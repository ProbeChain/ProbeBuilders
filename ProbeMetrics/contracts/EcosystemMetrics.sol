// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title EcosystemMetrics
 * @author ProbeChain Rydberg Testnet
 * @notice Ecosystem health dashboard aggregating TVL, active users, TPS, and health scores
 * @dev Authorized reporters submit protocol metrics, contract computes aggregate ecosystem health
 */

// ---------- Inlined Ownable ----------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: caller is not the owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner); _owner = newOwner;
    }
}

// ---------- Inlined ReentrancyGuard ----------
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

// ---------- Inlined Pausable ----------
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

contract EcosystemMetrics is Ownable, ReentrancyGuard, Pausable {
    // ---------- Structs ----------
    struct ProtocolMetrics {
        address protocol;
        string name;
        uint256 tvl;
        uint256 activeUsers;
        uint256 lastTVLUpdate;
        uint256 lastUserUpdate;
        bool active;
    }

    struct TPSRecord {
        uint256 blockRangeStart;
        uint256 blockRangeEnd;
        uint256 avgTps;
        uint256 peakTps;
        uint256 recordedAt;
    }

    struct HealthScore {
        uint256 totalTVL;
        uint256 totalActiveUsers;
        uint256 avgTPS;
        uint256 protocolCount;
        uint256 overallScore;
        uint256 calculatedAt;
    }

    // ---------- State ----------
    uint256 public nextProtocolId;
    uint256 public nextTPSRecordId;

    mapping(uint256 => ProtocolMetrics) public protocols;
    mapping(address => uint256) public protocolIdByAddress;
    mapping(uint256 => TPSRecord) public tpsRecords;
    mapping(address => bool) public authorizedReporters;

    uint256 public latestTVL;
    uint256 public latestActiveUsers;
    uint256 public latestAvgTPS;
    uint256 public activeProtocolCount;

    // Scoring weights (BPS, must sum to 10000)
    uint256 public tvlWeight;
    uint256 public userWeight;
    uint256 public tpsWeight;
    uint256 public diversityWeight;

    // ---------- Events ----------
    /// @notice Emitted when TVL is reported for a protocol
    event TVLReported(uint256 indexed protocolId, address indexed protocol, uint256 tvl);
    /// @notice Emitted when active users count is reported
    event ActiveUsersReported(uint256 indexed protocolId, address indexed protocol, uint256 count);
    /// @notice Emitted when TPS data is reported
    event TPSReported(uint256 indexed recordId, uint256 blockRangeStart, uint256 blockRangeEnd, uint256 avgTps);
    /// @notice Emitted when ecosystem health is calculated
    event HealthCalculated(uint256 totalTVL, uint256 totalUsers, uint256 avgTPS, uint256 score);
    /// @notice Emitted when a protocol is registered
    event ProtocolRegistered(uint256 indexed protocolId, address indexed protocol, string name);

    // ---------- Constructor ----------
    constructor() Ownable() ReentrancyGuard() Pausable() {
        nextProtocolId = 1;
        nextTPSRecordId = 1;
        tvlWeight = 3000;
        userWeight = 3000;
        tpsWeight = 2000;
        diversityWeight = 2000;
    }

    /**
     * @notice Authorize a metrics reporter
     * @param reporter Address to authorize
     */
    function authorizeReporter(address reporter) external onlyOwner {
        require(reporter != address(0), "Zero address");
        authorizedReporters[reporter] = true;
    }

    /**
     * @notice Register a protocol for tracking
     * @param protocol Protocol contract address
     * @param name_ Protocol name
     * @return protocolId The registered protocol ID
     */
    function registerProtocol(address protocol, string calldata name_)
        external
        onlyOwner
        returns (uint256 protocolId)
    {
        require(protocol != address(0), "Zero address");
        require(protocolIdByAddress[protocol] == 0, "Already registered");
        require(bytes(name_).length > 0 && bytes(name_).length <= 64, "Invalid name");

        protocolId = nextProtocolId++;
        ProtocolMetrics storage pm = protocols[protocolId];
        pm.protocol = protocol;
        pm.name = name_;
        pm.active = true;

        protocolIdByAddress[protocol] = protocolId;
        activeProtocolCount++;
        emit ProtocolRegistered(protocolId, protocol, name_);
    }

    /**
     * @notice Report TVL for a protocol
     * @param protocol Protocol address
     * @param tvl Total value locked in wei
     */
    function reportTVL(address protocol, uint256 tvl) external whenNotPaused {
        require(authorizedReporters[msg.sender] || msg.sender == owner(), "Not authorized");
        uint256 pid = protocolIdByAddress[protocol];
        require(pid != 0, "Protocol not registered");
        ProtocolMetrics storage pm = protocols[pid];
        require(pm.active, "Protocol not active");

        pm.tvl = tvl;
        pm.lastTVLUpdate = block.timestamp;

        _recalculateAggregateTVL();
        emit TVLReported(pid, protocol, tvl);
    }

    /**
     * @notice Report active users for a protocol
     * @param protocol Protocol address
     * @param count Active user count
     */
    function reportActiveUsers(address protocol, uint256 count) external whenNotPaused {
        require(authorizedReporters[msg.sender] || msg.sender == owner(), "Not authorized");
        uint256 pid = protocolIdByAddress[protocol];
        require(pid != 0, "Protocol not registered");
        ProtocolMetrics storage pm = protocols[pid];
        require(pm.active, "Protocol not active");

        pm.activeUsers = count;
        pm.lastUserUpdate = block.timestamp;

        _recalculateAggregateUsers();
        emit ActiveUsersReported(pid, protocol, count);
    }

    /**
     * @notice Report TPS for a block range
     * @param blockRangeStart Start block
     * @param blockRangeEnd End block
     * @param avgTps Average TPS
     */
    function reportTPS(uint256 blockRangeStart, uint256 blockRangeEnd, uint256 avgTps)
        external
        whenNotPaused
    {
        require(authorizedReporters[msg.sender] || msg.sender == owner(), "Not authorized");
        require(blockRangeEnd > blockRangeStart, "Invalid range");

        uint256 recordId = nextTPSRecordId++;
        TPSRecord storage rec = tpsRecords[recordId];
        rec.blockRangeStart = blockRangeStart;
        rec.blockRangeEnd = blockRangeEnd;
        rec.avgTps = avgTps;
        rec.recordedAt = block.timestamp;

        latestAvgTPS = avgTps;
        emit TPSReported(recordId, blockRangeStart, blockRangeEnd, avgTps);
    }

    /**
     * @notice Get aggregate ecosystem health score
     * @return health Comprehensive health score struct
     */
    function getEcosystemHealth() external view returns (HealthScore memory health) {
        health.totalTVL = latestTVL;
        health.totalActiveUsers = latestActiveUsers;
        health.avgTPS = latestAvgTPS;
        health.protocolCount = activeProtocolCount;
        health.calculatedAt = block.timestamp;

        // Calculate overall score (0-100)
        uint256 tvlScore;
        if (latestTVL >= 1000000 ether) tvlScore = 100;
        else if (latestTVL >= 100000 ether) tvlScore = 80;
        else if (latestTVL >= 10000 ether) tvlScore = 60;
        else if (latestTVL >= 1000 ether) tvlScore = 40;
        else if (latestTVL > 0) tvlScore = 20;

        uint256 userScore;
        if (latestActiveUsers >= 100000) userScore = 100;
        else if (latestActiveUsers >= 10000) userScore = 80;
        else if (latestActiveUsers >= 1000) userScore = 60;
        else if (latestActiveUsers >= 100) userScore = 40;
        else if (latestActiveUsers > 0) userScore = 20;

        uint256 tpsScore;
        if (latestAvgTPS >= 10000) tpsScore = 100;
        else if (latestAvgTPS >= 1000) tpsScore = 80;
        else if (latestAvgTPS >= 100) tpsScore = 60;
        else if (latestAvgTPS >= 10) tpsScore = 40;
        else if (latestAvgTPS > 0) tpsScore = 20;

        uint256 divScore;
        if (activeProtocolCount >= 50) divScore = 100;
        else if (activeProtocolCount >= 20) divScore = 80;
        else if (activeProtocolCount >= 10) divScore = 60;
        else if (activeProtocolCount >= 5) divScore = 40;
        else if (activeProtocolCount > 0) divScore = 20;

        health.overallScore = (
            tvlScore * tvlWeight +
            userScore * userWeight +
            tpsScore * tpsWeight +
            divScore * diversityWeight
        ) / 10000;
    }

    // ---------- Internal ----------
    function _recalculateAggregateTVL() internal {
        uint256 total;
        for (uint256 i = 1; i < nextProtocolId; i++) {
            if (protocols[i].active) total += protocols[i].tvl;
        }
        latestTVL = total;
    }

    function _recalculateAggregateUsers() internal {
        uint256 total;
        for (uint256 i = 1; i < nextProtocolId; i++) {
            if (protocols[i].active) total += protocols[i].activeUsers;
        }
        latestActiveUsers = total;
    }

    // ---------- Admin ----------
    function deactivateProtocol(uint256 protocolId) external onlyOwner {
        protocols[protocolId].active = false;
        activeProtocolCount--;
    }

    function setWeights(uint256 _tvl, uint256 _user, uint256 _tps, uint256 _div) external onlyOwner {
        require(_tvl + _user + _tps + _div == 10000, "Must sum to 10000");
        tvlWeight = _tvl;
        userWeight = _user;
        tpsWeight = _tps;
        diversityWeight = _div;
    }
}
