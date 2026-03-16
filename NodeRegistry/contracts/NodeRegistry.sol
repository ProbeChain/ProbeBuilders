// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NodeRegistry
 * @author ProbeChain Team
 * @notice Validator and agent node registry for ProbeChain Rydberg Testnet
 * @dev Register nodes by type (Validator, Agent, Physical), manage stake, slash bad actors
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

contract NodeRegistry is Ownable, ReentrancyGuard, Pausable {
    enum NodeType { Validator, Agent, Physical }
    enum NodeStatus { Active, Inactive, Slashed, Deregistered }

    /// @notice Node data
    struct Node {
        uint256 id;
        address operator;
        NodeType nodeType;
        string endpoint;
        uint256 stakeAmount;
        NodeStatus status;
        uint256 registeredAt;
        uint256 lastUpdateAt;
        uint256 slashCount;
        uint256 uptimeScore;
    }

    /// @notice Slash record
    struct SlashRecord {
        uint256 nodeId;
        string reason;
        uint256 amount;
        uint256 timestamp;
        address slashedBy;
    }

    mapping(uint256 => Node) private _nodes;
    mapping(address => uint256[]) private _operatorNodes;
    mapping(NodeType => uint256[]) private _nodesByType;
    mapping(uint256 => SlashRecord[]) private _slashHistory;

    uint256 private _nextNodeId = 1;
    mapping(NodeType => uint256) public minStake;
    uint256 public slashPenaltyBps = 1000; // 10%
    uint256 public totalNodes;
    uint256 public totalStaked;

    /// @notice Emitted when a node is registered
    event NodeRegistered(uint256 indexed nodeId, address indexed operator, NodeType nodeType, string endpoint, uint256 stake);
    /// @notice Emitted when a node is updated
    event NodeUpdated(uint256 indexed nodeId, string newEndpoint);
    /// @notice Emitted when a node is deregistered
    event NodeDeregistered(uint256 indexed nodeId, address indexed operator, uint256 stakeReturned);
    /// @notice Emitted when a node is slashed
    event NodeSlashed(uint256 indexed nodeId, string reason, uint256 amount);
    /// @notice Emitted when uptime is reported
    event UptimeReported(uint256 indexed nodeId, uint256 score);

    error NodeNotFound(uint256 nodeId);
    error NodeNotActive(uint256 nodeId);
    error NotNodeOperator(address caller);
    error InsufficientStake(uint256 sent, uint256 required);
    error EmptyEndpoint();
    error AlreadyDeregistered(uint256 nodeId);

    constructor() {
        minStake[NodeType.Validator] = 1 ether;
        minStake[NodeType.Agent] = 0.5 ether;
        minStake[NodeType.Physical] = 0.1 ether;
    }

    /**
     * @notice Register a new node
     * @param nodeType The type of node (Validator, Agent, Physical)
     * @param endpoint The node's network endpoint
     * @return nodeId The registered node ID
     */
    function registerNode(
        NodeType nodeType,
        string calldata endpoint
    ) external payable nonReentrant whenNotPaused returns (uint256 nodeId) {
        if (bytes(endpoint).length == 0) revert EmptyEndpoint();
        if (msg.value < minStake[nodeType]) revert InsufficientStake(msg.value, minStake[nodeType]);

        nodeId = _nextNodeId++;
        _nodes[nodeId] = Node({
            id: nodeId,
            operator: msg.sender,
            nodeType: nodeType,
            endpoint: endpoint,
            stakeAmount: msg.value,
            status: NodeStatus.Active,
            registeredAt: block.timestamp,
            lastUpdateAt: block.timestamp,
            slashCount: 0,
            uptimeScore: 100
        });

        _operatorNodes[msg.sender].push(nodeId);
        _nodesByType[nodeType].push(nodeId);
        totalNodes++;
        totalStaked += msg.value;

        emit NodeRegistered(nodeId, msg.sender, nodeType, endpoint, msg.value);
    }

    /**
     * @notice Update a node's endpoint
     * @param nodeId The node to update
     * @param newEndpoint The new endpoint URL
     */
    function updateNode(uint256 nodeId, string calldata newEndpoint) external whenNotPaused {
        Node storage node = _nodes[nodeId];
        if (node.id == 0) revert NodeNotFound(nodeId);
        if (node.operator != msg.sender) revert NotNodeOperator(msg.sender);
        if (node.status != NodeStatus.Active) revert NodeNotActive(nodeId);
        if (bytes(newEndpoint).length == 0) revert EmptyEndpoint();

        node.endpoint = newEndpoint;
        node.lastUpdateAt = block.timestamp;

        emit NodeUpdated(nodeId, newEndpoint);
    }

    /**
     * @notice Deregister a node and return stake
     * @param nodeId The node to deregister
     */
    function deregisterNode(uint256 nodeId) external nonReentrant whenNotPaused {
        Node storage node = _nodes[nodeId];
        if (node.id == 0) revert NodeNotFound(nodeId);
        if (node.operator != msg.sender && msg.sender != owner()) revert NotNodeOperator(msg.sender);
        if (node.status == NodeStatus.Deregistered) revert AlreadyDeregistered(nodeId);

        uint256 stakeReturn = node.stakeAmount;
        node.status = NodeStatus.Deregistered;
        node.stakeAmount = 0;
        totalStaked -= stakeReturn;

        if (stakeReturn > 0) {
            (bool success, ) = node.operator.call{value: stakeReturn}("");
            require(success, "Stake return failed");
        }

        emit NodeDeregistered(nodeId, node.operator, stakeReturn);
    }

    /**
     * @notice Get all active nodes of a specific type
     * @param nodeType The node type to filter
     * @return activeNodes Array of active node IDs
     */
    function getActiveNodes(NodeType nodeType) external view returns (uint256[] memory activeNodes) {
        uint256[] storage allIds = _nodesByType[nodeType];
        uint256 activeCount;

        // Count active nodes
        for (uint256 i = 0; i < allIds.length; i++) {
            if (_nodes[allIds[i]].status == NodeStatus.Active) activeCount++;
        }

        activeNodes = new uint256[](activeCount);
        uint256 idx;
        for (uint256 i = 0; i < allIds.length; i++) {
            if (_nodes[allIds[i]].status == NodeStatus.Active) {
                activeNodes[idx++] = allIds[i];
            }
        }
    }

    /**
     * @notice Slash a node for misbehavior (admin only)
     * @param nodeId The node to slash
     * @param reason The slash reason
     */
    function slash(uint256 nodeId, string calldata reason) external onlyOwner {
        Node storage node = _nodes[nodeId];
        if (node.id == 0) revert NodeNotFound(nodeId);
        if (node.status != NodeStatus.Active) revert NodeNotActive(nodeId);

        uint256 penalty = (node.stakeAmount * slashPenaltyBps) / 10000;
        node.stakeAmount -= penalty;
        node.slashCount++;
        totalStaked -= penalty;

        if (node.slashCount >= 3) {
            node.status = NodeStatus.Slashed;
        }

        _slashHistory[nodeId].push(SlashRecord({
            nodeId: nodeId,
            reason: reason,
            amount: penalty,
            timestamp: block.timestamp,
            slashedBy: msg.sender
        }));

        emit NodeSlashed(nodeId, reason, penalty);
    }

    /**
     * @notice Report uptime score for a node
     * @param nodeId The node to report
     * @param score The uptime score (0-100)
     */
    function reportUptime(uint256 nodeId, uint256 score) external onlyOwner {
        Node storage node = _nodes[nodeId];
        if (node.id == 0) revert NodeNotFound(nodeId);
        require(score <= 100, "Score must be <= 100");

        node.uptimeScore = (node.uptimeScore + score) / 2; // Rolling average
        node.lastUpdateAt = block.timestamp;

        emit UptimeReported(nodeId, score);
    }

    /// @notice Get node details
    function getNode(uint256 nodeId) external view returns (Node memory) {
        if (_nodes[nodeId].id == 0) revert NodeNotFound(nodeId);
        return _nodes[nodeId];
    }

    /// @notice Get operator's nodes
    function getOperatorNodes(address operator) external view returns (uint256[] memory) {
        return _operatorNodes[operator];
    }

    /// @notice Get slash history
    function getSlashHistory(uint256 nodeId) external view returns (SlashRecord[] memory) {
        return _slashHistory[nodeId];
    }

    /// @notice Set minimum stake for a node type
    function setMinStake(NodeType nodeType, uint256 amount) external onlyOwner {
        minStake[nodeType] = amount;
    }

    /// @notice Set slash penalty basis points
    function setSlashPenalty(uint256 bps) external onlyOwner {
        require(bps <= 10000, "Max 100%");
        slashPenaltyBps = bps;
    }

    /// @notice Withdraw slashed funds
    function withdrawSlashed() external onlyOwner {
        uint256 excess = address(this).balance - totalStaked;
        require(excess > 0, "No slashed funds");
        (bool success, ) = owner().call{value: excess}("");
        require(success, "Withdraw failed");
    }

    receive() external payable {}
}
