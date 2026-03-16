// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title TaxLedger
 * @author ProbeBuilders
 * @notice DeFi tax tracking ledger for ProbeChain Rydberg Testnet.
 *         Records trades and income on-chain for immutable audit trails.
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

contract TaxLedger is Ownable, ReentrancyGuard, Pausable {

    /* ── Enums ── */

    /// @notice Type of taxable event
    enum EventType { Trade, Income }

    /* ── Structs ── */

    /// @notice A recorded trade event
    struct TradeRecord {
        bytes32 txHash;
        address assetIn;
        address assetOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 timestamp;
        uint256 recordedAt;
    }

    /// @notice A recorded income event
    struct IncomeRecord {
        string  source;      // e.g. "staking", "farming", "airdrop"
        address asset;
        uint256 amount;
        uint256 timestamp;
        uint256 recordedAt;
    }

    /// @notice Annual report summary
    struct AnnualSummary {
        uint256 year;
        uint256 totalTrades;
        uint256 totalIncomeRecords;
        bytes32 summaryHash;
        uint256 generatedAt;
    }

    /* ── State ── */

    mapping(address => TradeRecord[]) private _trades;
    mapping(address => IncomeRecord[]) private _incomes;
    mapping(address => mapping(uint256 => AnnualSummary)) private _reports;
    mapping(address => bool) public authorizedRecorders;

    uint256 public totalTradeRecords;
    uint256 public totalIncomeRecords;

    /* ── Events ── */

    /// @notice Emitted when a trade is recorded
    event TradeRecorded(address indexed user, bytes32 txHash, address assetIn, address assetOut, uint256 amountIn, uint256 amountOut, uint256 timestamp);
    /// @notice Emitted when income is recorded
    event IncomeRecorded(address indexed user, string source, address asset, uint256 amount, uint256 timestamp);
    /// @notice Emitted when an annual report is generated
    event ReportGenerated(address indexed user, uint256 year, bytes32 summaryHash);
    /// @notice Emitted when a recorder is authorized or revoked
    event RecorderUpdated(address indexed recorder, bool status);

    /* ── Errors ── */

    error NotAuthorized();
    error InvalidTimestamp();
    error ReportAlreadyExists();

    /* ── Modifiers ── */

    modifier onlyAuthorized() {
        if (msg.sender != tx.origin && !authorizedRecorders[msg.sender] && msg.sender != owner()) revert NotAuthorized();
        _;
    }

    /* ── Constructor ── */

    constructor() Ownable() {}

    /* ── Admin ── */

    /// @notice Authorize or revoke a recorder address (e.g. a relayer bot)
    function setRecorder(address recorder, bool status) external onlyOwner {
        authorizedRecorders[recorder] = status;
        emit RecorderUpdated(recorder, status);
    }

    /* ── Core functions ── */

    /**
     * @notice Record a trade for tax tracking
     * @param txHash Transaction hash of the trade
     * @param assetIn Token sold
     * @param assetOut Token bought
     * @param amountIn Amount sold
     * @param amountOut Amount bought
     * @param timestamp Time of the trade (must be <= now)
     */
    function recordTrade(
        bytes32 txHash,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    ) external whenNotPaused {
        if (timestamp > block.timestamp) revert InvalidTimestamp();
        require(amountIn > 0 && amountOut > 0, "zero amount");

        _trades[msg.sender].push(TradeRecord({
            txHash: txHash,
            assetIn: assetIn,
            assetOut: assetOut,
            amountIn: amountIn,
            amountOut: amountOut,
            timestamp: timestamp,
            recordedAt: block.timestamp
        }));

        totalTradeRecords++;

        emit TradeRecorded(msg.sender, txHash, assetIn, assetOut, amountIn, amountOut, timestamp);
    }

    /**
     * @notice Record income for tax tracking
     * @param source Description of the income source
     * @param asset Token address (address(0) for native)
     * @param amount Income amount
     */
    function recordIncome(
        string calldata source,
        address asset,
        uint256 amount
    ) external whenNotPaused {
        require(amount > 0, "zero amount");
        require(bytes(source).length > 0, "empty source");

        _incomes[msg.sender].push(IncomeRecord({
            source: source,
            asset: asset,
            amount: amount,
            timestamp: block.timestamp,
            recordedAt: block.timestamp
        }));

        totalIncomeRecords++;

        emit IncomeRecorded(msg.sender, source, asset, amount, block.timestamp);
    }

    /**
     * @notice Generate an annual tax report summary hash.
     *         The hash covers all trades and income for the given year.
     * @param year The tax year (e.g. 2026)
     * @return summaryHash A keccak256 hash summarizing the year's records
     */
    function generateReport(uint256 year) external whenNotPaused returns (bytes32 summaryHash) {
        require(year > 2020 && year <= 2100, "invalid year");
        if (_reports[msg.sender][year].generatedAt != 0) revert ReportAlreadyExists();

        uint256 yearStart = _yearToTimestamp(year);
        uint256 yearEnd = _yearToTimestamp(year + 1);

        // Count trades and income in the year
        uint256 tradeCount;
        uint256 incomeCount;
        uint256 totalTradeVolume;
        uint256 totalIncomeAmount;

        TradeRecord[] storage trades = _trades[msg.sender];
        for (uint256 i = 0; i < trades.length; i++) {
            if (trades[i].timestamp >= yearStart && trades[i].timestamp < yearEnd) {
                tradeCount++;
                totalTradeVolume += trades[i].amountIn;
            }
        }

        IncomeRecord[] storage incomes = _incomes[msg.sender];
        for (uint256 i = 0; i < incomes.length; i++) {
            if (incomes[i].timestamp >= yearStart && incomes[i].timestamp < yearEnd) {
                incomeCount++;
                totalIncomeAmount += incomes[i].amount;
            }
        }

        summaryHash = keccak256(abi.encodePacked(
            msg.sender,
            year,
            tradeCount,
            totalTradeVolume,
            incomeCount,
            totalIncomeAmount,
            block.timestamp
        ));

        _reports[msg.sender][year] = AnnualSummary({
            year: year,
            totalTrades: tradeCount,
            totalIncomeRecords: incomeCount,
            summaryHash: summaryHash,
            generatedAt: block.timestamp
        });

        emit ReportGenerated(msg.sender, year, summaryHash);
    }

    /* ── View helpers ── */

    /// @notice Get all trade records for the caller
    function getMyTrades() external view returns (TradeRecord[] memory) {
        return _trades[msg.sender];
    }

    /// @notice Get all income records for the caller
    function getMyIncomes() external view returns (IncomeRecord[] memory) {
        return _incomes[msg.sender];
    }

    /// @notice Get annual report for the caller
    function getReport(uint256 year) external view returns (AnnualSummary memory) {
        return _reports[msg.sender][year];
    }

    /// @notice Get trade count for the caller
    function getTradeCount(address user) external view returns (uint256) {
        return _trades[user].length;
    }

    /// @notice Get income count for the caller
    function getIncomeCount(address user) external view returns (uint256) {
        return _incomes[user].length;
    }

    /* ── Internal ── */

    /// @dev Rough year-to-timestamp. Approximate; sufficient for bucketing.
    function _yearToTimestamp(uint256 year) private pure returns (uint256) {
        // Unix epoch starts 1970. Each year ~ 365.25 days.
        return (year - 1970) * 365 days + ((year - 1970) / 4) * 1 days;
    }
}
