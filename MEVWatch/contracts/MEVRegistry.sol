// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title MEVRegistry
 * @author ProbeChain Labs
 * @notice MEV activity monitor — watchers report MEV events (sandwich,
 *         frontrun, backrun, arbitrage), track stats, and false reporters
 *         can be slashed.
 * @dev Designed for ProbeChain Rydberg Testnet (Chain ID 8004, EVM London).
 */

// ---------------------------------------------------------------------------
// Inline: Ownable
// ---------------------------------------------------------------------------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ---------------------------------------------------------------------------
// Inline: ReentrancyGuard
// ---------------------------------------------------------------------------
abstract contract ReentrancyGuard {
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    constructor() { _status = _NOT_ENTERED; }
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED; _; _status = _NOT_ENTERED;
    }
}

// ---------------------------------------------------------------------------
// Inline: Pausable
// ---------------------------------------------------------------------------
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

// ---------------------------------------------------------------------------
// Main Contract
// ---------------------------------------------------------------------------
contract MEVRegistry is Ownable, ReentrancyGuard, Pausable {

    enum MEVType { Sandwich, Frontrun, Backrun, Arbitrage }

    struct MEVReport {
        uint256 id;
        address reporter;
        bytes32 txHash;
        MEVType mevType;
        uint256 extractedValue;    // value in wei
        bytes32 victimTx;
        uint256 blockNumber;
        uint256 reportedAt;
        bool slashed;              // flagged as false report
    }

    struct WatcherProfile {
        address watcher;
        uint256 stake;
        uint256 reportCount;
        uint256 slashCount;
        uint256 rewardBalance;
        bool active;
        uint256 registeredAt;
    }

    /// @notice Minimum stake required to register as a watcher.
    uint256 public minStake;

    /// @notice Reward per valid report.
    uint256 public reportReward;

    /// @notice Slash penalty (deducted from stake).
    uint256 public slashPenalty;

    uint256 private _nextReportId;
    mapping(uint256 => MEVReport) public reports;
    mapping(address => WatcherProfile) public watchers;
    mapping(bytes32 => bool) public reportedTxHashes;

    // Aggregate stats
    uint256 public totalReports;
    uint256 public totalExtractedValue;
    mapping(uint256 => uint256) public mevTypeCount; // MEVType => count

    // Block-range stats: blockNumber => total extracted value
    mapping(uint256 => uint256) public blockMEVValue;

    // ---- Events ----------------------------------------------------------
    event WatcherRegistered(address indexed watcher, uint256 stake);
    event WatcherDeregistered(address indexed watcher, uint256 stakeReturned);
    event MEVReported(uint256 indexed reportId, address indexed reporter, bytes32 txHash, MEVType mevType, uint256 extractedValue, bytes32 victimTx);
    event FalseReportSlashed(uint256 indexed reportId, address indexed reporter, uint256 penalty);
    event RewardClaimed(address indexed watcher, uint256 amount);
    event MinStakeUpdated(uint256 newMinStake);
    event ReportRewardUpdated(uint256 newReward);
    event SlashPenaltyUpdated(uint256 newPenalty);

    constructor(uint256 _minStake, uint256 _reportReward, uint256 _slashPenalty) {
        minStake = _minStake;
        reportReward = _reportReward;
        slashPenalty = _slashPenalty;
        _nextReportId = 1;
    }

    // ---- Watcher Management ----------------------------------------------

    /**
     * @notice Register as a MEV watcher by staking.
     */
    function registerWatcher() external payable whenNotPaused {
        require(msg.value >= minStake, "Insufficient stake");
        require(!watchers[msg.sender].active, "Already registered");

        watchers[msg.sender] = WatcherProfile({
            watcher: msg.sender,
            stake: msg.value,
            reportCount: 0,
            slashCount: 0,
            rewardBalance: 0,
            active: true,
            registeredAt: block.timestamp
        });

        emit WatcherRegistered(msg.sender, msg.value);
    }

    /**
     * @notice Deregister as a watcher and withdraw remaining stake.
     */
    function deregisterWatcher() external nonReentrant whenNotPaused {
        WatcherProfile storage w = watchers[msg.sender];
        require(w.active, "Not registered");

        w.active = false;
        uint256 stakeReturn = w.stake;
        uint256 rewards = w.rewardBalance;
        w.stake = 0;
        w.rewardBalance = 0;

        uint256 total = stakeReturn + rewards;
        if (total > 0) {
            (bool success, ) = payable(msg.sender).call{value: total}("");
            require(success, "Transfer failed");
        }

        emit WatcherDeregistered(msg.sender, total);
    }

    // ---- Core Functions --------------------------------------------------

    /**
     * @notice Report an observed MEV event.
     * @param txHash         The transaction hash exhibiting MEV.
     * @param mevType        Type of MEV (Sandwich, Frontrun, Backrun, Arbitrage).
     * @param extractedValue Estimated value extracted in wei.
     * @param victimTx       The victim transaction hash.
     */
    function reportMEV(
        bytes32 txHash,
        MEVType mevType,
        uint256 extractedValue,
        bytes32 victimTx
    ) external whenNotPaused {
        WatcherProfile storage w = watchers[msg.sender];
        require(w.active, "Not a registered watcher");
        require(txHash != bytes32(0), "Empty tx hash");
        require(!reportedTxHashes[txHash], "Already reported");
        require(extractedValue > 0, "Zero extracted value");

        reportedTxHashes[txHash] = true;

        uint256 reportId = _nextReportId++;
        reports[reportId] = MEVReport({
            id: reportId,
            reporter: msg.sender,
            txHash: txHash,
            mevType: mevType,
            extractedValue: extractedValue,
            victimTx: victimTx,
            blockNumber: block.number,
            reportedAt: block.timestamp,
            slashed: false
        });

        w.reportCount++;
        w.rewardBalance += reportReward;

        // Update aggregate stats
        totalReports++;
        totalExtractedValue += extractedValue;
        mevTypeCount[uint256(mevType)]++;
        blockMEVValue[block.number] += extractedValue;

        emit MEVReported(reportId, msg.sender, txHash, mevType, extractedValue, victimTx);
    }

    /**
     * @notice Slash a watcher for a false report (owner only).
     * @param reportId The report deemed false.
     */
    function slashFalseReport(uint256 reportId) external onlyOwner {
        MEVReport storage r = reports[reportId];
        require(r.id != 0, "Report not found");
        require(!r.slashed, "Already slashed");

        r.slashed = true;

        WatcherProfile storage w = watchers[r.reporter];
        w.slashCount++;

        uint256 penalty = slashPenalty;
        if (penalty > w.stake) {
            penalty = w.stake;
        }
        w.stake -= penalty;

        // Reverse stats
        if (totalExtractedValue >= r.extractedValue) {
            totalExtractedValue -= r.extractedValue;
        }

        emit FalseReportSlashed(reportId, r.reporter, penalty);
    }

    /**
     * @notice Watcher claims accumulated rewards.
     */
    function claimRewards() external nonReentrant whenNotPaused {
        WatcherProfile storage w = watchers[msg.sender];
        require(w.rewardBalance > 0, "No rewards");

        uint256 amount = w.rewardBalance;
        w.rewardBalance = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Claim failed");

        emit RewardClaimed(msg.sender, amount);
    }

    // ---- Views -----------------------------------------------------------

    function getReport(uint256 reportId) external view returns (MEVReport memory) {
        require(reports[reportId].id != 0, "Not found");
        return reports[reportId];
    }

    function getWatcher(address watcher) external view returns (WatcherProfile memory) {
        return watchers[watcher];
    }

    /**
     * @notice Get aggregated MEV stats for a block range.
     * @param startBlock Start of range (inclusive).
     * @param endBlock   End of range (inclusive).
     * @return totalValue Total extracted MEV value in the range.
     */
    function getMEVStats(
        uint256 startBlock,
        uint256 endBlock
    ) external view returns (uint256 totalValue) {
        require(endBlock >= startBlock, "Invalid range");
        require(endBlock - startBlock <= 1000, "Range too large");
        for (uint256 b = startBlock; b <= endBlock; b++) {
            totalValue += blockMEVValue[b];
        }
    }

    function getMEVTypeCount(MEVType mevType) external view returns (uint256) {
        return mevTypeCount[uint256(mevType)];
    }

    // ---- Admin -----------------------------------------------------------

    function setMinStake(uint256 _minStake) external onlyOwner {
        minStake = _minStake;
        emit MinStakeUpdated(_minStake);
    }

    function setReportReward(uint256 _reward) external onlyOwner {
        reportReward = _reward;
        emit ReportRewardUpdated(_reward);
    }

    function setSlashPenalty(uint256 _penalty) external onlyOwner {
        slashPenalty = _penalty;
        emit SlashPenaltyUpdated(_penalty);
    }

    /// @notice Fund the contract for watcher rewards.
    receive() external payable {}

    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Withdraw failed");
    }
}
