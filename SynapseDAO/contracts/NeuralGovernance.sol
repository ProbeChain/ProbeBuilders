// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NeuralGovernance
 * @author ProbeChain
 * @notice Conviction voting governance — the longer a voter locks tokens, the more
 *         weight their vote carries. Supports proposal creation, staking, conviction-
 *         weighted voting, and on-chain execution.
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

// ── NeuralGovernance ───────────────────────────────────────────────────────────
contract NeuralGovernance is Ownable, ReentrancyGuard, Pausable {

    /// @dev Conviction multiplier tiers (lock period -> multiplier)
    ///  0 = no lock  -> 1x
    ///  1 = 7 days   -> 2x
    ///  2 = 30 days  -> 4x
    ///  3 = 90 days  -> 8x

    enum ProposalState { Active, Passed, Rejected, Executed, Cancelled }

    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        ProposalState state;
    }

    struct StakeInfo {
        uint256 amount;
        uint256 lockedUntil;
        uint256 convictionLevel; // 0-3
    }

    struct VoteRecord {
        bool voted;
        bool support;
        uint256 weight;
    }

    uint256 public nextProposalId;
    uint256 public votingDuration = 5 days;
    uint256 public quorumThreshold = 10 ether;
    uint256 public totalStaked;
    uint256 public minProposalStake = 1 ether;

    uint256[4] public lockDurations = [0, 7 days, 30 days, 90 days];
    uint256[4] public convictionMultipliers = [1, 2, 4, 8];

    mapping(uint256 => Proposal) public proposals;
    mapping(address => StakeInfo) public stakes;
    mapping(uint256 => mapping(address => VoteRecord)) public voteRecords;

    // ── Events ─────────────────────────────────────────────────────────────────
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description, uint256 endTime);
    event Staked(address indexed user, uint256 amount, uint256 convictionLevel, uint256 lockedUntil);
    event Unstaked(address indexed user, uint256 amount);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight, uint256 conviction);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);

    // ── Errors ─────────────────────────────────────────────────────────────────
    error EmptyDescription();
    error InsufficientStake();
    error InvalidConviction();
    error StakeStillLocked();
    error NothingStaked();
    error ProposalNotFound();
    error ProposalNotActive();
    error AlreadyVoted();
    error NoVotingPower();
    error ProposalStillActive();
    error ProposalNotPassed();
    error NotProposer();
    error TransferFailed();

    // ── Staking ────────────────────────────────────────────────────────────────
    /// @notice Stake tokens with a conviction level (0-3). Higher = longer lock = more weight.
    /// @param conviction Conviction level: 0 (no lock, 1x), 1 (7d, 2x), 2 (30d, 4x), 3 (90d, 8x).
    function stake(uint256 conviction) external payable whenNotPaused {
        if (msg.value == 0) revert InsufficientStake();
        if (conviction > 3) revert InvalidConviction();

        StakeInfo storage s = stakes[msg.sender];

        // If already staked, must wait for unlock first (or add to existing)
        if (s.amount > 0 && s.lockedUntil > block.timestamp) {
            // Can only add more at same or higher conviction
            if (conviction < s.convictionLevel) revert InvalidConviction();
        }

        s.amount += msg.value;
        s.convictionLevel = conviction;
        s.lockedUntil = block.timestamp + lockDurations[conviction];
        totalStaked += msg.value;

        emit Staked(msg.sender, msg.value, conviction, s.lockedUntil);
    }

    /// @notice Unstake tokens after lock period expires.
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        StakeInfo storage s = stakes[msg.sender];
        if (s.amount == 0 || amount == 0) revert NothingStaked();
        if (s.lockedUntil > block.timestamp) revert StakeStillLocked();
        if (amount > s.amount) amount = s.amount;

        s.amount -= amount;
        totalStaked -= amount;
        if (s.amount == 0) s.convictionLevel = 0;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Unstaked(msg.sender, amount);
    }

    // ── Voting Power ───────────────────────────────────────────────────────────
    /// @notice Calculate voting power = staked * conviction multiplier.
    function votingPower(address user) public view returns (uint256) {
        StakeInfo storage s = stakes[user];
        if (s.amount == 0) return 0;
        return s.amount * convictionMultipliers[s.convictionLevel];
    }

    // ── Proposals ──────────────────────────────────────────────────────────────
    /// @notice Create a new governance proposal.
    /// @param description Description of the proposal.
    function createProposal(string calldata description) external whenNotPaused returns (uint256 proposalId) {
        if (bytes(description).length == 0) revert EmptyDescription();
        if (stakes[msg.sender].amount < minProposalStake) revert InsufficientStake();

        proposalId = nextProposalId++;
        uint256 endTime = block.timestamp + votingDuration;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            description: description,
            forVotes: 0,
            againstVotes: 0,
            startTime: block.timestamp,
            endTime: endTime,
            state: ProposalState.Active
        });

        emit ProposalCreated(proposalId, msg.sender, description, endTime);
    }

    // ── Voting ─────────────────────────────────────────────────────────────────
    /// @notice Vote on a proposal with conviction-weighted power.
    /// @param proposalId  Proposal to vote on.
    /// @param support     True = for, false = against.
    /// @param conviction  Conviction level for this vote (0-3, capped by stake conviction).
    function vote(
        uint256 proposalId,
        bool support,
        uint256 conviction
    ) external whenNotPaused {
        Proposal storage p = proposals[proposalId];
        if (p.startTime == 0) revert ProposalNotFound();
        if (p.state != ProposalState.Active || block.timestamp > p.endTime) revert ProposalNotActive();
        if (voteRecords[proposalId][msg.sender].voted) revert AlreadyVoted();

        StakeInfo storage s = stakes[msg.sender];
        if (s.amount == 0) revert NoVotingPower();

        // Cap conviction at user's staked conviction level
        uint256 effConviction = conviction > s.convictionLevel ? s.convictionLevel : conviction;
        uint256 weight = s.amount * convictionMultipliers[effConviction];

        // Extend lock if voting with higher conviction
        uint256 newLock = block.timestamp + lockDurations[effConviction];
        if (newLock > s.lockedUntil) {
            s.lockedUntil = newLock;
            s.convictionLevel = effConviction;
        }

        voteRecords[proposalId][msg.sender] = VoteRecord(true, support, weight);

        if (support) {
            p.forVotes += weight;
        } else {
            p.againstVotes += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight, effConviction);
    }

    // ── Execution ──────────────────────────────────────────────────────────────
    /// @notice Execute a proposal after voting ends (if passed quorum and majority).
    function executeProposal(uint256 proposalId) external whenNotPaused {
        Proposal storage p = proposals[proposalId];
        if (p.startTime == 0) revert ProposalNotFound();
        if (block.timestamp <= p.endTime) revert ProposalStillActive();

        if (p.state == ProposalState.Active) {
            bool quorumMet = (p.forVotes + p.againstVotes) >= quorumThreshold;
            if (quorumMet && p.forVotes > p.againstVotes) {
                p.state = ProposalState.Passed;
            } else {
                p.state = ProposalState.Rejected;
                revert ProposalNotPassed();
            }
        }

        if (p.state != ProposalState.Passed) revert ProposalNotPassed();
        p.state = ProposalState.Executed;
        emit ProposalExecuted(proposalId);
    }

    /// @notice Proposer or owner cancels an active proposal.
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

    /// @notice Update quorum threshold.
    function setQuorumThreshold(uint256 threshold) external onlyOwner {
        quorumThreshold = threshold;
    }

    /// @notice Update minimum stake to create proposals.
    function setMinProposalStake(uint256 minStake) external onlyOwner {
        minProposalStake = minStake;
    }

    // ── Views ──────────────────────────────────────────────────────────────────
    /// @notice Get a voter's record on a specific proposal.
    function getVoteRecord(uint256 proposalId, address voter) external view returns (VoteRecord memory) {
        return voteRecords[proposalId][voter];
    }

    /// @notice Get stake details for a user.
    function getStakeInfo(address user) external view returns (StakeInfo memory) {
        return stakes[user];
    }

    /// @notice Receive native tokens for funding.
    receive() external payable {}
}
