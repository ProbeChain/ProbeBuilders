// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title CommitRevealVote — Anonymous voting with commit-reveal scheme for ProbeChain
/// @author ProbeBuilders
/// @notice Create polls, commit hashed votes, reveal votes, tally results. Prevents front-running.
/// @dev Two-phase voting: commit phase (submit hash), reveal phase (reveal vote + salt). Rydberg Testnet (Chain ID 8004).
contract CommitRevealVote {
    // ─── Enums & Structs ─────────────────────────────────────────────────
    enum PollStatus { CommitPhase, RevealPhase, Tallied, Cancelled }

    struct Poll {
        uint256 id;
        address creator;
        string question;
        uint256 optionCount;
        uint256 commitDeadline;
        uint256 revealDeadline;
        PollStatus status;
        uint256 totalRevealed;
        uint256 totalCommitted;
        uint256 createdAt;
    }

    struct Commit {
        bytes32 commitHash;
        bool revealed;
        uint256 revealedOption;
        uint256 committedAt;
    }

    struct PollResult {
        uint256 pollId;
        uint256[] voteCounts;
        uint256 totalVotes;
        uint256 winningOption;
        uint256 winningVotes;
    }

    // ─── State ───────────────────────────────────────────────────────────
    address public owner;
    bool public paused;

    uint256 private _nextPollId = 1;

    mapping(uint256 => Poll) public polls;
    mapping(uint256 => string[]) private _pollOptions;
    mapping(uint256 => mapping(address => Commit)) private _commits;
    mapping(uint256 => mapping(uint256 => uint256)) private _voteCounts; // pollId => optionId => count
    mapping(uint256 => PollResult) private _results;
    mapping(address => uint256[]) private _creatorPolls;

    uint256 public totalPolls;
    uint256 public minCommitDuration = 1 hours;
    uint256 public minRevealDuration = 1 hours;

    // ─── Events ──────────────────────────────────────────────────────────
    event PollCreated(uint256 indexed pollId, address indexed creator, string question, string[] options, uint256 commitDeadline, uint256 revealDeadline);
    event VoteCommitted(uint256 indexed pollId, address indexed voter, bytes32 commitHash);
    event VoteRevealed(uint256 indexed pollId, address indexed voter, uint256 optionId);
    event PollTallied(uint256 indexed pollId, uint256 winningOption, uint256 winningVotes, uint256 totalVotes);
    event PollCancelled(uint256 indexed pollId, address indexed canceller);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "CommitRevealVote: not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "CommitRevealVote: paused");
        _;
    }

    modifier pollExists(uint256 pollId) {
        require(polls[pollId].createdAt != 0, "CommitRevealVote: poll not found");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Poll Creation ───────────────────────────────────────────────────

    /// @notice Create a new poll with commit-reveal voting
    /// @param question The poll question
    /// @param options Array of option strings (2-20 options)
    /// @param commitDuration Seconds for the commit phase
    /// @param revealDuration Seconds for the reveal phase
    /// @return pollId The new poll ID
    function createPoll(
        string calldata question,
        string[] calldata options,
        uint256 commitDuration,
        uint256 revealDuration
    ) external whenNotPaused returns (uint256 pollId) {
        require(bytes(question).length > 0 && bytes(question).length <= 1024, "CommitRevealVote: invalid question");
        require(options.length >= 2 && options.length <= 20, "CommitRevealVote: 2-20 options required");
        require(commitDuration >= minCommitDuration, "CommitRevealVote: commit too short");
        require(revealDuration >= minRevealDuration, "CommitRevealVote: reveal too short");

        pollId = _nextPollId++;
        uint256 commitDeadline = block.timestamp + commitDuration;
        uint256 revealDeadline = commitDeadline + revealDuration;

        polls[pollId] = Poll({
            id: pollId,
            creator: msg.sender,
            question: question,
            optionCount: options.length,
            commitDeadline: commitDeadline,
            revealDeadline: revealDeadline,
            status: PollStatus.CommitPhase,
            totalRevealed: 0,
            totalCommitted: 0,
            createdAt: block.timestamp
        });

        for (uint256 i; i < options.length; ++i) {
            require(bytes(options[i]).length > 0, "CommitRevealVote: empty option");
            _pollOptions[pollId].push(options[i]);
        }

        _creatorPolls[msg.sender].push(pollId);
        totalPolls++;

        emit PollCreated(pollId, msg.sender, question, options, commitDeadline, revealDeadline);
    }

    // ─── Commit Phase ────────────────────────────────────────────────────

    /// @notice Commit a hashed vote (hash = keccak256(abi.encodePacked(pollId, optionId, salt)))
    /// @param pollId The poll to vote on
    /// @param commitHash The hash of (pollId, optionId, salt)
    function commitVote(uint256 pollId, bytes32 commitHash) external whenNotPaused pollExists(pollId) {
        Poll storage poll = polls[pollId];
        require(block.timestamp <= poll.commitDeadline, "CommitRevealVote: commit phase ended");
        require(poll.status == PollStatus.CommitPhase, "CommitRevealVote: not in commit phase");
        require(_commits[pollId][msg.sender].committedAt == 0, "CommitRevealVote: already committed");
        require(commitHash != bytes32(0), "CommitRevealVote: empty hash");

        _commits[pollId][msg.sender] = Commit({
            commitHash: commitHash,
            revealed: false,
            revealedOption: 0,
            committedAt: block.timestamp
        });

        poll.totalCommitted++;

        emit VoteCommitted(pollId, msg.sender, commitHash);
    }

    // ─── Reveal Phase ────────────────────────────────────────────────────

    /// @notice Reveal a previously committed vote
    /// @param pollId The poll
    /// @param optionId The option that was voted for
    /// @param salt The random salt used in the commit hash
    function revealVote(uint256 pollId, uint256 optionId, bytes32 salt) external pollExists(pollId) {
        Poll storage poll = polls[pollId];

        // Auto-transition to reveal phase
        if (poll.status == PollStatus.CommitPhase && block.timestamp > poll.commitDeadline) {
            poll.status = PollStatus.RevealPhase;
        }

        require(poll.status == PollStatus.RevealPhase, "CommitRevealVote: not in reveal phase");
        require(block.timestamp <= poll.revealDeadline, "CommitRevealVote: reveal phase ended");
        require(optionId < poll.optionCount, "CommitRevealVote: invalid option");

        Commit storage commit = _commits[pollId][msg.sender];
        require(commit.committedAt != 0, "CommitRevealVote: no commit found");
        require(!commit.revealed, "CommitRevealVote: already revealed");

        // Verify hash
        bytes32 expectedHash = keccak256(abi.encodePacked(pollId, optionId, salt));
        require(commit.commitHash == expectedHash, "CommitRevealVote: hash mismatch");

        commit.revealed = true;
        commit.revealedOption = optionId;

        _voteCounts[pollId][optionId]++;
        poll.totalRevealed++;

        emit VoteRevealed(pollId, msg.sender, optionId);
    }

    // ─── Tally ───────────────────────────────────────────────────────────

    /// @notice Tally the results after reveal phase ends
    /// @param pollId The poll to tally
    function tallyResults(uint256 pollId) external pollExists(pollId) {
        Poll storage poll = polls[pollId];

        // Auto-transition if needed
        if (poll.status == PollStatus.CommitPhase && block.timestamp > poll.commitDeadline) {
            poll.status = PollStatus.RevealPhase;
        }

        require(
            poll.status == PollStatus.RevealPhase && block.timestamp > poll.revealDeadline,
            "CommitRevealVote: reveal phase not ended"
        );

        uint256[] memory counts = new uint256[](poll.optionCount);
        uint256 winningOption;
        uint256 winningVotes;

        for (uint256 i; i < poll.optionCount; ++i) {
            counts[i] = _voteCounts[pollId][i];
            if (counts[i] > winningVotes) {
                winningVotes = counts[i];
                winningOption = i;
            }
        }

        _results[pollId] = PollResult({
            pollId: pollId,
            voteCounts: counts,
            totalVotes: poll.totalRevealed,
            winningOption: winningOption,
            winningVotes: winningVotes
        });

        poll.status = PollStatus.Tallied;

        emit PollTallied(pollId, winningOption, winningVotes, poll.totalRevealed);
    }

    /// @notice Cancel a poll (creator or admin only)
    /// @param pollId The poll to cancel
    function cancelPoll(uint256 pollId) external pollExists(pollId) {
        Poll storage poll = polls[pollId];
        require(msg.sender == poll.creator || msg.sender == owner, "CommitRevealVote: not authorized");
        require(poll.status != PollStatus.Tallied, "CommitRevealVote: already tallied");

        poll.status = PollStatus.Cancelled;
        emit PollCancelled(pollId, msg.sender);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Get poll options
    /// @param pollId The poll to query
    /// @return options Array of option strings
    function getPollOptions(uint256 pollId) external view pollExists(pollId) returns (string[] memory) {
        return _pollOptions[pollId];
    }

    /// @notice Get results for a tallied poll
    /// @param pollId The poll to query
    /// @return result The poll result
    function getResults(uint256 pollId) external view returns (PollResult memory result) {
        require(polls[pollId].status == PollStatus.Tallied, "CommitRevealVote: not tallied");
        return _results[pollId];
    }

    /// @notice Get current status of a poll (with auto-transition logic)
    /// @param pollId The poll
    /// @return The effective status
    function getEffectiveStatus(uint256 pollId) external view pollExists(pollId) returns (PollStatus) {
        Poll storage poll = polls[pollId];
        if (poll.status == PollStatus.Cancelled || poll.status == PollStatus.Tallied) {
            return poll.status;
        }
        if (block.timestamp <= poll.commitDeadline) return PollStatus.CommitPhase;
        if (block.timestamp <= poll.revealDeadline) return PollStatus.RevealPhase;
        return PollStatus.RevealPhase; // awaiting tally
    }

    /// @notice Get vote count for a specific option
    /// @param pollId The poll
    /// @param optionId The option
    /// @return Number of revealed votes for this option
    function getOptionVotes(uint256 pollId, uint256 optionId) external view returns (uint256) {
        require(polls[pollId].status == PollStatus.Tallied, "CommitRevealVote: not tallied");
        return _voteCounts[pollId][optionId];
    }

    /// @notice Check if a voter has committed
    function hasCommitted(uint256 pollId, address voter) external view returns (bool) {
        return _commits[pollId][voter].committedAt != 0;
    }

    /// @notice Check if a voter has revealed
    function hasRevealed(uint256 pollId, address voter) external view returns (bool) {
        return _commits[pollId][voter].revealed;
    }

    /// @notice Helper: compute commit hash off-chain or verify on-chain
    /// @param pollId The poll ID
    /// @param optionId The option being voted for
    /// @param salt Random salt
    /// @return The keccak256 hash
    function computeCommitHash(uint256 pollId, uint256 optionId, bytes32 salt) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(pollId, optionId, salt));
    }

    /// @notice Get polls created by an address
    function getCreatorPolls(address creator) external view returns (uint256[] memory) {
        return _creatorPolls[creator];
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    function setMinCommitDuration(uint256 duration) external onlyOwner {
        require(duration >= 10 minutes, "CommitRevealVote: too short");
        minCommitDuration = duration;
    }

    function setMinRevealDuration(uint256 duration) external onlyOwner {
        require(duration >= 10 minutes, "CommitRevealVote: too short");
        minRevealDuration = duration;
    }

    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "CommitRevealVote: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
