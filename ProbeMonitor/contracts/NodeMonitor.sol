// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title NodeMonitor
 * @author ProbeBuilders
 * @notice Node performance registry and monitoring with on-chain scoring
 * @dev Tracks uptime, latency, and computes performance scores for leaderboard
 */

abstract contract Ownable {
    address private _owner;
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert OwnableInvalidOwner(address(0));
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender);
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
}

/// @title NodeMonitor — Node performance registry and leaderboard
contract NodeMonitor is Ownable, Pausable {

    enum NodeType { Validator, FullNode, LightNode, ArchiveNode, RPC }

    /// @notice Node information
    struct Node {
        bytes32 nodeId;
        address operator;
        string endpoint;
        NodeType nodeType;
        uint64 registeredAt;
        bool active;
    }

    /// @notice Performance metrics snapshot
    struct PerformanceReport {
        uint16 uptimePercent;       // 0-10000 (basis points, 10000 = 100%)
        uint256 blockHeight;
        uint32 avgLatencyMs;
        uint64 reportedAt;
        address reporter;
    }

    /// @notice Aggregated node performance score
    struct NodeScore {
        uint256 totalReports;
        uint256 avgUptimeBPS;       // Weighted average uptime in basis points
        uint256 avgLatencyMs;       // Weighted average latency
        uint256 highestBlock;
        uint256 score;              // Composite score (higher is better)
    }

    uint256 public nodeCount;
    uint256 public reportCount;

    /// @notice nodeId => Node
    mapping(bytes32 => Node) public nodes;
    /// @notice nodeId => performance reports
    mapping(bytes32 => PerformanceReport[]) private _reports;
    /// @notice nodeId => aggregated score
    mapping(bytes32 => NodeScore) public nodeScores;
    /// @notice Authorized reporters
    mapping(address => bool) public authorizedReporters;
    /// @notice operator => nodeIds
    mapping(address => bytes32[]) public operatorNodes;
    /// @notice All node IDs for iteration
    bytes32[] public allNodeIds;

    event NodeRegistered(bytes32 indexed nodeId, address indexed operator, string endpoint, NodeType nodeType);
    event NodeDeactivated(bytes32 indexed nodeId);
    event NodeReactivated(bytes32 indexed nodeId);
    event UptimeReported(bytes32 indexed nodeId, uint16 uptimePercent, uint256 blockHeight, address indexed reporter);
    event LatencyReported(bytes32 indexed nodeId, uint32 avgMs, address indexed reporter);
    event ScoreUpdated(bytes32 indexed nodeId, uint256 newScore);
    event ReporterAuthorized(address indexed reporter, bool authorized);
    event EndpointUpdated(bytes32 indexed nodeId, string newEndpoint);

    error NodeAlreadyRegistered();
    error NodeNotFound();
    error NodeNotActive();
    error NotOperator();
    error NotAuthorizedReporter();
    error InvalidUptime();
    error InvalidLatency();

    constructor() Ownable(msg.sender) {
        authorizedReporters[msg.sender] = true;
    }

    /// @notice Register a new node
    /// @param nodeId Unique node identifier
    /// @param endpoint Node endpoint URL
    /// @param nodeType Type of node
    function registerNode(
        bytes32 nodeId,
        string calldata endpoint,
        NodeType nodeType
    ) external whenNotPaused {
        if (nodes[nodeId].registeredAt != 0) revert NodeAlreadyRegistered();
        require(bytes(endpoint).length > 0, "Empty endpoint");

        nodes[nodeId] = Node({
            nodeId: nodeId,
            operator: msg.sender,
            endpoint: endpoint,
            nodeType: nodeType,
            registeredAt: uint64(block.timestamp),
            active: true
        });

        nodeScores[nodeId] = NodeScore({
            totalReports: 0,
            avgUptimeBPS: 0,
            avgLatencyMs: 0,
            highestBlock: 0,
            score: 0
        });

        operatorNodes[msg.sender].push(nodeId);
        allNodeIds.push(nodeId);
        nodeCount++;

        emit NodeRegistered(nodeId, msg.sender, endpoint, nodeType);
    }

    /// @notice Report uptime for a node
    /// @param nodeId Node to report for
    /// @param uptimePercent Uptime in basis points (0-10000)
    /// @param blockHeight Current block height of node
    function reportUptime(
        bytes32 nodeId,
        uint16 uptimePercent,
        uint256 blockHeight
    ) external whenNotPaused {
        if (!authorizedReporters[msg.sender]) revert NotAuthorizedReporter();
        if (nodes[nodeId].registeredAt == 0) revert NodeNotFound();
        if (uptimePercent > 10000) revert InvalidUptime();

        _reports[nodeId].push(PerformanceReport({
            uptimePercent: uptimePercent,
            blockHeight: blockHeight,
            avgLatencyMs: 0,
            reportedAt: uint64(block.timestamp),
            reporter: msg.sender
        }));

        reportCount++;
        _updateScore(nodeId, uptimePercent, 0, blockHeight);

        emit UptimeReported(nodeId, uptimePercent, blockHeight, msg.sender);
    }

    /// @notice Report latency for a node
    /// @param nodeId Node to report for
    /// @param avgMs Average latency in milliseconds
    function reportLatency(bytes32 nodeId, uint32 avgMs) external whenNotPaused {
        if (!authorizedReporters[msg.sender]) revert NotAuthorizedReporter();
        if (nodes[nodeId].registeredAt == 0) revert NodeNotFound();
        if (avgMs == 0) revert InvalidLatency();

        _reports[nodeId].push(PerformanceReport({
            uptimePercent: 0,
            blockHeight: 0,
            avgLatencyMs: avgMs,
            reportedAt: uint64(block.timestamp),
            reporter: msg.sender
        }));

        reportCount++;
        _updateScore(nodeId, 0, avgMs, 0);

        emit LatencyReported(nodeId, avgMs, msg.sender);
    }

    /// @notice Update composite score based on new report
    function _updateScore(
        bytes32 nodeId,
        uint16 uptimePercent,
        uint32 latencyMs,
        uint256 blockHeight
    ) internal {
        NodeScore storage s = nodeScores[nodeId];
        s.totalReports++;

        // Update rolling averages
        if (uptimePercent > 0) {
            s.avgUptimeBPS = ((s.avgUptimeBPS * (s.totalReports - 1)) + uptimePercent) / s.totalReports;
        }
        if (latencyMs > 0) {
            if (s.avgLatencyMs == 0) {
                s.avgLatencyMs = latencyMs;
            } else {
                s.avgLatencyMs = ((s.avgLatencyMs * (s.totalReports - 1)) + latencyMs) / s.totalReports;
            }
        }
        if (blockHeight > s.highestBlock) {
            s.highestBlock = blockHeight;
        }

        // Composite score: uptime weight 70%, latency weight 30%
        // Higher uptime = higher score, lower latency = higher score
        uint256 uptimeScore = s.avgUptimeBPS * 70; // max 700000
        uint256 latencyScore = 0;
        if (s.avgLatencyMs > 0 && s.avgLatencyMs < 10000) {
            latencyScore = ((10000 - s.avgLatencyMs) * 30); // max 300000
        }
        s.score = (uptimeScore + latencyScore) / 100; // Normalize to 0-10000

        emit ScoreUpdated(nodeId, s.score);
    }

    /// @notice Get node performance score
    /// @param nodeId Node to query
    /// @return score Composite performance score
    /// @return uptime Average uptime in basis points
    /// @return latency Average latency in ms
    /// @return reports Total number of reports
    function getNodeScore(bytes32 nodeId)
        external
        view
        returns (uint256 score, uint256 uptime, uint256 latency, uint256 reports)
    {
        NodeScore storage s = nodeScores[nodeId];
        return (s.score, s.avgUptimeBPS, s.avgLatencyMs, s.totalReports);
    }

    /// @notice Get report count for a node
    function getReportCount(bytes32 nodeId) external view returns (uint256) {
        return _reports[nodeId].length;
    }

    /// @notice Get a specific report
    function getReport(bytes32 nodeId, uint256 index) external view returns (PerformanceReport memory) {
        return _reports[nodeId][index];
    }

    /// @notice Update node endpoint
    function updateEndpoint(bytes32 nodeId, string calldata newEndpoint) external {
        if (nodes[nodeId].operator != msg.sender) revert NotOperator();
        nodes[nodeId].endpoint = newEndpoint;
        emit EndpointUpdated(nodeId, newEndpoint);
    }

    /// @notice Deactivate a node
    function deactivateNode(bytes32 nodeId) external {
        if (nodes[nodeId].operator != msg.sender && msg.sender != owner()) revert NotOperator();
        nodes[nodeId].active = false;
        emit NodeDeactivated(nodeId);
    }

    /// @notice Reactivate a node
    function reactivateNode(bytes32 nodeId) external {
        if (nodes[nodeId].operator != msg.sender) revert NotOperator();
        nodes[nodeId].active = true;
        emit NodeReactivated(nodeId);
    }

    /// @notice Authorize or revoke a reporter
    function setAuthorizedReporter(address reporter, bool authorized) external onlyOwner {
        authorizedReporters[reporter] = authorized;
        emit ReporterAuthorized(reporter, authorized);
    }

    /// @notice Get all node IDs for an operator
    function getOperatorNodes(address operator) external view returns (bytes32[] memory) {
        return operatorNodes[operator];
    }

    /// @notice Get total registered node count
    function getTotalNodes() external view returns (uint256) {
        return allNodeIds.length;
    }
}
