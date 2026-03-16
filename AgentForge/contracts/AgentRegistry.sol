// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title AgentRegistry — Agent lifecycle management for ProbeChain
/// @author ProbeBuilders
/// @notice Register, update, and manage AI agent lifecycles on-chain
/// @dev Implements Ownable and Pausable patterns inline. Deploys on Rydberg Testnet (Chain ID 8004).
contract AgentRegistry {
    // ─── Enums ───────────────────────────────────────────────────────────
    enum AgentStatus { Active, Paused, Deactivated }

    // ─── Structs ─────────────────────────────────────────────────────────
    struct Agent {
        uint256 id;
        address owner;
        string name;
        string capabilities;
        string endpoint;
        uint256 reputationScore;
        AgentStatus status;
        uint256 registeredAt;
        uint256 updatedAt;
    }

    // ─── State ───────────────────────────────────────────────────────────
    address public owner;
    bool public paused;

    uint256 private _nextAgentId;
    mapping(uint256 => Agent) private _agents;
    mapping(address => uint256[]) private _ownerAgents;
    uint256[] private _allAgentIds;

    uint256 public registrationFee;

    // ─── Events ──────────────────────────────────────────────────────────
    event AgentRegistered(uint256 indexed agentId, address indexed agentOwner, string name, string endpoint);
    event AgentUpdated(uint256 indexed agentId, string name, string capabilities, string endpoint);
    event AgentStatusChanged(uint256 indexed agentId, AgentStatus oldStatus, AgentStatus newStatus);
    event AgentDeactivated(uint256 indexed agentId, address indexed agentOwner);
    event ReputationUpdated(uint256 indexed agentId, uint256 oldScore, uint256 newScore);
    event RegistrationFeeUpdated(uint256 oldFee, uint256 newFee);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "AgentRegistry: caller is not the owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "AgentRegistry: paused");
        _;
    }

    modifier onlyAgentOwner(uint256 agentId) {
        require(_agents[agentId].owner == msg.sender, "AgentRegistry: not agent owner");
        _;
    }

    modifier agentExists(uint256 agentId) {
        require(_agents[agentId].registeredAt != 0, "AgentRegistry: agent does not exist");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    /// @notice Deploys the registry and sets the deployer as owner
    /// @param _registrationFee Initial fee (in wei) required to register an agent
    constructor(uint256 _registrationFee) {
        owner = msg.sender;
        registrationFee = _registrationFee;
        _nextAgentId = 1;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── External / Public ───────────────────────────────────────────────

    /// @notice Register a new agent on-chain
    /// @param name Human-readable agent name
    /// @param capabilities Comma-separated capability tags
    /// @param endpoint URL or URI where the agent can be reached
    /// @return agentId The unique ID assigned to the new agent
    function registerAgent(
        string calldata name,
        string calldata capabilities,
        string calldata endpoint
    ) external payable whenNotPaused returns (uint256 agentId) {
        require(bytes(name).length > 0 && bytes(name).length <= 128, "AgentRegistry: invalid name length");
        require(bytes(endpoint).length > 0, "AgentRegistry: endpoint required");
        require(msg.value >= registrationFee, "AgentRegistry: insufficient fee");

        agentId = _nextAgentId++;

        _agents[agentId] = Agent({
            id: agentId,
            owner: msg.sender,
            name: name,
            capabilities: capabilities,
            endpoint: endpoint,
            reputationScore: 50, // start at neutral 50/100
            status: AgentStatus.Active,
            registeredAt: block.timestamp,
            updatedAt: block.timestamp
        });

        _ownerAgents[msg.sender].push(agentId);
        _allAgentIds.push(agentId);

        emit AgentRegistered(agentId, msg.sender, name, endpoint);
    }

    /// @notice Update agent metadata (name, capabilities, endpoint)
    /// @param agentId The agent to update
    /// @param name New name (empty string = keep existing)
    /// @param capabilities New capabilities (empty string = keep existing)
    /// @param endpoint New endpoint (empty string = keep existing)
    function updateAgent(
        uint256 agentId,
        string calldata name,
        string calldata capabilities,
        string calldata endpoint
    ) external whenNotPaused agentExists(agentId) onlyAgentOwner(agentId) {
        Agent storage agent = _agents[agentId];
        require(agent.status != AgentStatus.Deactivated, "AgentRegistry: agent deactivated");

        if (bytes(name).length > 0) {
            require(bytes(name).length <= 128, "AgentRegistry: name too long");
            agent.name = name;
        }
        if (bytes(capabilities).length > 0) {
            agent.capabilities = capabilities;
        }
        if (bytes(endpoint).length > 0) {
            agent.endpoint = endpoint;
        }
        agent.updatedAt = block.timestamp;

        emit AgentUpdated(agentId, agent.name, agent.capabilities, agent.endpoint);
    }

    /// @notice Pause an active agent
    /// @param agentId The agent to pause
    function pauseAgent(uint256 agentId) external agentExists(agentId) onlyAgentOwner(agentId) {
        Agent storage agent = _agents[agentId];
        require(agent.status == AgentStatus.Active, "AgentRegistry: agent not active");

        AgentStatus old = agent.status;
        agent.status = AgentStatus.Paused;
        agent.updatedAt = block.timestamp;

        emit AgentStatusChanged(agentId, old, AgentStatus.Paused);
    }

    /// @notice Resume a paused agent
    /// @param agentId The agent to resume
    function resumeAgent(uint256 agentId) external agentExists(agentId) onlyAgentOwner(agentId) {
        Agent storage agent = _agents[agentId];
        require(agent.status == AgentStatus.Paused, "AgentRegistry: agent not paused");

        AgentStatus old = agent.status;
        agent.status = AgentStatus.Active;
        agent.updatedAt = block.timestamp;

        emit AgentStatusChanged(agentId, old, AgentStatus.Active);
    }

    /// @notice Permanently deactivate an agent (irreversible)
    /// @param agentId The agent to deactivate
    function deactivateAgent(uint256 agentId) external agentExists(agentId) onlyAgentOwner(agentId) {
        Agent storage agent = _agents[agentId];
        require(agent.status != AgentStatus.Deactivated, "AgentRegistry: already deactivated");

        AgentStatus old = agent.status;
        agent.status = AgentStatus.Deactivated;
        agent.updatedAt = block.timestamp;

        emit AgentDeactivated(agentId, msg.sender);
        emit AgentStatusChanged(agentId, old, AgentStatus.Deactivated);
    }

    /// @notice Get full agent details
    /// @param agentId The agent to query
    /// @return The Agent struct
    function getAgent(uint256 agentId) external view agentExists(agentId) returns (Agent memory) {
        return _agents[agentId];
    }

    /// @notice List all agent IDs (paginated)
    /// @param offset Start index
    /// @param limit Max number of results
    /// @return ids Array of agent IDs
    function listAgents(uint256 offset, uint256 limit) external view returns (uint256[] memory ids) {
        uint256 total = _allAgentIds.length;
        if (offset >= total) return new uint256[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 count = end - offset;

        ids = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            ids[i] = _allAgentIds[offset + i];
        }
    }

    /// @notice List agent IDs owned by a specific address
    /// @param agentOwner The address to query
    /// @return Array of agent IDs
    function listAgentsByOwner(address agentOwner) external view returns (uint256[] memory) {
        return _ownerAgents[agentOwner];
    }

    /// @notice Total number of registered agents
    function totalAgents() external view returns (uint256) {
        return _allAgentIds.length;
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    /// @notice Adjust an agent's reputation (admin only)
    /// @param agentId The agent
    /// @param newScore New reputation score (0-100)
    function setReputation(uint256 agentId, uint256 newScore) external onlyOwner agentExists(agentId) {
        require(newScore <= 100, "AgentRegistry: score out of range");
        uint256 oldScore = _agents[agentId].reputationScore;
        _agents[agentId].reputationScore = newScore;
        _agents[agentId].updatedAt = block.timestamp;
        emit ReputationUpdated(agentId, oldScore, newScore);
    }

    /// @notice Update the registration fee
    /// @param newFee New fee in wei
    function setRegistrationFee(uint256 newFee) external onlyOwner {
        uint256 oldFee = registrationFee;
        registrationFee = newFee;
        emit RegistrationFeeUpdated(oldFee, newFee);
    }

    /// @notice Pause all registration and updates
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Transfer ownership
    /// @param newOwner New owner address
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "AgentRegistry: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Withdraw collected fees
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "AgentRegistry: no balance");
        (bool ok, ) = payable(owner).call{value: balance}("");
        require(ok, "AgentRegistry: transfer failed");
    }
}
