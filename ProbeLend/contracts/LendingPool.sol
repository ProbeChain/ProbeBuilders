// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title LendingPool
 * @author ProbeBuilders
 * @notice Lending protocol with 150% collateralization for ProbeChain Rydberg Testnet.
 * @dev Supports deposit, borrow, repay, and liquidate with a simple collateral ratio model.
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

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

abstract contract Pausable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    function paused() public view returns (bool) { return _paused; }
    function _pause() internal { _paused = true; emit Paused(msg.sender); }
    function _unpause() internal { _paused = false; emit Unpaused(msg.sender); }
}

contract LendingPool is Ownable, ReentrancyGuard, Pausable {
    // ---- Constants ----
    uint256 public constant COLLATERAL_RATIO = 15000; // 150% in basis points
    uint256 public constant LIQUIDATION_BONUS = 10500; // 105% bonus to liquidator
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant INTEREST_RATE_PER_SECOND = 317097920; // ~1% APR in 1e18 per second
    uint256 public constant RATE_PRECISION = 1e18;

    struct Market {
        address token;
        uint256 totalDeposits;
        uint256 totalBorrows;
        uint256 lastAccrualTimestamp;
        uint256 borrowIndex; // cumulative interest index (scaled by 1e18)
        bool isActive;
    }

    struct UserPosition {
        uint256 depositAmount;
        uint256 borrowAmount;
        uint256 borrowIndex; // user's snapshot of borrowIndex at time of borrow
    }

    /// @notice token address => Market
    mapping(address => Market) public markets;
    address[] public marketList;

    /// @notice token => user => position
    mapping(address => mapping(address => UserPosition)) public positions;

    /// @notice Price oracle (simplified: token => price in USD with 18 decimals)
    mapping(address => uint256) public tokenPriceUSD;

    // ---- Events ----
    event MarketAdded(address indexed token);
    event PriceUpdated(address indexed token, uint256 price);
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event Borrow(address indexed user, address indexed token, uint256 amount);
    event Repay(address indexed user, address indexed token, uint256 amount);
    event Liquidation(address indexed liquidator, address indexed borrower, address indexed token, uint256 debtRepaid, uint256 collateralSeized);

    // ---- Market Management ----

    /// @notice Add a new lending market
    function addMarket(address token) external onlyOwner {
        require(!markets[token].isActive, "LendingPool: market exists");
        markets[token] = Market({
            token: token,
            totalDeposits: 0,
            totalBorrows: 0,
            lastAccrualTimestamp: block.timestamp,
            borrowIndex: RATE_PRECISION,
            isActive: true
        });
        marketList.push(token);
        emit MarketAdded(token);
    }

    /// @notice Set price for a token (owner acts as oracle)
    function setPrice(address token, uint256 priceUSD) external onlyOwner {
        tokenPriceUSD[token] = priceUSD;
        emit PriceUpdated(token, priceUSD);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ---- Interest Accrual ----

    function accrueInterest(address token) public {
        Market storage market = markets[token];
        if (!market.isActive) return;
        uint256 elapsed = block.timestamp - market.lastAccrualTimestamp;
        if (elapsed == 0) return;

        uint256 interestFactor = RATE_PRECISION + (INTEREST_RATE_PER_SECOND * elapsed);
        uint256 interestAccrued = (market.totalBorrows * INTEREST_RATE_PER_SECOND * elapsed) / RATE_PRECISION;
        market.totalBorrows += interestAccrued;
        market.borrowIndex = (market.borrowIndex * interestFactor) / RATE_PRECISION;
        market.lastAccrualTimestamp = block.timestamp;
    }

    // ---- Core Functions ----

    /// @notice Deposit tokens as collateral / lending supply
    function deposit(address token, uint256 amount) external nonReentrant whenNotPaused {
        require(markets[token].isActive, "LendingPool: market not active");
        require(amount > 0, "LendingPool: zero amount");
        accrueInterest(token);

        IERC20(token).transferFrom(msg.sender, address(this), amount);
        positions[token][msg.sender].depositAmount += amount;
        markets[token].totalDeposits += amount;

        emit Deposit(msg.sender, token, amount);
    }

    /// @notice Withdraw deposited tokens
    function withdraw(address token, uint256 amount) external nonReentrant {
        require(markets[token].isActive, "LendingPool: market not active");
        accrueInterest(token);

        UserPosition storage pos = positions[token][msg.sender];
        require(pos.depositAmount >= amount, "LendingPool: insufficient deposit");

        pos.depositAmount -= amount;
        markets[token].totalDeposits -= amount;

        // Check health factor remains valid after withdrawal
        require(_isHealthy(msg.sender), "LendingPool: unhealthy after withdraw");

        IERC20(token).transfer(msg.sender, amount);
        emit Withdraw(msg.sender, token, amount);
    }

    /// @notice Borrow tokens against collateral
    function borrow(address token, uint256 amount) external nonReentrant whenNotPaused {
        Market storage market = markets[token];
        require(market.isActive, "LendingPool: market not active");
        require(amount > 0, "LendingPool: zero amount");
        require(market.totalDeposits - market.totalBorrows >= amount, "LendingPool: insufficient liquidity");
        accrueInterest(token);

        UserPosition storage pos = positions[token][msg.sender];
        // Update user borrow with current index
        if (pos.borrowAmount > 0 && pos.borrowIndex > 0) {
            pos.borrowAmount = (pos.borrowAmount * market.borrowIndex) / pos.borrowIndex;
        }
        pos.borrowAmount += amount;
        pos.borrowIndex = market.borrowIndex;
        market.totalBorrows += amount;

        require(_isHealthy(msg.sender), "LendingPool: insufficient collateral");

        IERC20(token).transfer(msg.sender, amount);
        emit Borrow(msg.sender, token, amount);
    }

    /// @notice Repay borrowed tokens
    function repay(address token, uint256 amount) external nonReentrant {
        Market storage market = markets[token];
        require(market.isActive, "LendingPool: market not active");
        accrueInterest(token);

        UserPosition storage pos = positions[token][msg.sender];
        // Update user borrow
        if (pos.borrowIndex > 0) {
            pos.borrowAmount = (pos.borrowAmount * market.borrowIndex) / pos.borrowIndex;
        }
        uint256 repayAmount = amount > pos.borrowAmount ? pos.borrowAmount : amount;
        require(repayAmount > 0, "LendingPool: nothing to repay");

        IERC20(token).transferFrom(msg.sender, address(this), repayAmount);
        pos.borrowAmount -= repayAmount;
        pos.borrowIndex = market.borrowIndex;
        market.totalBorrows -= repayAmount;

        emit Repay(msg.sender, token, repayAmount);
    }

    /// @notice Liquidate an unhealthy position
    function liquidate(address borrower, address collateralToken, address debtToken, uint256 debtToRepay) external nonReentrant {
        accrueInterest(collateralToken);
        accrueInterest(debtToken);
        require(!_isHealthy(borrower), "LendingPool: position healthy");

        UserPosition storage debtPos = positions[debtToken][borrower];
        Market storage debtMarket = markets[debtToken];
        if (debtPos.borrowIndex > 0) {
            debtPos.borrowAmount = (debtPos.borrowAmount * debtMarket.borrowIndex) / debtPos.borrowIndex;
        }
        require(debtToRepay <= debtPos.borrowAmount, "LendingPool: excess repay");

        // Calculate collateral to seize (with 5% bonus)
        uint256 debtValueUSD = (debtToRepay * tokenPriceUSD[debtToken]) / 1e18;
        uint256 collateralToSeize = (debtValueUSD * LIQUIDATION_BONUS) / (tokenPriceUSD[collateralToken]);
        // Scale back to token amount
        collateralToSeize = (collateralToSeize * 1e18) / BASIS_POINTS;

        UserPosition storage collPos = positions[collateralToken][borrower];
        require(collPos.depositAmount >= collateralToSeize, "LendingPool: insufficient collateral");

        // Transfer debt from liquidator
        IERC20(debtToken).transferFrom(msg.sender, address(this), debtToRepay);
        debtPos.borrowAmount -= debtToRepay;
        debtPos.borrowIndex = debtMarket.borrowIndex;
        debtMarket.totalBorrows -= debtToRepay;

        // Seize collateral
        collPos.depositAmount -= collateralToSeize;
        markets[collateralToken].totalDeposits -= collateralToSeize;
        IERC20(collateralToken).transfer(msg.sender, collateralToSeize);

        emit Liquidation(msg.sender, borrower, debtToken, debtToRepay, collateralToSeize);
    }

    // ---- View Functions ----

    /// @notice Get user total collateral value in USD (18 decimals)
    function getUserCollateralUSD(address user) public view returns (uint256 totalUSD) {
        for (uint256 i = 0; i < marketList.length; i++) {
            address token = marketList[i];
            uint256 deposit_ = positions[token][user].depositAmount;
            if (deposit_ > 0) {
                totalUSD += (deposit_ * tokenPriceUSD[token]) / 1e18;
            }
        }
    }

    /// @notice Get user total borrow value in USD (18 decimals)
    function getUserBorrowUSD(address user) public view returns (uint256 totalUSD) {
        for (uint256 i = 0; i < marketList.length; i++) {
            address token = marketList[i];
            UserPosition storage pos = positions[token][user];
            if (pos.borrowAmount > 0) {
                uint256 currentBorrow = pos.borrowAmount;
                if (pos.borrowIndex > 0) {
                    currentBorrow = (currentBorrow * markets[token].borrowIndex) / pos.borrowIndex;
                }
                totalUSD += (currentBorrow * tokenPriceUSD[token]) / 1e18;
            }
        }
    }

    /// @notice Check if a user's position is healthy
    function _isHealthy(address user) internal view returns (bool) {
        uint256 collateral = getUserCollateralUSD(user);
        uint256 borrow = getUserBorrowUSD(user);
        if (borrow == 0) return true;
        return (collateral * BASIS_POINTS) / borrow >= COLLATERAL_RATIO;
    }

    /// @notice Public health check
    function isHealthy(address user) external view returns (bool) {
        return _isHealthy(user);
    }

    /// @notice Number of markets
    function marketCount() external view returns (uint256) {
        return marketList.length;
    }
}
