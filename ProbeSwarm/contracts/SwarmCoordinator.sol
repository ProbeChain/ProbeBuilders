// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SwarmCoordinator
 * @author ProbeChain Rydberg Testnet
 * @notice Multi-agent swarm coordination contract for task decomposition and execution
 * @dev Manages swarm registration, task assignment, completion reporting, and finalization
 */

// ---------- Inlined Ownable ----------
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

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

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// ---------- Inlined Pausable ----------
abstract contract Pausable is Ownable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function pause() external onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract SwarmCoordinator is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum SwarmStatus { Created, Active, Completed, Cancelled }
    enum SubtaskStatus { Pending, Assigned, Completed, Failed }

    // ---------- Structs ----------
    struct Swarm {
        uint256 id;
        address creator;
        bytes32 taskHash;
        address[] agents;
        SwarmStatus status;
        uint256 createdAt;
        uint256 completedAt;
        uint256 completedSubtasks;
        uint256 totalSubtasks;
    }

    struct Subtask {
        uint256 swarmId;
        address assignedAgent;
        bytes32 subtaskHash;
        bytes32 resultHash;
        SubtaskStatus status;
        uint256 assignedAt;
        uint256 completedAt;
    }

    // ---------- State ----------
    uint256 public nextSwarmId;
    uint256 public nextSubtaskId;

    mapping(uint256 => Swarm) public swarms;
    mapping(uint256 => Subtask) public subtasks;
    mapping(uint256 => uint256[]) public swarmSubtasks;
    mapping(address => bool) public registeredAgents;
    mapping(address => uint256) public agentCompletions;
    mapping(uint256 => mapping(address => bool)) public swarmAgentMembership;

    // ---------- Events ----------
    /// @notice Emitted when a new swarm is registered
    event SwarmRegistered(uint256 indexed swarmId, address indexed creator, bytes32 taskHash, uint256 agentCount);
    /// @notice Emitted when a task is assigned to an agent within a swarm
    event TaskAssigned(uint256 indexed swarmId, uint256 indexed subtaskId, address indexed agent, bytes32 subtaskHash);
    /// @notice Emitted when an agent reports subtask completion
    event CompletionReported(uint256 indexed swarmId, uint256 indexed subtaskId, address indexed agent, bytes32 resultHash);
    /// @notice Emitted when a swarm is finalized
    event SwarmFinalized(uint256 indexed swarmId, uint256 completedSubtasks, uint256 totalSubtasks);
    /// @notice Emitted when a swarm is cancelled
    event SwarmCancelled(uint256 indexed swarmId, address indexed canceller);
    /// @notice Emitted when an agent is globally registered
    event AgentRegistered(address indexed agent);

    // ---------- Constructor ----------
    constructor() Ownable() ReentrancyGuard() Pausable() {
        nextSwarmId = 1;
        nextSubtaskId = 1;
    }

    // ---------- Agent Registration ----------
    /**
     * @notice Register an address as a valid agent
     * @param agent The agent address to register
     */
    function registerAgent(address agent) external onlyOwner {
        require(agent != address(0), "Invalid agent address");
        require(!registeredAgents[agent], "Agent already registered");
        registeredAgents[agent] = true;
        emit AgentRegistered(agent);
    }

    // ---------- Core Functions ----------
    /**
     * @notice Register a new multi-agent swarm
     * @param agents Array of agent addresses composing the swarm
     * @param taskHash IPFS or data hash describing the overarching task
     * @return swarmId The newly created swarm identifier
     */
    function registerSwarm(address[] calldata agents, bytes32 taskHash)
        external
        whenNotPaused
        returns (uint256 swarmId)
    {
        require(agents.length >= 2, "Swarm requires at least 2 agents");
        require(agents.length <= 50, "Swarm max 50 agents");
        require(taskHash != bytes32(0), "Empty task hash");

        for (uint256 i = 0; i < agents.length; i++) {
            require(registeredAgents[agents[i]], "Unregistered agent");
            for (uint256 j = i + 1; j < agents.length; j++) {
                require(agents[i] != agents[j], "Duplicate agent");
            }
        }

        swarmId = nextSwarmId++;
        Swarm storage s = swarms[swarmId];
        s.id = swarmId;
        s.creator = msg.sender;
        s.taskHash = taskHash;
        s.agents = agents;
        s.status = SwarmStatus.Active;
        s.createdAt = block.timestamp;

        for (uint256 i = 0; i < agents.length; i++) {
            swarmAgentMembership[swarmId][agents[i]] = true;
        }

        emit SwarmRegistered(swarmId, msg.sender, taskHash, agents.length);
    }

    /**
     * @notice Assign a subtask to an agent within a swarm
     * @param swarmId The target swarm
     * @param agentId The agent address receiving the subtask
     * @param subtaskHash Hash describing the subtask details
     * @return subtaskId The subtask identifier
     */
    function assignTask(uint256 swarmId, address agentId, bytes32 subtaskHash)
        external
        whenNotPaused
        returns (uint256 subtaskId)
    {
        Swarm storage s = swarms[swarmId];
        require(s.status == SwarmStatus.Active, "Swarm not active");
        require(msg.sender == s.creator || msg.sender == owner(), "Not authorized");
        require(swarmAgentMembership[swarmId][agentId], "Agent not in swarm");
        require(subtaskHash != bytes32(0), "Empty subtask hash");

        subtaskId = nextSubtaskId++;
        Subtask storage st = subtasks[subtaskId];
        st.swarmId = swarmId;
        st.assignedAgent = agentId;
        st.subtaskHash = subtaskHash;
        st.status = SubtaskStatus.Assigned;
        st.assignedAt = block.timestamp;

        swarmSubtasks[swarmId].push(subtaskId);
        s.totalSubtasks++;

        emit TaskAssigned(swarmId, subtaskId, agentId, subtaskHash);
    }

    /**
     * @notice Report completion of an assigned subtask
     * @param swarmId The swarm containing the subtask
     * @param subtaskId The subtask being reported
     * @param resultHash Hash of the subtask result data
     */
    function reportCompletion(uint256 swarmId, uint256 subtaskId, bytes32 resultHash)
        external
        whenNotPaused
    {
        Swarm storage s = swarms[swarmId];
        require(s.status == SwarmStatus.Active, "Swarm not active");

        Subtask storage st = subtasks[subtaskId];
        require(st.swarmId == swarmId, "Subtask not in swarm");
        require(st.assignedAgent == msg.sender, "Not assigned agent");
        require(st.status == SubtaskStatus.Assigned, "Subtask not assigned");
        require(resultHash != bytes32(0), "Empty result hash");

        st.resultHash = resultHash;
        st.status = SubtaskStatus.Completed;
        st.completedAt = block.timestamp;
        s.completedSubtasks++;
        agentCompletions[msg.sender]++;

        emit CompletionReported(swarmId, subtaskId, msg.sender, resultHash);
    }

    /**
     * @notice Finalize a swarm after all subtasks are handled
     * @param swarmId The swarm to finalize
     */
    function finalizeSwarm(uint256 swarmId) external whenNotPaused {
        Swarm storage s = swarms[swarmId];
        require(s.status == SwarmStatus.Active, "Swarm not active");
        require(msg.sender == s.creator || msg.sender == owner(), "Not authorized");
        require(s.completedSubtasks > 0, "No completed subtasks");

        s.status = SwarmStatus.Completed;
        s.completedAt = block.timestamp;

        emit SwarmFinalized(swarmId, s.completedSubtasks, s.totalSubtasks);
    }

    /**
     * @notice Cancel an active swarm
     * @param swarmId The swarm to cancel
     */
    function cancelSwarm(uint256 swarmId) external {
        Swarm storage s = swarms[swarmId];
        require(s.status == SwarmStatus.Active, "Swarm not active");
        require(msg.sender == s.creator || msg.sender == owner(), "Not authorized");

        s.status = SwarmStatus.Cancelled;
        emit SwarmCancelled(swarmId, msg.sender);
    }

    // ---------- View Functions ----------
    /**
     * @notice Get the list of subtask IDs for a swarm
     * @param swarmId The swarm to query
     * @return Array of subtask IDs
     */
    function getSwarmSubtasks(uint256 swarmId) external view returns (uint256[] memory) {
        return swarmSubtasks[swarmId];
    }

    /**
     * @notice Get the list of agents in a swarm
     * @param swarmId The swarm to query
     * @return Array of agent addresses
     */
    function getSwarmAgents(uint256 swarmId) external view returns (address[] memory) {
        return swarms[swarmId].agents;
    }

    /**
     * @notice Get swarm completion percentage (basis points)
     * @param swarmId The swarm to query
     * @return Completion percentage in basis points (0-10000)
     */
    function getSwarmProgress(uint256 swarmId) external view returns (uint256) {
        Swarm storage s = swarms[swarmId];
        if (s.totalSubtasks == 0) return 0;
        return (s.completedSubtasks * 10000) / s.totalSubtasks;
    }
}
