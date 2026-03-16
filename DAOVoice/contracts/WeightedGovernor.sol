// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title WeightedGovernor
 * @author ProbeChain
 * @notice Weighted governance contract. Voting power comes from staked tokens multiplied
 *         by a reputation score. Proposals can encode on-chain actions for execution.
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London).
 */

// ── Ownable ────────────────────────────────────────────────────────────────────
abstract contract Ownable {
    address private _owner;
    error OwnableUnauthorized(address account);
    error OwnableInvalidOwner(address owner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    function owner() public view virtual returns (address) { return _owner; }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorized(msg.sender); _; }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ── ReentrancyGuard ────────────────────────────────────────────────────────────
abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status != 1) revert ReentrancyGuardReentrantCall();
        _status = 2; _; _status = 1;
    }
}

// ── Pausable ───────────────────────────────────────────────────────────────────
abstract contract Pausable is Ownable {
    bool private _paused;
    error EnforcedPause(); error ExpectedPause();
    event Paused(address account); event Unpaused(address account);
    function paused() public view returns (bool) { return _paused; }
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    modifier whenPaused() { if (!_paused) revert ExpectedPause(); _; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

// ── WeightedGovernor ───────────────────────────────────────────────────────────
contract WeightedGovernor is Ownable, ReentrancyGuard, Pausable {

    enum ProposalState { Active, Passed, Rejected, Executed, Cancelled }

    struct Action {
        address target;
        uint256 value;
        bytes data;
    }

    struct Proposal {
        uint256 id;
        address proposer;
        string title;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        ProposalState state;
        bool executed;
    }

    uint256 public nextProposalId;
    uint256 public votingDuration = 3 days;
    uint256 public quorumBps = 1000; // 10 % of total staked
    uint256 public totalStaked;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => Action[]) private _actions;
    mapping(address => uint256) public staked;
    mapping(address => uint256) public reputation; // 100 = 1x multiplier
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // ── Events ─────────────────────────────────────────────────────────────────
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string title, uint256 endTime);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event ReputationUpdated(address indexed user, uint256 newReputation);

    // ── Errors ─────────────────────────────────────────────────────────────────
    error EmptyProposal();
    error ProposalNotFound();
    error ProposalNotActive();
    error AlreadyVoted();
    error NoVotingPower();
    error ProposalStillActive();
    error ProposalNotPassed();
    error ExecutionFailed();
    error InsufficientStake();
    error NothingStaked();
    error TransferFailed();
    error NotProposer();

    // ── Staking ────────────────────────────────────────────────────────────────
    /// @notice Stake native tokens to gain voting power.
    function stake() external payable whenNotPaused {
        if (msg.value == 0) revert InsufficientStake();
        staked[msg.sender] += msg.value;
        totalStaked += msg.value;
        if (reputation[msg.sender] == 0) reputation[msg.sender] = 100; // default 1x
        emit Staked(msg.sender, msg.value);
    }

    /// @notice Unstake tokens.
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        if (staked[msg.sender] < amount || amount == 0) revert NothingStaked();
        staked[msg.sender] -= amount;
        totalStaked -= amount;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Unstaked(msg.sender, amount);
    }

    // ── Reputation ─────────────────────────────────────────────────────────────
    /// @notice Owner or authorized address sets a user's reputation multiplier.
    /// @param user User address.
    /// @param rep  Reputation score (100 = 1x, 200 = 2x, etc.).
    function setReputation(address user, uint256 rep) external onlyOwner {
        reputation[user] = rep;
        emit ReputationUpdated(user, rep);
    }

    // ── Voting power ───────────────────────────────────────────────────────────
    /// @notice Compute voting power = staked * (reputation / 100).
    function votingPower(address user) public view returns (uint256) {
        uint256 rep = reputation[user];
        if (rep == 0) rep = 100;
        return (staked[user] * rep) / 100;
    }

    // ── Proposals ──────────────────────────────────────────────────────────────
    /// @notice Create a governance proposal.
    /// @param title       Short title.
    /// @param description Detailed description.
    /// @param targets     Target addresses for actions.
    /// @param values      ETH values for each action.
    /// @param calldatas   Encoded calldata for each action.
    function createProposal(
        string calldata title,
        string calldata description,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external whenNotPaused returns (uint256 proposalId) {
        if (bytes(title).length == 0) revert EmptyProposal();
        if (votingPower(msg.sender) == 0) revert NoVotingPower();

        proposalId = nextProposalId++;
        uint256 endTime = block.timestamp + votingDuration;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            title: title,
            description: description,
            forVotes: 0,
            againstVotes: 0,
            startTime: block.timestamp,
            endTime: endTime,
            state: ProposalState.Active,
            executed: false
        });

        for (uint256 i = 0; i < targets.length; i++) {
            _actions[proposalId].push(Action(targets[i], values[i], calldatas[i]));
        }

        emit ProposalCreated(proposalId, msg.sender, title, endTime);
    }

    // ── Voting ─────────────────────────────────────────────────────────────────
    /// @notice Cast a weighted vote on a proposal.
    /// @param proposalId  Proposal to vote on.
    /// @param weight      Amount of voting power to commit (up to max).
    /// @param support     True = for, false = against.
    function castVote(uint256 proposalId, uint256 weight, bool support) external whenNotPaused {
        Proposal storage p = proposals[proposalId];
        if (p.startTime == 0) revert ProposalNotFound();
        if (p.state != ProposalState.Active || block.timestamp > p.endTime) revert ProposalNotActive();
        if (hasVoted[proposalId][msg.sender]) revert AlreadyVoted();

        uint256 maxPower = votingPower(msg.sender);
        if (maxPower == 0) revert NoVotingPower();
        uint256 w = weight > maxPower ? maxPower : weight;

        hasVoted[proposalId][msg.sender] = true;
        if (support) {
            p.forVotes += w;
        } else {
            p.againstVotes += w;
        }
        emit VoteCast(proposalId, msg.sender, support, w);
    }

    // ── Execution ──────────────────────────────────────────────────────────────
    /// @notice Execute a passed proposal.
    function executeProposal(uint256 proposalId) external nonReentrant whenNotPaused {
        Proposal storage p = proposals[proposalId];
        if (p.startTime == 0) revert ProposalNotFound();
        if (block.timestamp <= p.endTime) revert ProposalStillActive();

        // Finalize state if still active
        if (p.state == ProposalState.Active) {
            uint256 quorum = (totalStaked * quorumBps) / 10_000;
            if (p.forVotes > p.againstVotes && (p.forVotes + p.againstVotes) >= quorum) {
                p.state = ProposalState.Passed;
            } else {
                p.state = ProposalState.Rejected;
                revert ProposalNotPassed();
            }
        }
        if (p.state != ProposalState.Passed) revert ProposalNotPassed();
        p.state = ProposalState.Executed;
        p.executed = true;

        Action[] storage actions = _actions[proposalId];
        for (uint256 i = 0; i < actions.length; i++) {
            (bool ok, ) = actions[i].target.call{value: actions[i].value}(actions[i].data);
            if (!ok) revert ExecutionFailed();
        }
        emit ProposalExecuted(proposalId);
    }

    /// @notice Proposer can cancel their own active proposal.
    function cancelProposal(uint256 proposalId) external whenNotPaused {
        Proposal storage p = proposals[proposalId];
        if (p.startTime == 0) revert ProposalNotFound();
        if (msg.sender != p.proposer && msg.sender != owner()) revert NotProposer();
        if (p.state != ProposalState.Active) revert ProposalNotActive();
        p.state = ProposalState.Cancelled;
        emit ProposalCancelled(proposalId);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────
    /// @notice Update voting duration.
    function setVotingDuration(uint256 duration) external onlyOwner {
        votingDuration = duration;
    }

    /// @notice Update quorum basis points.
    function setQuorum(uint256 bps) external onlyOwner {
        quorumBps = bps;
    }

    // ── Views ──────────────────────────────────────────────────────────────────
    /// @notice Get the actions attached to a proposal.
    function getActions(uint256 proposalId) external view returns (Action[] memory) {
        return _actions[proposalId];
    }

    /// @notice Receive native tokens (for proposal execution funding).
    receive() external payable {}
}
