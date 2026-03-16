// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ForumContract
 * @author ProbeChain
 * @notice Decentralized forum with threads, replies, voting, tipping, and karma scoring.
 *         Moderation privileges are granted to users who stake tokens.
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

// ── ForumContract ──────────────────────────────────────────────────────────────
contract ForumContract is Ownable, ReentrancyGuard, Pausable {

    // ── Structs ────────────────────────────────────────────────────────────────
    struct Thread {
        uint256 id;
        address author;
        string title;
        string contentHash;
        string category;
        uint256 createdAt;
        uint256 replyCount;
        bool deleted;
    }

    struct Post {
        uint256 id;
        uint256 threadId;
        address author;
        string contentHash;
        uint256 createdAt;
        int256 score;
        bool deleted;
    }

    // ── State ──────────────────────────────────────────────────────────────────
    uint256 public nextThreadId;
    uint256 public nextPostId;
    uint256 public minModStake = 1 ether;

    mapping(uint256 => Thread) public threads;
    mapping(uint256 => Post) public posts;
    mapping(address => int256) public karma;
    mapping(address => uint256) public stakedAmount;
    mapping(address => mapping(uint256 => bool)) private _voted;

    // ── Events ─────────────────────────────────────────────────────────────────
    event ThreadCreated(uint256 indexed threadId, address indexed author, string title, string category);
    event ReplyPosted(uint256 indexed postId, uint256 indexed threadId, address indexed author);
    event Upvoted(uint256 indexed postId, address indexed voter);
    event Downvoted(uint256 indexed postId, address indexed voter);
    event AuthorTipped(uint256 indexed postId, address indexed tipper, uint256 amount);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event ContentModerated(uint256 indexed id, bool isThread, address indexed moderator);

    // ── Errors ─────────────────────────────────────────────────────────────────
    error EmptyContent();
    error ThreadNotFound();
    error PostNotFound();
    error AlreadyVoted();
    error CannotVoteOwnPost();
    error InsufficientStake();
    error NothingToUnstake();
    error TipFailed();
    error ContentDeleted();

    // ── Moderation ─────────────────────────────────────────────────────────────
    modifier onlyModerator() {
        if (stakedAmount[msg.sender] < minModStake && msg.sender != owner())
            revert InsufficientStake();
        _;
    }

    // ── Staking ────────────────────────────────────────────────────────────────
    /// @notice Stake native tokens to gain moderation rights.
    function stake() external payable whenNotPaused {
        if (msg.value == 0) revert InsufficientStake();
        stakedAmount[msg.sender] += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    /// @notice Withdraw staked tokens.
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        if (stakedAmount[msg.sender] < amount || amount == 0) revert NothingToUnstake();
        stakedAmount[msg.sender] -= amount;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TipFailed();
        emit Unstaked(msg.sender, amount);
    }

    // ── Threads ────────────────────────────────────────────────────────────────
    /// @notice Create a new discussion thread.
    /// @param title       Human-readable thread title.
    /// @param contentHash IPFS / Arweave hash of the body.
    /// @param category    Forum category tag.
    function createThread(
        string calldata title,
        string calldata contentHash,
        string calldata category
    ) external whenNotPaused returns (uint256 threadId) {
        if (bytes(title).length == 0 || bytes(contentHash).length == 0) revert EmptyContent();
        threadId = nextThreadId++;
        threads[threadId] = Thread(threadId, msg.sender, title, contentHash, category, block.timestamp, 0, false);
        karma[msg.sender] += 1;
        emit ThreadCreated(threadId, msg.sender, title, category);
    }

    // ── Replies ────────────────────────────────────────────────────────────────
    /// @notice Post a reply to an existing thread.
    function postReply(uint256 threadId, string calldata contentHash) external whenNotPaused returns (uint256 postId) {
        if (threads[threadId].createdAt == 0 || threads[threadId].deleted) revert ThreadNotFound();
        if (bytes(contentHash).length == 0) revert EmptyContent();
        postId = nextPostId++;
        posts[postId] = Post(postId, threadId, msg.sender, contentHash, block.timestamp, 0, false);
        threads[threadId].replyCount++;
        karma[msg.sender] += 1;
        emit ReplyPosted(postId, threadId, msg.sender);
    }

    // ── Voting ─────────────────────────────────────────────────────────────────
    /// @notice Upvote a post (+1 karma to author).
    function upvote(uint256 postId) external whenNotPaused {
        Post storage p = posts[postId];
        if (p.createdAt == 0 || p.deleted) revert PostNotFound();
        if (p.author == msg.sender) revert CannotVoteOwnPost();
        if (_voted[msg.sender][postId]) revert AlreadyVoted();
        _voted[msg.sender][postId] = true;
        p.score += 1;
        karma[p.author] += 1;
        emit Upvoted(postId, msg.sender);
    }

    /// @notice Downvote a post (-1 karma to author).
    function downvote(uint256 postId) external whenNotPaused {
        Post storage p = posts[postId];
        if (p.createdAt == 0 || p.deleted) revert PostNotFound();
        if (p.author == msg.sender) revert CannotVoteOwnPost();
        if (_voted[msg.sender][postId]) revert AlreadyVoted();
        _voted[msg.sender][postId] = true;
        p.score -= 1;
        karma[p.author] -= 1;
        emit Downvoted(postId, msg.sender);
    }

    // ── Tipping ────────────────────────────────────────────────────────────────
    /// @notice Tip a post author with native tokens.
    function tipAuthor(uint256 postId) external payable nonReentrant whenNotPaused {
        Post storage p = posts[postId];
        if (p.createdAt == 0 || p.deleted) revert PostNotFound();
        if (msg.value == 0) revert EmptyContent();
        karma[p.author] += int256(msg.value / 1e15);
        (bool ok, ) = payable(p.author).call{value: msg.value}("");
        if (!ok) revert TipFailed();
        emit AuthorTipped(postId, msg.sender, msg.value);
    }

    // ── Moderation ─────────────────────────────────────────────────────────────
    /// @notice Moderator deletes a thread (soft-delete).
    function moderateThread(uint256 threadId) external onlyModerator whenNotPaused {
        if (threads[threadId].createdAt == 0) revert ThreadNotFound();
        threads[threadId].deleted = true;
        emit ContentModerated(threadId, true, msg.sender);
    }

    /// @notice Moderator deletes a post (soft-delete).
    function moderatePost(uint256 postId) external onlyModerator whenNotPaused {
        if (posts[postId].createdAt == 0) revert PostNotFound();
        posts[postId].deleted = true;
        emit ContentModerated(postId, false, msg.sender);
    }

    /// @notice Owner updates the minimum stake required for moderation.
    function setMinModStake(uint256 newMin) external onlyOwner {
        minModStake = newMin;
    }

    // ── Views ──────────────────────────────────────────────────────────────────
    /// @notice Check whether a user has voted on a given post.
    function hasVoted(address user, uint256 postId) external view returns (bool) {
        return _voted[user][postId];
    }
}
