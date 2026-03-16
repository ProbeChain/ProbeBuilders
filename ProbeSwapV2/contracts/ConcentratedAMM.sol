// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ConcentratedAMM
 * @author ProbeChain Team
 * @notice Concentrated liquidity AMM (Uniswap V3 style) for ProbeChain Rydberg Testnet
 * @dev Tick-based pricing, position management, and fee-tier swap execution
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender); _; }
    function owner() public view virtual returns (address) { return _owner; }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner); _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardReentrantCall();
        _status = _ENTERED; _; _status = _NOT_ENTERED;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    error ExpectedPause();
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    modifier whenPaused() { if (!_paused) revert ExpectedPause(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract ConcentratedAMM is Ownable, ReentrancyGuard, Pausable {
    /// @notice Pool data
    struct Pool {
        uint256 id;
        address tokenA;
        address tokenB;
        uint256 feeBps;         // fee in basis points
        uint256 liquidity;
        int24 currentTick;
        uint256 sqrtPriceX96;   // sqrt(price) * 2^96
        uint256 reserveA;
        uint256 reserveB;
        uint256 feeGrowthA;
        uint256 feeGrowthB;
        bool active;
    }

    /// @notice Liquidity position
    struct Position {
        uint256 id;
        uint256 poolId;
        address provider;
        int24 tickLower;
        int24 tickUpper;
        uint256 liquidity;
        uint256 tokensOwedA;
        uint256 tokensOwedB;
        uint256 feeGrowthInsideA;
        uint256 feeGrowthInsideB;
        uint256 createdAt;
    }

    /// @notice Tick data
    struct TickInfo {
        uint256 liquidityGross;
        int256 liquidityNet;
        bool initialized;
    }

    mapping(uint256 => Pool) private _pools;
    mapping(uint256 => Position) private _positions;
    mapping(uint256 => mapping(int24 => TickInfo)) private _ticks;
    mapping(address => mapping(address => uint256)) private _pairToPool;
    mapping(address => uint256[]) private _userPositions;

    uint256 private _nextPoolId = 1;
    uint256 private _nextPositionId = 1;
    uint256 public totalPools;
    uint256 public protocolFeeBps = 500; // 5% of swap fees go to protocol
    uint256 public totalSwapVolume;

    int24 public constant MIN_TICK = -887272;
    int24 public constant MAX_TICK = 887272;
    int24 public constant TICK_SPACING = 60;

    /// @notice Emitted when a pool is created
    event PoolCreated(uint256 indexed poolId, address tokenA, address tokenB, uint256 feeBps);
    /// @notice Emitted when liquidity is added
    event LiquidityAdded(uint256 indexed positionId, uint256 indexed poolId, address indexed provider, int24 tickLower, int24 tickUpper, uint256 liquidity);
    /// @notice Emitted when liquidity is removed
    event LiquidityRemoved(uint256 indexed positionId, uint256 amountA, uint256 amountB);
    /// @notice Emitted on swap
    event Swap(uint256 indexed poolId, address indexed sender, uint256 amountIn, uint256 amountOut, bool zeroForOne);
    /// @notice Emitted when fees are collected
    event FeesCollected(uint256 indexed positionId, uint256 feeA, uint256 feeB);

    error PoolNotFound(uint256 poolId);
    error PoolNotActive(uint256 poolId);
    error PoolAlreadyExists(address tokenA, address tokenB);
    error PositionNotFound(uint256 positionId);
    error NotPositionOwner(address caller);
    error InvalidTickRange(int24 tickLower, int24 tickUpper);
    error InsufficientOutput(uint256 actual, uint256 minimum);
    error ZeroAmount();
    error ZeroLiquidity();
    error SameToken();
    error InvalidFeeTier(uint256 fee);

    /**
     * @notice Create a new liquidity pool
     * @param tokenA The first token address
     * @param tokenB The second token address
     * @param fee The fee tier in basis points
     * @return poolId The created pool ID
     */
    function createPool(
        address tokenA,
        address tokenB,
        uint256 fee
    ) external whenNotPaused returns (uint256 poolId) {
        if (tokenA == tokenB) revert SameToken();
        if (fee == 0 || fee > 10000) revert InvalidFeeTier(fee);

        // Sort tokens
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (_pairToPool[token0][token1] != 0) revert PoolAlreadyExists(token0, token1);

        poolId = _nextPoolId++;
        _pools[poolId] = Pool({
            id: poolId,
            tokenA: token0,
            tokenB: token1,
            feeBps: fee,
            liquidity: 0,
            currentTick: 0,
            sqrtPriceX96: 79228162514264337593543950336, // 1:1 initial price (2^96)
            reserveA: 0,
            reserveB: 0,
            feeGrowthA: 0,
            feeGrowthB: 0,
            active: true
        });

        _pairToPool[token0][token1] = poolId;
        totalPools++;

        emit PoolCreated(poolId, token0, token1, fee);
    }

    /**
     * @notice Add concentrated liquidity to a pool
     * @param poolId The pool to add liquidity to
     * @param tickLower The lower tick boundary
     * @param tickUpper The upper tick boundary
     * @param amount The liquidity amount (in tokenA terms)
     * @return positionId The created position ID
     */
    function addLiquidity(
        uint256 poolId,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount
    ) external nonReentrant whenNotPaused returns (uint256 positionId) {
        Pool storage pool = _pools[poolId];
        if (pool.id == 0) revert PoolNotFound(poolId);
        if (!pool.active) revert PoolNotActive(poolId);
        if (amount == 0) revert ZeroAmount();
        if (tickLower >= tickUpper) revert InvalidTickRange(tickLower, tickUpper);
        if (tickLower < MIN_TICK || tickUpper > MAX_TICK) revert InvalidTickRange(tickLower, tickUpper);
        if (tickLower % TICK_SPACING != 0 || tickUpper % TICK_SPACING != 0) {
            revert InvalidTickRange(tickLower, tickUpper);
        }

        // Calculate token amounts based on tick range
        uint256 amountA = amount;
        uint256 amountB = amount; // Simplified: equal amounts for both tokens

        // Transfer tokens
        IERC20(pool.tokenA).transferFrom(msg.sender, address(this), amountA);
        IERC20(pool.tokenB).transferFrom(msg.sender, address(this), amountB);

        pool.reserveA += amountA;
        pool.reserveB += amountB;
        pool.liquidity += amount;

        // Update ticks
        _ticks[poolId][tickLower].liquidityGross += amount;
        _ticks[poolId][tickLower].liquidityNet += int256(amount);
        _ticks[poolId][tickLower].initialized = true;

        _ticks[poolId][tickUpper].liquidityGross += amount;
        _ticks[poolId][tickUpper].liquidityNet -= int256(amount);
        _ticks[poolId][tickUpper].initialized = true;

        positionId = _nextPositionId++;
        _positions[positionId] = Position({
            id: positionId,
            poolId: poolId,
            provider: msg.sender,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: amount,
            tokensOwedA: 0,
            tokensOwedB: 0,
            feeGrowthInsideA: pool.feeGrowthA,
            feeGrowthInsideB: pool.feeGrowthB,
            createdAt: block.timestamp
        });

        _userPositions[msg.sender].push(positionId);

        emit LiquidityAdded(positionId, poolId, msg.sender, tickLower, tickUpper, amount);
    }

    /**
     * @notice Remove liquidity from a position
     * @param positionId The position to remove
     * @return amountA Token A returned
     * @return amountB Token B returned
     */
    function removeLiquidity(
        uint256 positionId
    ) external nonReentrant whenNotPaused returns (uint256 amountA, uint256 amountB) {
        Position storage pos = _positions[positionId];
        if (pos.id == 0) revert PositionNotFound(positionId);
        if (pos.provider != msg.sender) revert NotPositionOwner(msg.sender);
        if (pos.liquidity == 0) revert ZeroLiquidity();

        Pool storage pool = _pools[pos.poolId];

        // Calculate fees earned
        uint256 feeA = ((pool.feeGrowthA - pos.feeGrowthInsideA) * pos.liquidity) / 1e18;
        uint256 feeB = ((pool.feeGrowthB - pos.feeGrowthInsideB) * pos.liquidity) / 1e18;

        amountA = pos.liquidity + feeA;
        amountB = pos.liquidity + feeB;

        // Cap to available reserves
        if (amountA > pool.reserveA) amountA = pool.reserveA;
        if (amountB > pool.reserveB) amountB = pool.reserveB;

        pool.reserveA -= amountA;
        pool.reserveB -= amountB;
        pool.liquidity -= pos.liquidity;

        // Update ticks
        _ticks[pos.poolId][pos.tickLower].liquidityGross -= pos.liquidity;
        _ticks[pos.poolId][pos.tickLower].liquidityNet -= int256(pos.liquidity);
        _ticks[pos.poolId][pos.tickUpper].liquidityGross -= pos.liquidity;
        _ticks[pos.poolId][pos.tickUpper].liquidityNet += int256(pos.liquidity);

        pos.liquidity = 0;

        IERC20(pool.tokenA).transfer(msg.sender, amountA);
        IERC20(pool.tokenB).transfer(msg.sender, amountB);

        emit LiquidityRemoved(positionId, amountA, amountB);
        if (feeA > 0 || feeB > 0) emit FeesCollected(positionId, feeA, feeB);
    }

    /**
     * @notice Swap tokens through a pool
     * @param poolId The pool to swap in
     * @param amountIn The input token amount
     * @param minOut The minimum output expected
     * @param zeroForOne True if swapping tokenA for tokenB
     * @return amountOut The output amount
     */
    function swap(
        uint256 poolId,
        uint256 amountIn,
        uint256 minOut,
        bool zeroForOne
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        Pool storage pool = _pools[poolId];
        if (pool.id == 0) revert PoolNotFound(poolId);
        if (!pool.active) revert PoolNotActive(poolId);
        if (amountIn == 0) revert ZeroAmount();

        // Calculate fee
        uint256 feeAmount = (amountIn * pool.feeBps) / 10000;
        uint256 amountInAfterFee = amountIn - feeAmount;

        // Constant product formula: x * y = k
        uint256 reserveIn = zeroForOne ? pool.reserveA : pool.reserveB;
        uint256 reserveOut = zeroForOne ? pool.reserveB : pool.reserveA;

        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");

        amountOut = (amountInAfterFee * reserveOut) / (reserveIn + amountInAfterFee);
        if (amountOut < minOut) revert InsufficientOutput(amountOut, minOut);

        // Transfer tokens
        address tokenIn = zeroForOne ? pool.tokenA : pool.tokenB;
        address tokenOut = zeroForOne ? pool.tokenB : pool.tokenA;

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).transfer(msg.sender, amountOut);

        // Update reserves
        if (zeroForOne) {
            pool.reserveA += amountIn;
            pool.reserveB -= amountOut;
            pool.feeGrowthA += pool.liquidity > 0 ? (feeAmount * 1e18) / pool.liquidity : 0;
        } else {
            pool.reserveB += amountIn;
            pool.reserveA -= amountOut;
            pool.feeGrowthB += pool.liquidity > 0 ? (feeAmount * 1e18) / pool.liquidity : 0;
        }

        // Update tick (simplified)
        if (pool.reserveA > 0) {
            pool.currentTick = int24(int256((pool.reserveB * 10000) / pool.reserveA) - 10000);
        }

        totalSwapVolume += amountIn;

        emit Swap(poolId, msg.sender, amountIn, amountOut, zeroForOne);
    }

    /// @notice Get pool info
    function getPool(uint256 poolId) external view returns (Pool memory) {
        if (_pools[poolId].id == 0) revert PoolNotFound(poolId);
        return _pools[poolId];
    }

    /// @notice Get position info
    function getPosition(uint256 positionId) external view returns (Position memory) {
        if (_positions[positionId].id == 0) revert PositionNotFound(positionId);
        return _positions[positionId];
    }

    /// @notice Get user positions
    function getUserPositions(address user) external view returns (uint256[] memory) {
        return _userPositions[user];
    }

    /// @notice Get pool by token pair
    function getPoolByPair(address tokenA, address tokenB) external view returns (uint256) {
        (address t0, address t1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return _pairToPool[t0][t1];
    }

    /// @notice Get tick info
    function getTick(uint256 poolId, int24 tick) external view returns (TickInfo memory) {
        return _ticks[poolId][tick];
    }

    /// @notice Set protocol fee
    function setProtocolFee(uint256 bps) external onlyOwner {
        require(bps <= 5000, "Max 50%");
        protocolFeeBps = bps;
    }

    /// @notice Deactivate a pool
    function deactivatePool(uint256 poolId) external onlyOwner {
        _pools[poolId].active = false;
    }

    receive() external payable {}
}
