// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ProtocolGovernor
 * @author ProbeChain Team
 * @notice On-chain governance with proposals, voting, timelock, and quorum for ProbeChain
 * @dev Full governance lifecycle: propose -> vote -> queue -> execute with configurable parameters
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

contract ProtocolGovernor is Ownable, ReentrancyGuard, Pausable {
    enum ProposalState { Pending, Active, Defeated, Succeeded, Queued, Executed, Cancelled }
    enum VoteType { Against, For, Abstain }

    /// @notice Proposal data
    struct Proposal {
        uint256 id;
        address proposer;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
        uint256 startBlock;
        uint256 endBlock;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool queued;
        bool executed;
        bool cancelled;
        uint256 queuedAt;
    }

    /// @notice Vote receipt
    struct Receipt {
        bool hasVoted;
        VoteType support;
        uint256 weight;
    }

    mapping(uint256 => Proposal) private _proposals;
    mapping(uint256 => mapping(address => Receipt)) private _receipts;
    mapping(address => uint256) private _votingPower;

    uint256 private _nextProposalId = 1;
    uint256 public votingDelay = 1;        // blocks
    uint256 public votingPeriod = 50400;   // ~7 days at 12s blocks
    uint256 public quorumVotes = 100 ether; // minimum votes for quorum
    uint256 public timelockDelay = 2 days;
    uint256 public proposalThreshold = 10 ether;

    /// @notice Emitted when a proposal is created
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    /// @notice Emitted when a vote is cast
    event VoteCast(address indexed voter, uint256 indexed proposalId, VoteType support, uint256 weight);
    /// @notice Emitted when a proposal is queued
    event ProposalQueued(uint256 indexed proposalId, uint256 eta);
    /// @notice Emitted when a proposal is executed
    event ProposalExecuted(uint256 indexed proposalId);
    /// @notice Emitted when a proposal is cancelled
    event ProposalCancelled(uint256 indexed proposalId);
    /// @notice Emitted when voting power is delegated
    event VotingPowerSet(address indexed account, uint256 power);

    error ProposalNotFound(uint256 proposalId);
    error ProposalNotActive(uint256 proposalId);
    error ProposalNotSucceeded(uint256 proposalId);
    error ProposalNotQueued(uint256 proposalId);
    error TimelockNotExpired(uint256 proposalId);
    error AlreadyVoted(address voter, uint256 proposalId);
    error InsufficientVotingPower(uint256 power, uint256 required);
    error ArrayLengthMismatch();
    error EmptyProposal();

    /**
     * @notice Create a new governance proposal
     * @param targets Array of target contract addresses
     * @param values Array of ETH values to send
     * @param calldatas Array of encoded function calls
     * @param description Human-readable proposal description
     * @return proposalId The created proposal ID
     */
    function propose(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        string calldata description
    ) external whenNotPaused returns (uint256 proposalId) {
        if (targets.length == 0) revert EmptyProposal();
        if (targets.length != values.length || targets.length != calldatas.length) revert ArrayLengthMismatch();
        if (_votingPower[msg.sender] < proposalThreshold) {
            revert InsufficientVotingPower(_votingPower[msg.sender], proposalThreshold);
        }

        proposalId = _nextProposalId++;

        Proposal storage p = _proposals[proposalId];
        p.id = proposalId;
        p.proposer = msg.sender;
        p.targets = targets;
        p.values = values;
        p.calldatas = calldatas;
        p.description = description;
        p.startBlock = block.number + votingDelay;
        p.endBlock = block.number + votingDelay + votingPeriod;

        emit ProposalCreated(proposalId, msg.sender, description);
    }

    /**
     * @notice Cast a vote on an active proposal
     * @param proposalId The proposal to vote on
     * @param support The vote type (0=Against, 1=For, 2=Abstain)
     */
    function castVote(uint256 proposalId, VoteType support) external whenNotPaused {
        Proposal storage p = _proposals[proposalId];
        if (p.id == 0) revert ProposalNotFound(proposalId);
        if (block.number < p.startBlock || block.number > p.endBlock) revert ProposalNotActive(proposalId);

        Receipt storage receipt = _receipts[proposalId][msg.sender];
        if (receipt.hasVoted) revert AlreadyVoted(msg.sender, proposalId);

        uint256 weight = _votingPower[msg.sender];
        if (weight == 0) revert InsufficientVotingPower(0, 1);

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.weight = weight;

        if (support == VoteType.For) {
            p.forVotes += weight;
        } else if (support == VoteType.Against) {
            p.againstVotes += weight;
        } else {
            p.abstainVotes += weight;
        }

        emit VoteCast(msg.sender, proposalId, support, weight);
    }

    /**
     * @notice Queue a succeeded proposal for execution
     * @param proposalId The proposal to queue
     */
    function queue(uint256 proposalId) external whenNotPaused {
        Proposal storage p = _proposals[proposalId];
        if (p.id == 0) revert ProposalNotFound(proposalId);
        if (state(proposalId) != ProposalState.Succeeded) revert ProposalNotSucceeded(proposalId);

        p.queued = true;
        p.queuedAt = block.timestamp;

        emit ProposalQueued(proposalId, block.timestamp + timelockDelay);
    }

    /**
     * @notice Execute a queued proposal after timelock
     * @param proposalId The proposal to execute
     */
    function execute(uint256 proposalId) external nonReentrant whenNotPaused {
        Proposal storage p = _proposals[proposalId];
        if (p.id == 0) revert ProposalNotFound(proposalId);
        if (!p.queued) revert ProposalNotQueued(proposalId);
        if (block.timestamp < p.queuedAt + timelockDelay) revert TimelockNotExpired(proposalId);

        p.executed = true;

        for (uint256 i = 0; i < p.targets.length; i++) {
            (bool success, ) = p.targets[i].call{value: p.values[i]}(p.calldatas[i]);
            require(success, "Execution failed");
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Cancel a proposal (proposer or owner only)
     * @param proposalId The proposal to cancel
     */
    function cancel(uint256 proposalId) external {
        Proposal storage p = _proposals[proposalId];
        if (p.id == 0) revert ProposalNotFound(proposalId);
        require(msg.sender == p.proposer || msg.sender == owner(), "Unauthorized");
        p.cancelled = true;
        emit ProposalCancelled(proposalId);
    }

    /**
     * @notice Get the current state of a proposal
     * @param proposalId The proposal to query
     * @return The proposal state
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage p = _proposals[proposalId];
        if (p.id == 0) revert ProposalNotFound(proposalId);
        if (p.cancelled) return ProposalState.Cancelled;
        if (p.executed) return ProposalState.Executed;
        if (block.number < p.startBlock) return ProposalState.Pending;
        if (block.number <= p.endBlock) return ProposalState.Active;
        if (p.forVotes <= p.againstVotes || p.forVotes + p.againstVotes + p.abstainVotes < quorumVotes) {
            return ProposalState.Defeated;
        }
        if (p.queued) return ProposalState.Queued;
        return ProposalState.Succeeded;
    }

    /**
     * @notice Get proposal details
     * @param proposalId The proposal ID
     * @return proposal The proposal data
     */
    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        if (_proposals[proposalId].id == 0) revert ProposalNotFound(proposalId);
        return _proposals[proposalId];
    }

    /**
     * @notice Get vote receipt
     * @param proposalId The proposal ID
     * @param voter The voter address
     * @return receipt The vote receipt
     */
    function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory receipt) {
        return _receipts[proposalId][voter];
    }

    /// @notice Set voting power for an account (admin function for testnet)
    function setVotingPower(address account, uint256 power) external onlyOwner {
        _votingPower[account] = power;
        emit VotingPowerSet(account, power);
    }

    /// @notice Get voting power
    function getVotingPower(address account) external view returns (uint256) { return _votingPower[account]; }

    /// @notice Update governance parameters
    function setVotingDelay(uint256 delay) external onlyOwner { votingDelay = delay; }
    function setVotingPeriod(uint256 period) external onlyOwner { votingPeriod = period; }
    function setQuorumVotes(uint256 quorum) external onlyOwner { quorumVotes = quorum; }
    function setTimelockDelay(uint256 delay) external onlyOwner { timelockDelay = delay; }
    function setProposalThreshold(uint256 threshold) external onlyOwner { proposalThreshold = threshold; }

    receive() external payable {}
}
