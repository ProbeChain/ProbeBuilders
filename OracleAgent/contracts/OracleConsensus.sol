// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title OracleConsensus — Decentralized oracle with multi-source consensus for ProbeChain
/// @author ProbeBuilders
/// @notice Submit data points, aggregate via median, detect outliers, track reporter reputation
/// @dev Rydberg Testnet (Chain ID 8004). Outlier rejection: >2 std devs from mean.
contract OracleConsensus {
    // ─── Enums & Structs ─────────────────────────────────────────────────
    enum FeedStatus { Active, Resolved, Expired }

    struct Feed {
        uint256 id;
        string name;
        address creator;
        uint256 minReporters;
        uint256 timeout;
        FeedStatus status;
        uint256 resolvedValue;
        uint256 reportCount;
        uint256 createdAt;
        uint256 resolvedAt;
    }

    struct DataPoint {
        address reporter;
        uint256 value;
        uint256 submittedAt;
        bool outlier;
    }

    struct Reporter {
        uint256 totalReports;
        uint256 acceptedReports;
        uint256 reputationScore; // 0-100
        bool registered;
    }

    // ─── State ───────────────────────────────────────────────────────────
    address public owner;
    bool public paused;

    uint256 private _nextFeedId = 1;

    mapping(uint256 => Feed) public feeds;
    mapping(uint256 => DataPoint[]) private _feedDataPoints;
    mapping(uint256 => mapping(address => bool)) private _hasReported;
    mapping(address => Reporter) public reporters;

    uint256 public registrationStake;
    uint256 public totalFeeds;

    uint256 public constant MAX_REPORTERS_PER_FEED = 50;
    uint256 public constant OUTLIER_THRESHOLD_BPS = 200; // 2x std dev in basis points (simplified)

    // ─── Events ──────────────────────────────────────────────────────────
    event FeedCreated(uint256 indexed feedId, string name, address indexed creator, uint256 minReporters, uint256 timeout);
    event DataPointSubmitted(uint256 indexed feedId, address indexed reporter, uint256 value);
    event FeedResolved(uint256 indexed feedId, uint256 resolvedValue, uint256 validReports, uint256 outliers);
    event FeedExpired(uint256 indexed feedId);
    event ReporterRegistered(address indexed reporter, uint256 stake);
    event ReputationUpdated(address indexed reporter, uint256 oldScore, uint256 newScore);
    event OutlierDetected(uint256 indexed feedId, address indexed reporter, uint256 value, uint256 median);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "OracleConsensus: not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "OracleConsensus: paused");
        _;
    }

    modifier onlyRegisteredReporter() {
        require(reporters[msg.sender].registered, "OracleConsensus: not registered");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    /// @param _registrationStake Stake required to become a reporter (in wei)
    constructor(uint256 _registrationStake) {
        owner = msg.sender;
        registrationStake = _registrationStake;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Reporter Management ─────────────────────────────────────────────

    /// @notice Register as a data reporter (requires stake)
    function registerReporter() external payable whenNotPaused {
        require(!reporters[msg.sender].registered, "OracleConsensus: already registered");
        require(msg.value >= registrationStake, "OracleConsensus: insufficient stake");

        reporters[msg.sender] = Reporter({
            totalReports: 0,
            acceptedReports: 0,
            reputationScore: 50,
            registered: true
        });

        emit ReporterRegistered(msg.sender, msg.value);
    }

    // ─── Feed Management ─────────────────────────────────────────────────

    /// @notice Create a new data feed
    /// @param name Feed name (e.g., "PRB/USD")
    /// @param minReporters Minimum reporters needed before resolution
    /// @param timeout Seconds before feed expires
    /// @return feedId The new feed ID
    function createFeed(
        string calldata name,
        uint256 minReporters,
        uint256 timeout
    ) external whenNotPaused returns (uint256 feedId) {
        require(bytes(name).length > 0 && bytes(name).length <= 128, "OracleConsensus: invalid name");
        require(minReporters >= 3, "OracleConsensus: need at least 3 reporters");
        require(timeout >= 60 && timeout <= 7 days, "OracleConsensus: invalid timeout");

        feedId = _nextFeedId++;

        feeds[feedId] = Feed({
            id: feedId,
            name: name,
            creator: msg.sender,
            minReporters: minReporters,
            timeout: timeout,
            status: FeedStatus.Active,
            resolvedValue: 0,
            reportCount: 0,
            createdAt: block.timestamp,
            resolvedAt: 0
        });

        totalFeeds++;

        emit FeedCreated(feedId, name, msg.sender, minReporters, timeout);
    }

    /// @notice Submit a data point to a feed
    /// @param feedId The feed
    /// @param value The reported value (scaled by 1e8 for precision)
    function submitDataPoint(uint256 feedId, uint256 value) external whenNotPaused onlyRegisteredReporter {
        Feed storage feed = feeds[feedId];
        require(feed.createdAt != 0, "OracleConsensus: feed not found");
        require(feed.status == FeedStatus.Active, "OracleConsensus: feed not active");
        require(block.timestamp <= feed.createdAt + feed.timeout, "OracleConsensus: feed expired");
        require(!_hasReported[feedId][msg.sender], "OracleConsensus: already reported");
        require(feed.reportCount < MAX_REPORTERS_PER_FEED, "OracleConsensus: max reporters reached");

        _feedDataPoints[feedId].push(DataPoint({
            reporter: msg.sender,
            value: value,
            submittedAt: block.timestamp,
            outlier: false
        }));

        _hasReported[feedId][msg.sender] = true;
        feed.reportCount++;
        reporters[msg.sender].totalReports++;

        emit DataPointSubmitted(feedId, msg.sender, value);
    }

    /// @notice Resolve a feed by computing median and detecting outliers
    /// @param feedId The feed to resolve
    function resolveFeed(uint256 feedId) external {
        Feed storage feed = feeds[feedId];
        require(feed.createdAt != 0, "OracleConsensus: feed not found");
        require(feed.status == FeedStatus.Active, "OracleConsensus: feed not active");
        require(feed.reportCount >= feed.minReporters, "OracleConsensus: not enough reporters");

        DataPoint[] storage dataPoints = _feedDataPoints[feedId];
        uint256 len = dataPoints.length;

        // Sort values for median (simple insertion sort, OK for small arrays)
        uint256[] memory values = new uint256[](len);
        for (uint256 i; i < len; ++i) {
            values[i] = dataPoints[i].value;
        }
        _sort(values);

        // Calculate median
        uint256 median;
        if (len % 2 == 0) {
            median = (values[len / 2 - 1] + values[len / 2]) / 2;
        } else {
            median = values[len / 2];
        }

        // Calculate mean and std dev for outlier detection
        uint256 mean = _calculateMean(values);
        uint256 stdDev = _calculateStdDev(values, mean);
        uint256 outlierBound = stdDev * 2; // 2 standard deviations

        // Mark outliers and update reputations
        uint256 outlierCount;
        for (uint256 i; i < len; ++i) {
            uint256 diff = dataPoints[i].value > mean
                ? dataPoints[i].value - mean
                : mean - dataPoints[i].value;

            if (outlierBound > 0 && diff > outlierBound) {
                dataPoints[i].outlier = true;
                outlierCount++;
                _adjustReputation(dataPoints[i].reporter, false);
                emit OutlierDetected(feedId, dataPoints[i].reporter, dataPoints[i].value, median);
            } else {
                reporters[dataPoints[i].reporter].acceptedReports++;
                _adjustReputation(dataPoints[i].reporter, true);
            }
        }

        feed.resolvedValue = median;
        feed.status = FeedStatus.Resolved;
        feed.resolvedAt = block.timestamp;

        emit FeedResolved(feedId, median, len - outlierCount, outlierCount);
    }

    /// @notice Mark an expired feed
    /// @param feedId The feed
    function expireFeed(uint256 feedId) external {
        Feed storage feed = feeds[feedId];
        require(feed.createdAt != 0 && feed.status == FeedStatus.Active, "OracleConsensus: invalid feed");
        require(block.timestamp > feed.createdAt + feed.timeout, "OracleConsensus: not expired yet");

        feed.status = FeedStatus.Expired;
        emit FeedExpired(feedId);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Get resolved value for a feed
    function getResolvedValue(uint256 feedId) external view returns (uint256) {
        require(feeds[feedId].status == FeedStatus.Resolved, "OracleConsensus: not resolved");
        return feeds[feedId].resolvedValue;
    }

    /// @notice Get data points for a feed
    function getDataPoints(uint256 feedId) external view returns (DataPoint[] memory) {
        return _feedDataPoints[feedId];
    }

    /// @notice Get reporter info
    function getReporter(address reporter) external view returns (Reporter memory) {
        return reporters[reporter];
    }

    // ─── Internal ────────────────────────────────────────────────────────

    /// @dev Insertion sort for small arrays
    function _sort(uint256[] memory arr) internal pure {
        uint256 len = arr.length;
        for (uint256 i = 1; i < len; ++i) {
            uint256 key = arr[i];
            uint256 j = i;
            while (j > 0 && arr[j - 1] > key) {
                arr[j] = arr[j - 1];
                j--;
            }
            arr[j] = key;
        }
    }

    /// @dev Calculate arithmetic mean
    function _calculateMean(uint256[] memory values) internal pure returns (uint256) {
        uint256 sum;
        for (uint256 i; i < values.length; ++i) {
            sum += values[i];
        }
        return sum / values.length;
    }

    /// @dev Calculate standard deviation (approximate integer math)
    function _calculateStdDev(uint256[] memory values, uint256 mean) internal pure returns (uint256) {
        uint256 sumSquaredDiffs;
        for (uint256 i; i < values.length; ++i) {
            uint256 diff = values[i] > mean ? values[i] - mean : mean - values[i];
            sumSquaredDiffs += diff * diff;
        }
        uint256 variance = sumSquaredDiffs / values.length;
        return _sqrt(variance);
    }

    /// @dev Integer square root (Babylonian method)
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    /// @dev Adjust reporter reputation
    function _adjustReputation(address reporter, bool positive) internal {
        uint256 old = reporters[reporter].reputationScore;
        uint256 newScore;
        if (positive) {
            newScore = old + 1;
            if (newScore > 100) newScore = 100;
        } else {
            newScore = old >= 5 ? old - 5 : 0;
        }
        reporters[reporter].reputationScore = newScore;
        emit ReputationUpdated(reporter, old, newScore);
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    function setRegistrationStake(uint256 newStake) external onlyOwner {
        registrationStake = newStake;
    }

    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    function withdrawFees() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "OracleConsensus: no balance");
        (bool ok, ) = payable(owner).call{value: bal}("");
        require(ok, "OracleConsensus: transfer failed");
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "OracleConsensus: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
