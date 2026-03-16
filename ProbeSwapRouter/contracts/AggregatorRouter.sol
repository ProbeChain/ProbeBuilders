// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AggregatorRouter
 * @author ProbeBuilders
 * @notice DEX aggregator router that splits orders across multiple pools for ProbeChain.
 * @dev Includes price comparison, optimal routing, and multi-pool split execution.
 */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IDEXPool {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory);
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) external returns (uint256[] memory amounts);
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
        require(msg.sender == _owner, "Ownable: not owner");
        _;
    }

    function owner() public view returns (address) { return _owner; }

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

// ============ AggregatorRouter ============

contract AggregatorRouter is Ownable, ReentrancyGuard {
    // ---- State ----

    /// @notice Registered DEX pools
    address[] public registeredPools;
    mapping(address => bool) public isRegisteredPool;

    /// @notice Fee: 0.05% aggregator fee (5 / 10000)
    uint256 public feeBps = 5;
    uint256 public constant MAX_FEE_BPS = 50; // max 0.5%
    address public feeCollector;

    /// @notice Maximum number of split routes
    uint256 public constant MAX_SPLITS = 5;

    struct RouteQuote {
        address pool;
        uint256 amountOut;
    }

    struct SplitOrder {
        address pool;
        uint256 amountIn;
        uint256 minAmountOut;
    }

    // ---- Events ----
    event PoolRegistered(address indexed pool);
    event PoolRemoved(address indexed pool);
    event SwapExecuted(address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event SplitSwapExecuted(address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 totalIn, uint256 totalOut, uint256 splits);
    event FeeUpdated(uint256 newFeeBps);
    event FeeCollected(address indexed token, uint256 amount);

    constructor(address _feeCollector) {
        feeCollector = _feeCollector;
    }

    // ---- Pool Management ----

    /// @notice Register a DEX pool
    function registerPool(address pool) external onlyOwner {
        require(!isRegisteredPool[pool], "Aggregator: already registered");
        registeredPools.push(pool);
        isRegisteredPool[pool] = true;
        emit PoolRegistered(pool);
    }

    /// @notice Remove a DEX pool
    function removePool(address pool) external onlyOwner {
        require(isRegisteredPool[pool], "Aggregator: not registered");
        isRegisteredPool[pool] = false;
        // Remove from array
        for (uint256 i = 0; i < registeredPools.length; i++) {
            if (registeredPools[i] == pool) {
                registeredPools[i] = registeredPools[registeredPools.length - 1];
                registeredPools.pop();
                break;
            }
        }
        emit PoolRemoved(pool);
    }

    /// @notice Set aggregator fee
    function setFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= MAX_FEE_BPS, "Aggregator: fee too high");
        feeBps = _feeBps;
        emit FeeUpdated(_feeBps);
    }

    // ---- Price Comparison ----

    /// @notice Get quotes from all registered pools for a given swap
    function getQuotes(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (RouteQuote[] memory quotes) {
        quotes = new RouteQuote[](registeredPools.length);
        for (uint256 i = 0; i < registeredPools.length; i++) {
            address pool = registeredPools[i];
            try IDEXPool(pool).getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
                quotes[i] = RouteQuote({pool: pool, amountOut: amounts[amounts.length - 1]});
            } catch {
                quotes[i] = RouteQuote({pool: pool, amountOut: 0});
            }
        }
    }

    /// @notice Find the best single pool for a swap
    function getBestQuote(
        uint256 amountIn,
        address[] calldata path
    ) public view returns (address bestPool, uint256 bestAmountOut) {
        for (uint256 i = 0; i < registeredPools.length; i++) {
            address pool = registeredPools[i];
            try IDEXPool(pool).getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
                uint256 out = amounts[amounts.length - 1];
                if (out > bestAmountOut) {
                    bestAmountOut = out;
                    bestPool = pool;
                }
            } catch {
                continue;
            }
        }
    }

    // ---- Single Pool Swap ----

    /// @notice Swap through the best single pool
    function swapBestPool(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) external nonReentrant returns (uint256 amountOut) {
        require(path.length >= 2, "Aggregator: invalid path");

        (address bestPool, uint256 expectedOut) = getBestQuote(amountIn, path);
        require(bestPool != address(0), "Aggregator: no pool found");
        require(expectedOut >= amountOutMin, "Aggregator: insufficient output");

        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        // Collect fee
        uint256 fee = (amountIn * feeBps) / 10000;
        uint256 swapAmount = amountIn - fee;

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        if (fee > 0) {
            IERC20(tokenIn).transfer(feeCollector, fee);
            emit FeeCollected(tokenIn, fee);
        }

        IERC20(tokenIn).approve(bestPool, swapAmount);
        uint256[] memory amounts = IDEXPool(bestPool).swapExactTokensForTokens(swapAmount, amountOutMin, path);
        amountOut = amounts[amounts.length - 1];

        IERC20(tokenOut).transfer(msg.sender, amountOut);
        emit SwapExecuted(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    // ---- Split Order Execution ----

    /// @notice Execute a split order across multiple pools
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param splits Array of split orders
    /// @param path Swap path for each split
    function executeSplitSwap(
        address tokenIn,
        address tokenOut,
        SplitOrder[] calldata splits,
        address[] calldata path
    ) external nonReentrant returns (uint256 totalOut) {
        require(splits.length > 0 && splits.length <= MAX_SPLITS, "Aggregator: invalid splits");
        require(path.length >= 2, "Aggregator: invalid path");
        require(path[0] == tokenIn && path[path.length - 1] == tokenOut, "Aggregator: path mismatch");

        uint256 totalIn = 0;
        for (uint256 i = 0; i < splits.length; i++) {
            require(isRegisteredPool[splits[i].pool], "Aggregator: pool not registered");
            totalIn += splits[i].amountIn;
        }

        // Transfer total input from user
        IERC20(tokenIn).transferFrom(msg.sender, address(this), totalIn);

        // Collect fee
        uint256 fee = (totalIn * feeBps) / 10000;
        uint256 remainingIn = totalIn - fee;
        if (fee > 0) {
            IERC20(tokenIn).transfer(feeCollector, fee);
            emit FeeCollected(tokenIn, fee);
        }

        // Execute each split proportionally (adjust for fee)
        for (uint256 i = 0; i < splits.length; i++) {
            uint256 adjustedIn = (splits[i].amountIn * remainingIn) / totalIn;
            if (adjustedIn == 0) continue;

            IERC20(tokenIn).approve(splits[i].pool, adjustedIn);
            uint256[] memory amounts = IDEXPool(splits[i].pool).swapExactTokensForTokens(
                adjustedIn,
                splits[i].minAmountOut,
                path
            );
            totalOut += amounts[amounts.length - 1];
        }

        IERC20(tokenOut).transfer(msg.sender, totalOut);
        emit SplitSwapExecuted(msg.sender, tokenIn, tokenOut, totalIn, totalOut, splits.length);
    }

    // ---- Admin ----

    /// @notice Rescue stuck tokens
    function rescueTokens(address token, uint256 amount, address to) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    function setFeeCollector(address _collector) external onlyOwner {
        require(_collector != address(0), "Aggregator: zero address");
        feeCollector = _collector;
    }

    function poolCount() external view returns (uint256) {
        return registeredPools.length;
    }
}
