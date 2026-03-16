// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ArbExecutor
 * @author ProbeBuilders
 * @notice Arbitrage execution contract with profit tracking for ProbeChain Rydberg Testnet.
 * @dev Supports multi-hop arbitrage paths, owner-only execution, flash-loan compatible interface.
 */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ISwapRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path
    ) external returns (uint256[] memory amounts);
}

interface IFlashLoanReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
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

// ============ ArbExecutor ============

contract ArbExecutor is Ownable, ReentrancyGuard, IFlashLoanReceiver {
    // ---- State ----
    uint256 public totalProfitETH;
    uint256 public totalTradesExecuted;
    uint256 public minProfitThreshold;

    /// @notice Whitelisted DEX routers
    mapping(address => bool) public whitelistedRouters;

    struct TradeRecord {
        uint256 timestamp;
        address tokenIn;
        uint256 amountIn;
        uint256 profit;
        address[] path;
    }

    TradeRecord[] public tradeHistory;

    // ---- Events ----
    event ArbitrageExecuted(uint256 indexed tradeId, address indexed tokenIn, uint256 amountIn, uint256 profit);
    event RouterWhitelisted(address indexed router, bool status);
    event ProfitWithdrawn(address indexed to, address indexed token, uint256 amount);
    event MinProfitUpdated(uint256 newThreshold);
    event FlashLoanExecuted(address indexed asset, uint256 amount, uint256 premium);

    constructor(uint256 _minProfitThreshold) {
        minProfitThreshold = _minProfitThreshold;
    }

    // ---- Configuration ----

    /// @notice Whitelist or remove a DEX router
    function setRouterWhitelist(address router, bool status) external onlyOwner {
        whitelistedRouters[router] = status;
        emit RouterWhitelisted(router, status);
    }

    /// @notice Update minimum profit threshold
    function setMinProfitThreshold(uint256 _threshold) external onlyOwner {
        minProfitThreshold = _threshold;
        emit MinProfitUpdated(_threshold);
    }

    // ---- Arbitrage Execution ----

    /// @notice Execute a multi-hop arbitrage through a single DEX router
    /// @param router The DEX router to use
    /// @param path Token swap path (must start and end with same token for circular arb)
    /// @param amountIn Input amount
    /// @param minProfit Minimum acceptable profit
    function executeArbitrage(
        address router,
        address[] calldata path,
        uint256 amountIn,
        uint256 minProfit
    ) external onlyOwner nonReentrant returns (uint256 profit) {
        require(whitelistedRouters[router], "ArbExecutor: router not whitelisted");
        require(path.length >= 2, "ArbExecutor: invalid path");
        require(path[0] == path[path.length - 1], "ArbExecutor: not circular path");

        address tokenIn = path[0];
        uint256 balanceBefore = IERC20(tokenIn).balanceOf(address(this));
        require(balanceBefore >= amountIn, "ArbExecutor: insufficient balance");

        // Approve and swap
        IERC20(tokenIn).approve(router, amountIn);
        ISwapRouter(router).swapExactTokensForTokens(amountIn, 0, path);

        uint256 balanceAfter = IERC20(tokenIn).balanceOf(address(this));
        require(balanceAfter > balanceBefore, "ArbExecutor: no profit");
        profit = balanceAfter - balanceBefore;
        require(profit >= minProfit, "ArbExecutor: profit below minimum");
        require(profit >= minProfitThreshold, "ArbExecutor: below threshold");

        totalProfitETH += profit;
        totalTradesExecuted++;

        tradeHistory.push(TradeRecord({
            timestamp: block.timestamp,
            tokenIn: tokenIn,
            amountIn: amountIn,
            profit: profit,
            path: path
        }));

        emit ArbitrageExecuted(totalTradesExecuted - 1, tokenIn, amountIn, profit);
    }

    /// @notice Execute arbitrage across two different DEX routers
    function executeSplitArbitrage(
        address routerA,
        address routerB,
        address[] calldata pathA,
        address[] calldata pathB,
        uint256 amountIn,
        uint256 minProfit
    ) external onlyOwner nonReentrant returns (uint256 profit) {
        require(whitelistedRouters[routerA] && whitelistedRouters[routerB], "ArbExecutor: router not whitelisted");
        require(pathA.length >= 2 && pathB.length >= 2, "ArbExecutor: invalid paths");
        require(pathA[pathA.length - 1] == pathB[0], "ArbExecutor: paths not connected");

        address tokenIn = pathA[0];
        address tokenOut = pathB[pathB.length - 1];
        require(tokenIn == tokenOut, "ArbExecutor: not circular");

        uint256 balanceBefore = IERC20(tokenIn).balanceOf(address(this));

        // Leg A
        IERC20(tokenIn).approve(routerA, amountIn);
        uint256[] memory amountsA = ISwapRouter(routerA).swapExactTokensForTokens(amountIn, 0, pathA);

        // Leg B
        address midToken = pathA[pathA.length - 1];
        uint256 midAmount = amountsA[amountsA.length - 1];
        IERC20(midToken).approve(routerB, midAmount);
        ISwapRouter(routerB).swapExactTokensForTokens(midAmount, 0, pathB);

        uint256 balanceAfter = IERC20(tokenIn).balanceOf(address(this));
        require(balanceAfter > balanceBefore, "ArbExecutor: no profit");
        profit = balanceAfter - balanceBefore;
        require(profit >= minProfit, "ArbExecutor: profit below minimum");

        totalProfitETH += profit;
        totalTradesExecuted++;

        emit ArbitrageExecuted(totalTradesExecuted - 1, tokenIn, amountIn, profit);
    }

    // ---- Flash Loan Callback ----

    /// @notice Callback for flash loan providers (e.g., Aave-style)
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(initiator == address(this), "ArbExecutor: invalid initiator");

        // Decode params: (address router, address[] path)
        (address router, address[] memory path) = abi.decode(params, (address, address[]));
        require(whitelistedRouters[router], "ArbExecutor: router not whitelisted");

        IERC20(asset).approve(router, amount);
        ISwapRouter(router).swapExactTokensForTokens(amount, 0, path);

        // Ensure we can repay flash loan + premium
        uint256 amountOwed = amount + premium;
        uint256 balance = IERC20(asset).balanceOf(address(this));
        require(balance >= amountOwed, "ArbExecutor: cannot repay flash loan");

        // Approve repayment to msg.sender (the flash loan pool)
        IERC20(asset).approve(msg.sender, amountOwed);

        uint256 profit = balance - amountOwed;
        totalProfitETH += profit;
        totalTradesExecuted++;

        emit FlashLoanExecuted(asset, amount, premium);
        return true;
    }

    // ---- Fund Management ----

    /// @notice Withdraw profits or tokens
    function withdrawToken(address token, uint256 amount, address to) external onlyOwner {
        require(to != address(0), "ArbExecutor: zero address");
        IERC20(token).transfer(to, amount);
        emit ProfitWithdrawn(to, token, amount);
    }

    /// @notice Withdraw native currency
    function withdrawETH(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "ArbExecutor: zero address");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "ArbExecutor: ETH transfer failed");
        emit ProfitWithdrawn(to, address(0), amount);
    }

    /// @notice Deposit tokens for arbitrage capital
    function depositToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    receive() external payable {}

    // ---- View Functions ----

    function tradeCount() external view returns (uint256) {
        return tradeHistory.length;
    }

    function getTradeRecord(uint256 index) external view returns (
        uint256 timestamp,
        address tokenIn,
        uint256 amountIn,
        uint256 profit
    ) {
        TradeRecord storage record = tradeHistory[index];
        return (record.timestamp, record.tokenIn, record.amountIn, record.profit);
    }
}
