// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GrowthTracker
 * @author ProbeChain Team
 * @notice On-chain growth metrics tracking and project comparison platform
 * @dev Records time-series metrics for projects with growth rate calculation
 */
contract GrowthTracker {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "GrowthTracker: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "GrowthTracker: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "GrowthTracker: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums ──────────────────────────────────────────────────────────
    enum MetricType { Users, Transactions, Volume, Revenue, TVL }

    // ─── Structs ────────────────────────────────────────────────────────
    struct Project {
        uint256 id;
        string name;
        string category;
        address maintainer;
        uint256 metricCount;
        uint256 createdAt;
        bool active;
    }

    struct Metric {
        uint256 id;
        uint256 projectId;
        MetricType metricType;
        uint256 value;
        uint256 timestamp;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public projectCount;
    uint256 public metricCount;

    mapping(uint256 => Project) public projects;
    mapping(uint256 => Metric) public metrics;
    mapping(uint256 => mapping(uint8 => uint256[])) public projectMetrics;
    mapping(address => uint256[]) public maintainerProjects;
    mapping(string => uint256[]) public categoryProjects;
    mapping(address => bool) public authorizedReporters;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a project is registered
    event ProjectRegistered(uint256 indexed projectId, string name, string category, address indexed maintainer);
    /// @notice Emitted when a metric is recorded
    event MetricRecorded(uint256 indexed metricId, uint256 indexed projectId, MetricType metricType, uint256 value);
    /// @notice Emitted when reporter authorization changes
    event ReporterAuthorized(address indexed reporter, bool status);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Reporter Management ────────────────────────────────────────────
    /**
     * @notice Authorize or revoke a metric reporter
     * @param reporter Reporter address
     * @param status Authorization status
     */
    function setAuthorizedReporter(address reporter, bool status) external onlyOwner {
        authorizedReporters[reporter] = status;
        emit ReporterAuthorized(reporter, status);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register a new project for tracking
     * @param name Project name
     * @param category Project category
     * @return projectId The new project ID
     */
    function registerProject(
        string calldata name,
        string calldata category
    ) external whenNotPaused returns (uint256 projectId) {
        require(bytes(name).length > 0 && bytes(name).length <= 64, "GrowthTracker: invalid name");
        require(bytes(category).length > 0, "GrowthTracker: empty category");

        projectCount++;
        projectId = projectCount;

        projects[projectId] = Project({
            id: projectId,
            name: name,
            category: category,
            maintainer: msg.sender,
            metricCount: 0,
            createdAt: block.timestamp,
            active: true
        });

        maintainerProjects[msg.sender].push(projectId);
        categoryProjects[category].push(projectId);

        emit ProjectRegistered(projectId, name, category, msg.sender);
    }

    /**
     * @notice Record a metric data point for a project
     * @param projectId Project to record for
     * @param metricType Type of metric (0=Users, 1=Tx, 2=Volume, 3=Revenue, 4=TVL)
     * @param value Metric value
     * @param timestamp When the metric was measured
     */
    function recordMetric(
        uint256 projectId,
        MetricType metricType,
        uint256 value,
        uint256 timestamp
    ) external whenNotPaused {
        Project storage p = projects[projectId];
        require(p.active, "GrowthTracker: project not active");
        require(
            msg.sender == p.maintainer || authorizedReporters[msg.sender],
            "GrowthTracker: unauthorized"
        );
        require(timestamp <= block.timestamp, "GrowthTracker: future timestamp");

        metricCount++;
        metrics[metricCount] = Metric({
            id: metricCount,
            projectId: projectId,
            metricType: metricType,
            value: value,
            timestamp: timestamp
        });

        projectMetrics[projectId][uint8(metricType)].push(metricCount);
        p.metricCount++;

        emit MetricRecorded(metricCount, projectId, metricType, value);
    }

    /**
     * @notice Calculate growth rate for a project over a period
     * @param projectId Project ID
     * @param metricType Metric type to analyze
     * @return growthBps Growth rate in basis points (100 = 1%)
     * @return startValue First metric value in period
     * @return endValue Last metric value in period
     */
    function getGrowthRate(
        uint256 projectId,
        MetricType metricType
    ) external view returns (int256 growthBps, uint256 startValue, uint256 endValue) {
        uint256[] storage metricIds = projectMetrics[projectId][uint8(metricType)];
        require(metricIds.length >= 2, "GrowthTracker: insufficient data");

        startValue = metrics[metricIds[0]].value;
        endValue = metrics[metricIds[metricIds.length - 1]].value;

        if (startValue == 0) {
            return (int256(endValue > 0 ? int256(10000) : int256(0)), startValue, endValue);
        }

        growthBps = (int256(endValue) - int256(startValue)) * 10000 / int256(startValue);
    }

    /**
     * @notice Compare latest metric values across multiple projects
     * @param ids Array of project IDs to compare
     * @param metricType Metric type to compare
     * @return values Array of latest values for each project
     */
    function compareProjects(
        uint256[] calldata ids,
        MetricType metricType
    ) external view returns (uint256[] memory values) {
        values = new uint256[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            uint256[] storage metricIds = projectMetrics[ids[i]][uint8(metricType)];
            if (metricIds.length > 0) {
                values[i] = metrics[metricIds[metricIds.length - 1]].value;
            }
        }
    }

    /**
     * @notice Get metric history for a project
     * @param projectId Project ID
     * @param metricType Metric type
     * @param limit Max entries to return
     * @return metricIds Array of metric IDs (most recent first)
     */
    function getMetricHistory(
        uint256 projectId,
        MetricType metricType,
        uint256 limit
    ) external view returns (uint256[] memory metricIds) {
        uint256[] storage allIds = projectMetrics[projectId][uint8(metricType)];
        uint256 len = allIds.length > limit ? limit : allIds.length;
        metricIds = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            metricIds[i] = allIds[allIds.length - 1 - i];
        }
    }

    /**
     * @notice Deactivate a project
     * @param projectId Project to deactivate
     */
    function deactivateProject(uint256 projectId) external {
        require(
            projects[projectId].maintainer == msg.sender || msg.sender == _owner,
            "GrowthTracker: unauthorized"
        );
        projects[projectId].active = false;
    }
}
