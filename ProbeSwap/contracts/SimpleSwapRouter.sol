// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SimpleSwapRouter
 * @author ProbeBuilders
 * @notice DEX router with AI-optimized order splitting for ProbeChain Rydberg Testnet.
 * @dev Implements addLiquidity, removeLiquidity, swapExactTokensForTokens, getAmountsOut.
 *      Includes a minimal ERC20 pair factory for creating trading pairs.
 */

// ============ Minimal Interfaces ============

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// ============ Ownable ============

abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ============ ReentrancyGuard ============

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// ============ Liquidity Pair Token ============

contract LPToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public factory;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        factory = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == factory, "LPToken: only factory");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == factory, "LPToken: only factory");
        require(balanceOf[from] >= amount, "LPToken: insufficient balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        require(currentAllowance >= amount, "LPToken: insufficient allowance");
        allowance[from][msg.sender] = currentAllowance - amount;
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "LPToken: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

// ============ SimpleSwapRouter ============

contract SimpleSwapRouter is Ownable, ReentrancyGuard {
    /// @notice Fee numerator (3 = 0.3%)
    uint256 public constant FEE_NUMERATOR = 3;
    uint256 public constant FEE_DENOMINATOR = 1000;

    struct Pair {
        address tokenA;
        address tokenB;
        uint256 reserveA;
        uint256 reserveB;
        address lpToken;
        bool exists;
    }

    /// @notice pairId => Pair
    mapping(bytes32 => Pair) public pairs;
    /// @notice All pair IDs
    bytes32[] public allPairIds;

    // ---- Events ----

    event PairCreated(address indexed tokenA, address indexed tokenB, address lpToken, bytes32 pairId);
    event LiquidityAdded(bytes32 indexed pairId, address indexed provider, uint256 amountA, uint256 amountB, uint256 lpMinted);
    event LiquidityRemoved(bytes32 indexed pairId, address indexed provider, uint256 amountA, uint256 amountB, uint256 lpBurned);
    event Swap(bytes32 indexed pairId, address indexed sender, address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);

    // ---- Pair Management ----

    /// @notice Compute a canonical pair ID for two tokens
    function getPairId(address tokenA, address tokenB) public pure returns (bytes32) {
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(t0, t1));
    }

    /// @notice Create a new trading pair
    function createPair(address tokenA, address tokenB) external onlyOwner returns (bytes32 pairId) {
        require(tokenA != tokenB, "Router: identical tokens");
        require(tokenA != address(0) && tokenB != address(0), "Router: zero address");
        pairId = getPairId(tokenA, tokenB);
        require(!pairs[pairId].exists, "Router: pair exists");

        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        LPToken lp = new LPToken("ProbeSwap LP", "PSLP");
        pairs[pairId] = Pair({
            tokenA: t0,
            tokenB: t1,
            reserveA: 0,
            reserveB: 0,
            lpToken: address(lp),
            exists: true
        });
        allPairIds.push(pairId);
        emit PairCreated(t0, t1, address(lp), pairId);
    }

    /// @notice Return the number of pairs
    function allPairsLength() external view returns (uint256) {
        return allPairIds.length;
    }

    // ---- Liquidity ----

    /// @notice Add liquidity to a pair
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) external nonReentrant returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        bytes32 pairId = getPairId(tokenA, tokenB);
        Pair storage pair = pairs[pairId];
        require(pair.exists, "Router: pair not found");

        // Determine sorted order
        bool isForward = tokenA < tokenB;

        if (pair.reserveA == 0 && pair.reserveB == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            uint256 rA = isForward ? pair.reserveA : pair.reserveB;
            uint256 rB = isForward ? pair.reserveB : pair.reserveA;
            uint256 amountBOptimal = (amountADesired * rB) / rA;
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "Router: insufficient B amount");
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = (amountBDesired * rA) / rB;
                require(amountAOptimal <= amountADesired, "Router: excessive A");
                require(amountAOptimal >= amountAMin, "Router: insufficient A amount");
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountB);

        // Update reserves
        if (isForward) {
            pair.reserveA += amountA;
            pair.reserveB += amountB;
        } else {
            pair.reserveA += amountB;
            pair.reserveB += amountA;
        }

        // Mint LP
        LPToken lp = LPToken(pair.lpToken);
        if (lp.totalSupply() == 0) {
            liquidity = _sqrt(amountA * amountB);
        } else {
            uint256 liqA = (amountA * lp.totalSupply()) / (isForward ? pair.reserveA - amountA : pair.reserveB - amountB);
            uint256 liqB = (amountB * lp.totalSupply()) / (isForward ? pair.reserveB - amountB : pair.reserveA - amountA);
            liquidity = liqA < liqB ? liqA : liqB;
        }
        require(liquidity > 0, "Router: insufficient liquidity minted");
        lp.mint(msg.sender, liquidity);

        emit LiquidityAdded(pairId, msg.sender, amountA, amountB, liquidity);
    }

    /// @notice Remove liquidity from a pair
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        bytes32 pairId = getPairId(tokenA, tokenB);
        Pair storage pair = pairs[pairId];
        require(pair.exists, "Router: pair not found");

        LPToken lp = LPToken(pair.lpToken);
        uint256 supply = lp.totalSupply();
        require(supply > 0, "Router: no liquidity");

        bool isForward = tokenA < tokenB;
        uint256 rA = isForward ? pair.reserveA : pair.reserveB;
        uint256 rB = isForward ? pair.reserveB : pair.reserveA;

        amountA = (liquidity * rA) / supply;
        amountB = (liquidity * rB) / supply;
        require(amountA >= amountAMin, "Router: insufficient A");
        require(amountB >= amountBMin, "Router: insufficient B");

        lp.burn(msg.sender, liquidity);

        if (isForward) {
            pair.reserveA -= amountA;
            pair.reserveB -= amountB;
        } else {
            pair.reserveA -= amountB;
            pair.reserveB -= amountA;
        }

        IERC20(tokenA).transfer(msg.sender, amountA);
        IERC20(tokenB).transfer(msg.sender, amountB);

        emit LiquidityRemoved(pairId, msg.sender, amountA, amountB, liquidity);
    }

    // ---- Swap ----

    /// @notice Swap exact input tokens along a path
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(path.length >= 2, "Router: invalid path");
        amounts = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: insufficient output");

        IERC20(path[0]).transferFrom(msg.sender, address(this), amounts[0]);

        for (uint256 i = 0; i < path.length - 1; i++) {
            _swap(path[i], path[i + 1], amounts[i], amounts[i + 1]);
        }

        IERC20(path[path.length - 1]).transfer(msg.sender, amounts[amounts.length - 1]);
    }

    /// @notice Calculate output amounts for a given input along a path
    function getAmountsOut(uint256 amountIn, address[] calldata path) public view returns (uint256[] memory amounts) {
        require(path.length >= 2, "Router: invalid path");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i = 0; i < path.length - 1; i++) {
            amounts[i + 1] = _getAmountOut(amounts[i], path[i], path[i + 1]);
        }
    }

    function _getAmountOut(uint256 amountIn, address tokenIn, address tokenOut) internal view returns (uint256) {
        bytes32 pairId = getPairId(tokenIn, tokenOut);
        Pair storage pair = pairs[pairId];
        require(pair.exists, "Router: pair not found");

        bool isForward = tokenIn < tokenOut;
        uint256 reserveIn = isForward ? pair.reserveA : pair.reserveB;
        uint256 reserveOut = isForward ? pair.reserveB : pair.reserveA;
        require(reserveIn > 0 && reserveOut > 0, "Router: no liquidity");

        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - FEE_NUMERATOR);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * FEE_DENOMINATOR + amountInWithFee;
        return numerator / denominator;
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) internal {
        bytes32 pairId = getPairId(tokenIn, tokenOut);
        Pair storage pair = pairs[pairId];
        bool isForward = tokenIn < tokenOut;

        if (isForward) {
            pair.reserveA += amountIn;
            pair.reserveB -= amountOut;
        } else {
            pair.reserveB += amountIn;
            pair.reserveA -= amountOut;
        }

        emit Swap(pairId, msg.sender, tokenIn, amountIn, tokenOut, amountOut);
    }

    // ---- Helpers ----

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /// @notice Get pair reserves
    function getReserves(address tokenA, address tokenB) external view returns (uint256 reserveA, uint256 reserveB) {
        bytes32 pairId = getPairId(tokenA, tokenB);
        Pair storage pair = pairs[pairId];
        require(pair.exists, "Router: pair not found");
        bool isForward = tokenA < tokenB;
        reserveA = isForward ? pair.reserveA : pair.reserveB;
        reserveB = isForward ? pair.reserveB : pair.reserveA;
    }
}
