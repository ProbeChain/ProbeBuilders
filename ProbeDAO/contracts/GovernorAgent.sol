// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title GovernorAgent — DAO governance with AI-assisted proposals for ProbeChain
/// @author ProbeBuilders
/// @notice Create proposals, vote, queue with timelock, and execute on-chain governance actions
/// @dev Implements Ownable inline. Rydberg Testnet (Chain ID 8004).
contract GovernorAgent {
    // ─── Enums & Structs ─────────────────────────────────────────────────
    enum ProposalState { Pending, Active, Succeeded, Defeated, Queued, Executed, Cancelled, Expired }
    enum VoteType { Against, For, Abstain }

    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 startTime;
        uint256 endTime;
        uint256 executionTime; // timelock target
        bool executed;
        bool cancelled;
        bytes[] actions;       // encoded function calls
        address[] targets;
        uint256[] values;
    }

    struct Receipt {
        bool hasVoted;
        VoteType voteType;
        uint256 weight;
    }

    // ─── State ───────────────────────────────────────────────────────────
    address public owner;
    bool public paused;

    uint256 private _nextProposalId = 1;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Receipt)) public receipts;
    mapping(address => uint256) public votingPower; // simplified: admin-assigned voting power

    uint256 public votingPeriod = 3 days;
    uint256 public timelockDelay = 1 days;
    uint256 public quorumVotes = 100e18; // minimum total votes needed
    uint256 public proposalThreshold = 10e18; // min voting power to propose

    uint256 public totalProposals;
    uint256[] private _allProposalIds;

    // ─── Events ──────────────────────────────────────────────────────────
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description, uint256 startTime, uint256 endTime);
    event VoteCast(uint256 indexed proposalId, address indexed voter, VoteType voteType, uint256 weight);
    event ProposalQueued(uint256 indexed proposalId, uint256 executionTime);
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    event ProposalCancelled(uint256 indexed proposalId, address indexed canceller);
    event VotingPowerUpdated(address indexed account, uint256 oldPower, uint256 newPower);
    event QuorumUpdated(uint256 oldQuorum, uint256 newQuorum);
    event VotingPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "GovernorAgent: not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "GovernorAgent: paused");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        votingPower[msg.sender] = 1000e18; // founder gets initial voting power
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Proposal Management ─────────────────────────────────────────────

    /// @notice Create a new governance proposal
    /// @param description Proposal description (plain text or IPFS hash)
    /// @param targets Target contract addresses for execution
    /// @param values ETH values for each action
    /// @param actions Encoded function calls
    /// @return proposalId The new proposal ID
    function createProposal(
        string calldata description,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata actions
    ) external whenNotPaused returns (uint256 proposalId) {
        require(votingPower[msg.sender] >= proposalThreshold, "GovernorAgent: below threshold");
        require(bytes(description).length > 0 && bytes(description).length <= 4096, "GovernorAgent: invalid description");
        require(targets.length == values.length && values.length == actions.length, "GovernorAgent: length mismatch");
        require(targets.length > 0 && targets.length <= 10, "GovernorAgent: invalid action count");

        proposalId = _nextProposalId++;

        Proposal storage p = proposals[proposalId];
        p.id = proposalId;
        p.proposer = msg.sender;
        p.description = description;
        p.startTime = block.timestamp;
        p.endTime = block.timestamp + votingPeriod;
        p.targets = targets;
        p.values = values;
        p.actions = actions;

        _allProposalIds.push(proposalId);
        totalProposals++;

        emit ProposalCreated(proposalId, msg.sender, description, p.startTime, p.endTime);
    }

    /// @notice Cast a vote on a proposal
    /// @param proposalId The proposal to vote on
    /// @param support Vote type (0=Against, 1=For, 2=Abstain)
    function vote(uint256 proposalId, VoteType support) external whenNotPaused {
        Proposal storage p = proposals[proposalId];
        require(p.startTime != 0, "GovernorAgent: proposal not found");
        require(_state(p) == ProposalState.Active, "GovernorAgent: not active");

        Receipt storage receipt = receipts[proposalId][msg.sender];
        require(!receipt.hasVoted, "GovernorAgent: already voted");

        uint256 weight = votingPower[msg.sender];
        require(weight > 0, "GovernorAgent: no voting power");

        receipt.hasVoted = true;
        receipt.voteType = support;
        receipt.weight = weight;

        if (support == VoteType.For) {
            p.forVotes += weight;
        } else if (support == VoteType.Against) {
            p.againstVotes += weight;
        } else {
            p.abstainVotes += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    /// @notice Queue a succeeded proposal for timelock execution
    /// @param proposalId The proposal to queue
    function queueProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(_state(p) == ProposalState.Succeeded, "GovernorAgent: not succeeded");

        p.executionTime = block.timestamp + timelockDelay;

        emit ProposalQueued(proposalId, p.executionTime);
    }

    /// @notice Execute a queued proposal after timelock
    /// @param proposalId The proposal to execute
    function executeProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(_state(p) == ProposalState.Queued, "GovernorAgent: not queued");
        require(block.timestamp >= p.executionTime, "GovernorAgent: timelock not expired");

        p.executed = true;

        for (uint256 i; i < p.targets.length; ++i) {
            (bool success, ) = p.targets[i].call{value: p.values[i]}(p.actions[i]);
            require(success, "GovernorAgent: action execution failed");
        }

        emit ProposalExecuted(proposalId, msg.sender);
    }

    /// @notice Cancel a proposal (proposer or owner)
    /// @param proposalId The proposal to cancel
    function cancelProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        require(p.startTime != 0, "GovernorAgent: proposal not found");
        require(!p.executed, "GovernorAgent: already executed");
        require(msg.sender == p.proposer || msg.sender == owner, "GovernorAgent: not authorized");

        p.cancelled = true;

        emit ProposalCancelled(proposalId, msg.sender);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Get the current state of a proposal
    /// @param proposalId The proposal to query
    /// @return The proposal state
    function getProposalState(uint256 proposalId) external view returns (ProposalState) {
        Proposal storage p = proposals[proposalId];
        require(p.startTime != 0, "GovernorAgent: proposal not found");
        return _state(p);
    }

    /// @notice Get proposal details
    function getProposal(uint256 proposalId) external view returns (
        address proposer,
        string memory description,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes,
        uint256 startTime,
        uint256 endTime,
        ProposalState state
    ) {
        Proposal storage p = proposals[proposalId];
        require(p.startTime != 0, "GovernorAgent: proposal not found");
        return (p.proposer, p.description, p.forVotes, p.againstVotes, p.abstainVotes, p.startTime, p.endTime, _state(p));
    }

    /// @notice Get all proposal IDs (paginated)
    function listProposals(uint256 offset, uint256 limit) external view returns (uint256[] memory ids) {
        uint256 total = _allProposalIds.length;
        if (offset >= total) return new uint256[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 count = end - offset;

        ids = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            ids[i] = _allProposalIds[offset + i];
        }
    }

    /// @notice Check if an address has voted on a proposal
    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        return receipts[proposalId][voter].hasVoted;
    }

    // ─── Internal ────────────────────────────────────────────────────────

    /// @dev Determine proposal state
    function _state(Proposal storage p) internal view returns (ProposalState) {
        if (p.cancelled) return ProposalState.Cancelled;
        if (p.executed) return ProposalState.Executed;

        if (block.timestamp < p.startTime) return ProposalState.Pending;

        if (block.timestamp <= p.endTime) return ProposalState.Active;

        // Voting ended
        uint256 totalVotes = p.forVotes + p.againstVotes + p.abstainVotes;
        bool quorumReached = totalVotes >= quorumVotes;
        bool passed = p.forVotes > p.againstVotes;

        if (!quorumReached || !passed) return ProposalState.Defeated;

        if (p.executionTime == 0) return ProposalState.Succeeded;

        // Queued
        if (block.timestamp < p.executionTime + 7 days) return ProposalState.Queued;

        return ProposalState.Expired; // grace period passed
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    /// @notice Set voting power for an address
    function setVotingPower(address account, uint256 power) external onlyOwner {
        uint256 old = votingPower[account];
        votingPower[account] = power;
        emit VotingPowerUpdated(account, old, power);
    }

    /// @notice Batch set voting power
    function batchSetVotingPower(address[] calldata accounts, uint256[] calldata powers) external onlyOwner {
        require(accounts.length == powers.length, "GovernorAgent: length mismatch");
        for (uint256 i; i < accounts.length; ++i) {
            uint256 old = votingPower[accounts[i]];
            votingPower[accounts[i]] = powers[i];
            emit VotingPowerUpdated(accounts[i], old, powers[i]);
        }
    }

    function setQuorum(uint256 newQuorum) external onlyOwner {
        uint256 old = quorumVotes;
        quorumVotes = newQuorum;
        emit QuorumUpdated(old, newQuorum);
    }

    function setVotingPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod >= 1 hours, "GovernorAgent: period too short");
        uint256 old = votingPeriod;
        votingPeriod = newPeriod;
        emit VotingPeriodUpdated(old, newPeriod);
    }

    function setTimelockDelay(uint256 newDelay) external onlyOwner {
        require(newDelay >= 1 hours, "GovernorAgent: delay too short");
        timelockDelay = newDelay;
    }

    function setProposalThreshold(uint256 newThreshold) external onlyOwner {
        proposalThreshold = newThreshold;
    }

    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "GovernorAgent: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Allow contract to receive ETH for proposal execution
    receive() external payable {}
}
