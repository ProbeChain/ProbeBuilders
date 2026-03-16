// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title KnowledgeGraph
 * @author ProbeChain Rydberg Testnet
 * @notice Decentralized knowledge graph for storing nodes, edges, and rewarding contributors
 * @dev On-chain knowledge network with path querying and contributor incentives
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
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
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

contract KnowledgeGraph is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum Category { Concept, Entity, Event, Relation, Property }

    // ---------- Structs ----------
    struct KNode {
        uint256 id;
        address contributor;
        string label;
        bytes32 dataHash;
        Category category;
        uint256 edgeCount;
        uint256 citations;
        uint256 createdAt;
        bool verified;
    }

    struct Edge {
        uint256 id;
        uint256 fromNode;
        uint256 toNode;
        string relationship;
        address contributor;
        uint256 createdAt;
        bool verified;
    }

    struct PathResult {
        uint256[] nodeIds;
        uint256[] edgeIds;
        bool found;
    }

    // ---------- State ----------
    uint256 public nextNodeId;
    uint256 public nextEdgeId;
    uint256 public rewardPerContribution;
    uint256 public rewardPool;

    mapping(uint256 => KNode) public nodes;
    mapping(uint256 => Edge) public edges;
    mapping(uint256 => uint256[]) public nodeOutEdges;
    mapping(uint256 => uint256[]) public nodeInEdges;
    mapping(address => uint256) public contributorRewards;
    mapping(address => uint256) public contributionCount;
    mapping(address => bool) public verifiers;

    // ---------- Events ----------
    /// @notice Emitted when a knowledge node is added
    event NodeAdded(uint256 indexed nodeId, address indexed contributor, string label, Category category);
    /// @notice Emitted when an edge is added between nodes
    event EdgeAdded(uint256 indexed edgeId, uint256 indexed fromNode, uint256 indexed toNode, string relationship);
    /// @notice Emitted when a node is verified
    event NodeVerified(uint256 indexed nodeId, address indexed verifier);
    /// @notice Emitted when an edge is verified
    event EdgeVerified(uint256 indexed edgeId, address indexed verifier);
    /// @notice Emitted when a contributor claims rewards
    event RewardClaimed(address indexed contributor, uint256 amount);
    /// @notice Emitted when reward pool is funded
    event RewardPoolFunded(uint256 amount);
    /// @notice Emitted when a path query result is logged
    event PathQueried(uint256 indexed startNode, uint256 indexed endNode, bool found, uint256 pathLength);

    // ---------- Constructor ----------
    constructor(uint256 _rewardPerContribution) Ownable() ReentrancyGuard() Pausable() {
        rewardPerContribution = _rewardPerContribution;
        nextNodeId = 1;
        nextEdgeId = 1;
    }

    /// @notice Fund the reward pool
    function fundRewardPool() external payable {
        require(msg.value > 0, "Must send funds");
        rewardPool += msg.value;
        emit RewardPoolFunded(msg.value);
    }

    /// @notice Add a verifier
    function addVerifier(address verifier) external onlyOwner {
        require(verifier != address(0), "Zero address");
        verifiers[verifier] = true;
    }

    /// @notice Remove a verifier
    function removeVerifier(address verifier) external onlyOwner {
        verifiers[verifier] = false;
    }

    // ---------- Core Functions ----------
    /**
     * @notice Add a node to the knowledge graph
     * @param label Human-readable label for the node
     * @param dataHash IPFS hash of full node data
     * @param category The category of the node
     * @return nodeId The created node identifier
     */
    function addNode(string calldata label, bytes32 dataHash, Category category)
        external
        whenNotPaused
        returns (uint256 nodeId)
    {
        require(bytes(label).length > 0 && bytes(label).length <= 256, "Invalid label length");
        require(dataHash != bytes32(0), "Empty data hash");

        nodeId = nextNodeId++;
        KNode storage n = nodes[nodeId];
        n.id = nodeId;
        n.contributor = msg.sender;
        n.label = label;
        n.dataHash = dataHash;
        n.category = category;
        n.createdAt = block.timestamp;

        contributionCount[msg.sender]++;
        _accrueReward(msg.sender);

        emit NodeAdded(nodeId, msg.sender, label, category);
    }

    /**
     * @notice Add an edge connecting two nodes
     * @param fromNode Source node ID
     * @param toNode Target node ID
     * @param relationship Description of the relationship
     * @return edgeId The created edge identifier
     */
    function addEdge(uint256 fromNode, uint256 toNode, string calldata relationship)
        external
        whenNotPaused
        returns (uint256 edgeId)
    {
        require(nodes[fromNode].id != 0, "From node does not exist");
        require(nodes[toNode].id != 0, "To node does not exist");
        require(fromNode != toNode, "Self-referencing edge");
        require(bytes(relationship).length > 0 && bytes(relationship).length <= 128, "Invalid relationship");

        edgeId = nextEdgeId++;
        Edge storage e = edges[edgeId];
        e.id = edgeId;
        e.fromNode = fromNode;
        e.toNode = toNode;
        e.relationship = relationship;
        e.contributor = msg.sender;
        e.createdAt = block.timestamp;

        nodeOutEdges[fromNode].push(edgeId);
        nodeInEdges[toNode].push(edgeId);
        nodes[fromNode].edgeCount++;
        nodes[toNode].edgeCount++;

        contributionCount[msg.sender]++;
        _accrueReward(msg.sender);

        emit EdgeAdded(edgeId, fromNode, toNode, relationship);
    }

    /**
     * @notice Verify a node (verifier only)
     * @param nodeId The node to verify
     */
    function verifyNode(uint256 nodeId) external whenNotPaused {
        require(verifiers[msg.sender], "Not a verifier");
        KNode storage n = nodes[nodeId];
        require(n.id != 0, "Node does not exist");
        require(!n.verified, "Already verified");
        n.verified = true;
        emit NodeVerified(nodeId, msg.sender);
    }

    /**
     * @notice Verify an edge (verifier only)
     * @param edgeId The edge to verify
     */
    function verifyEdge(uint256 edgeId) external whenNotPaused {
        require(verifiers[msg.sender], "Not a verifier");
        Edge storage e = edges[edgeId];
        require(e.id != 0, "Edge does not exist");
        require(!e.verified, "Already verified");
        e.verified = true;
        emit EdgeVerified(edgeId, msg.sender);
    }

    /**
     * @notice Query a direct path between two nodes (one hop via edges)
     * @param startNode The starting node
     * @param endNode The destination node
     * @return found Whether a direct edge exists
     * @return edgeIds Array of edges connecting startNode to endNode
     */
    function queryPath(uint256 startNode, uint256 endNode)
        external
        view
        returns (bool found, uint256[] memory edgeIds)
    {
        uint256[] storage outEdges = nodeOutEdges[startNode];
        uint256 count;
        for (uint256 i = 0; i < outEdges.length; i++) {
            if (edges[outEdges[i]].toNode == endNode) count++;
        }

        edgeIds = new uint256[](count);
        uint256 idx;
        for (uint256 i = 0; i < outEdges.length; i++) {
            if (edges[outEdges[i]].toNode == endNode) {
                edgeIds[idx++] = outEdges[i];
            }
        }

        found = count > 0;
    }

    /**
     * @notice Claim accumulated contributor rewards
     */
    function rewardContributor() external nonReentrant whenNotPaused {
        uint256 amount = contributorRewards[msg.sender];
        require(amount > 0, "No rewards to claim");
        require(rewardPool >= amount, "Insufficient reward pool");

        contributorRewards[msg.sender] = 0;
        rewardPool -= amount;

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");

        emit RewardClaimed(msg.sender, amount);
    }

    // ---------- Internal ----------
    function _accrueReward(address contributor) internal {
        contributorRewards[contributor] += rewardPerContribution;
    }

    // ---------- View Functions ----------
    /**
     * @notice Get outgoing edges from a node
     * @param nodeId The node to query
     * @return Array of edge IDs
     */
    function getOutEdges(uint256 nodeId) external view returns (uint256[] memory) {
        return nodeOutEdges[nodeId];
    }

    /**
     * @notice Get incoming edges to a node
     * @param nodeId The node to query
     * @return Array of edge IDs
     */
    function getInEdges(uint256 nodeId) external view returns (uint256[] memory) {
        return nodeInEdges[nodeId];
    }

    /// @notice Update reward per contribution
    function setRewardPerContribution(uint256 _reward) external onlyOwner {
        rewardPerContribution = _reward;
    }
}
