// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title RiskMonitor
 * @author ProbeBuilders
 * @notice DeFi position health monitor for ProbeChain Rydberg Testnet.
 *         Tracks collateral/debt positions and emits alerts when health drops below threshold.
 * @dev Inline Ownable, ReentrancyGuard, Pausable. EVM London compatible.
 */

/* ───────── Abstract helpers (inlined) ───────── */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed prev, address indexed next_);
    error OwnableUnauthorized();
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorized(); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardLocked();
    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardLocked();
        _status = 2;
        _;
        _status = 1;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();
    modifier whenNotPaused() { if (_paused) revert ContractPaused(); _; }
    modifier whenPaused() { if (!_paused) revert ContractNotPaused(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

/* ───────── Main Contract ───────── */

contract RiskMonitor is Ownable, ReentrancyGuard, Pausable {

    /* ── Constants ── */

    /// @notice Health factor precision (18 decimals)
    uint256 public constant PRECISION = 1e18;
    /// @notice Default liquidation alert threshold (1.2x = 120%)
    uint256 public constant DEFAULT_ALERT_THRESHOLD = 12e17; // 1.2 * 1e18

    /* ── Structs ── */

    /// @notice Represents a tracked DeFi position
    struct Position {
        address user;
        string  protocol;       // e.g. "ProbeLend"
        address collateralAsset;
        address debtAsset;
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 alertThreshold; // health factor threshold for alerts
        bool    active;
        uint256 createdAt;
        uint256 updatedAt;
    }

    /* ── State ── */

    uint256 public nextPositionId;
    mapping(uint256 => Position) public positions;
    mapping(address => uint256[]) private _userPositions;

    /// @notice Asset price in USD with 18 decimals, set by oracle
    mapping(address => uint256) public assetPrice;
    /// @notice Authorized oracle addresses
    mapping(address => bool) public oracles;

    /* ── Events ── */

    /// @notice Emitted when a position is registered
    event PositionRegistered(uint256 indexed positionId, address indexed user, string protocol, address collateral, address debt);
    /// @notice Emitted when asset price is updated
    event PriceUpdated(address indexed asset, uint256 oldPrice, uint256 newPrice, address indexed oracle);
    /// @notice Emitted when a position's health factor drops below threshold
    event LiquidateAlert(uint256 indexed positionId, address indexed user, uint256 healthFactor, uint256 threshold);
    /// @notice Emitted when a position is updated
    event PositionUpdated(uint256 indexed positionId, uint256 collateral, uint256 debt);
    /// @notice Emitted when a position is closed
    event PositionClosed(uint256 indexed positionId);
    /// @notice Emitted when an oracle is added or removed
    event OracleUpdated(address indexed oracle, bool status);

    /* ── Errors ── */

    error NotOracle();
    error NotPositionOwner();
    error PositionNotActive();
    error InvalidPrice();

    /* ── Modifiers ── */

    modifier onlyOracle() {
        if (!oracles[msg.sender] && msg.sender != owner()) revert NotOracle();
        _;
    }

    /* ── Constructor ── */

    constructor() Ownable() {
        oracles[msg.sender] = true;
    }

    /* ── Oracle management ── */

    /// @notice Add or remove an oracle address
    /// @param oracle The address to update
    /// @param status true to authorize, false to revoke
    function setOracle(address oracle, bool status) external onlyOwner {
        oracles[oracle] = status;
        emit OracleUpdated(oracle, status);
    }

    /* ── Core functions ── */

    /**
     * @notice Register a new DeFi position to monitor
     * @param user The position owner
     * @param protocol The protocol name
     * @param collateralAsset Collateral token address
     * @param debtAsset Debt token address
     * @param collateralAmount Collateral amount (token units)
     * @param debtAmount Debt amount (token units)
     * @return positionId The ID of the newly created position
     */
    function registerPosition(
        address user,
        string calldata protocol,
        address collateralAsset,
        address debtAsset,
        uint256 collateralAmount,
        uint256 debtAmount
    ) external whenNotPaused returns (uint256 positionId) {
        require(user != address(0), "zero user");
        require(collateralAsset != address(0), "zero collateral");
        require(collateralAmount > 0, "zero collateral amount");

        positionId = nextPositionId++;
        positions[positionId] = Position({
            user: user,
            protocol: protocol,
            collateralAsset: collateralAsset,
            debtAsset: debtAsset,
            collateralAmount: collateralAmount,
            debtAmount: debtAmount,
            alertThreshold: DEFAULT_ALERT_THRESHOLD,
            active: true,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        _userPositions[user].push(positionId);

        emit PositionRegistered(positionId, user, protocol, collateralAsset, debtAsset);
    }

    /**
     * @notice Update the price for an asset (oracle only)
     * @param asset Token address
     * @param price New price in USD with 18 decimals
     */
    function updatePrice(address asset, uint256 price) external onlyOracle whenNotPaused {
        if (price == 0) revert InvalidPrice();
        uint256 old = assetPrice[asset];
        assetPrice[asset] = price;
        emit PriceUpdated(asset, old, price, msg.sender);
    }

    /**
     * @notice Batch update multiple asset prices
     * @param assets Array of token addresses
     * @param prices Array of prices (USD, 18 decimals)
     */
    function batchUpdatePrices(address[] calldata assets, uint256[] calldata prices) external onlyOracle whenNotPaused {
        require(assets.length == prices.length, "length mismatch");
        for (uint256 i = 0; i < assets.length; i++) {
            if (prices[i] == 0) revert InvalidPrice();
            uint256 old = assetPrice[assets[i]];
            assetPrice[assets[i]] = prices[i];
            emit PriceUpdated(assets[i], old, prices[i], msg.sender);
        }
    }

    /**
     * @notice Check the health factor of a position
     * @param positionId The position to check
     * @return healthFactor The health factor with 18 decimals (1e18 = 1.0)
     */
    function checkHealth(uint256 positionId) public view returns (uint256 healthFactor) {
        Position storage pos = positions[positionId];
        if (!pos.active) return type(uint256).max;
        if (pos.debtAmount == 0) return type(uint256).max;

        uint256 collPrice = assetPrice[pos.collateralAsset];
        uint256 debtPrice = assetPrice[pos.debtAsset];

        if (collPrice == 0 || debtPrice == 0) return type(uint256).max; // price not set

        uint256 collValue = pos.collateralAmount * collPrice / PRECISION;
        uint256 debtValue = pos.debtAmount * debtPrice / PRECISION;

        if (debtValue == 0) return type(uint256).max;

        healthFactor = collValue * PRECISION / debtValue;
    }

    /**
     * @notice Evaluate a position and emit alert if unhealthy. Anyone can call.
     * @param positionId The position to evaluate
     * @return healthFactor The current health factor
     * @return isAlert Whether the health is below threshold
     */
    function evaluatePosition(uint256 positionId) external returns (uint256 healthFactor, bool isAlert) {
        Position storage pos = positions[positionId];
        if (!pos.active) return (type(uint256).max, false);

        healthFactor = checkHealth(positionId);
        isAlert = healthFactor < pos.alertThreshold;

        if (isAlert) {
            emit LiquidateAlert(positionId, pos.user, healthFactor, pos.alertThreshold);
        }
    }

    /**
     * @notice Update position collateral and debt amounts
     * @param positionId The position to update
     * @param collateralAmount New collateral amount
     * @param debtAmount New debt amount
     */
    function updatePosition(uint256 positionId, uint256 collateralAmount, uint256 debtAmount) external whenNotPaused {
        Position storage pos = positions[positionId];
        if (pos.user != msg.sender && msg.sender != owner()) revert NotPositionOwner();
        if (!pos.active) revert PositionNotActive();

        pos.collateralAmount = collateralAmount;
        pos.debtAmount = debtAmount;
        pos.updatedAt = block.timestamp;

        emit PositionUpdated(positionId, collateralAmount, debtAmount);
    }

    /**
     * @notice Set custom alert threshold for a position
     * @param positionId The position
     * @param threshold New threshold (18 decimals, e.g. 1.5e18)
     */
    function setAlertThreshold(uint256 positionId, uint256 threshold) external {
        Position storage pos = positions[positionId];
        if (pos.user != msg.sender) revert NotPositionOwner();
        require(threshold > PRECISION, "threshold too low");
        pos.alertThreshold = threshold;
    }

    /**
     * @notice Close a position (stop monitoring)
     * @param positionId The position to close
     */
    function closePosition(uint256 positionId) external {
        Position storage pos = positions[positionId];
        if (pos.user != msg.sender && msg.sender != owner()) revert NotPositionOwner();
        if (!pos.active) revert PositionNotActive();
        pos.active = false;
        emit PositionClosed(positionId);
    }

    /* ── View helpers ── */

    /// @notice Get all position IDs for a user
    function getUserPositions(address user) external view returns (uint256[] memory) {
        return _userPositions[user];
    }

    /// @notice Batch check health of multiple positions
    function batchCheckHealth(uint256[] calldata positionIds) external view returns (uint256[] memory factors) {
        factors = new uint256[](positionIds.length);
        for (uint256 i = 0; i < positionIds.length; i++) {
            factors[i] = checkHealth(positionIds[i]);
        }
    }
}
