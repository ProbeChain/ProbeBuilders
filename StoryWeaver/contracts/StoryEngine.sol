// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title StoryEngine
 * @author ProbeChain Builders
 * @notice Interactive fiction engine with community-voted branching narratives
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London)
 */

// ──────────────────────────────────────────────────────────────
// Inline Ownable
// ──────────────────────────────────────────────────────────────
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed prev, address indexed next_);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address n) external onlyOwner {
        require(n != address(0), "Ownable: zero");
        emit OwnershipTransferred(_owner, n); _owner = n;
    }
}

// ──────────────────────────────────────────────────────────────
// Inline ReentrancyGuard
// ──────────────────────────────────────────────────────────────
abstract contract ReentrancyGuard {
    uint256 private _s = 1;
    modifier nonReentrant() { require(_s == 1, "ReentrancyGuard: reentrant"); _s = 2; _; _s = 1; }
}

// ──────────────────────────────────────────────────────────────
// Inline Pausable
// ──────────────────────────────────────────────────────────────
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
}

// ──────────────────────────────────────────────────────────────
// StoryEngine
// ──────────────────────────────────────────────────────────────
contract StoryEngine is Ownable, ReentrancyGuard, Pausable {

    // ── Structs ──────────────────────────────────────────────
    struct Story {
        string title;
        address author;
        bytes32 openingHash;        // IPFS hash of opening content
        uint256 currentNodeId;       // Current active node in the story
        uint256 nodeCount;
        uint256 totalVoters;
        uint256 votingPeriod;        // Seconds for each voting round
        uint256 lastAdvancedAt;
        bool active;
        uint256 createdAt;
    }

    struct StoryNode {
        uint256 storyId;
        uint256 parentNodeId;        // 0 for root
        string choiceText;           // Text describing this choice
        bytes32 contentHash;         // IPFS hash of full content
        address author;
        uint256[] childBranchIds;
        uint256 depth;
        uint256 createdAt;
    }

    struct Branch {
        uint256 storyId;
        uint256 parentNodeId;
        uint256 nodeId;              // The node this branch leads to
        string choiceText;
        bytes32 contentHash;
        address author;
        uint256 votes;
        uint256 createdAt;
    }

    // ── State ────────────────────────────────────────────────
    uint256 public storyCounter;
    uint256 public nodeCounter;
    uint256 public branchCounter;
    uint256 public defaultVotingPeriod = 1 days;

    mapping(uint256 => Story) public stories;
    mapping(uint256 => StoryNode) public nodes;
    mapping(uint256 => Branch) public branches;

    /// @dev storyId => nodeId => branchIds
    mapping(uint256 => mapping(uint256 => uint256[])) public nodeBranches;
    /// @dev branchId => voter => hasVoted
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    /// @dev storyId => voter => totalVotes cast
    mapping(uint256 => mapping(address => uint256)) public voterContributions;

    // ── Events ───────────────────────────────────────────────
    event StoryCreated(uint256 indexed storyId, string title, address indexed author, bytes32 openingHash);
    event BranchAdded(uint256 indexed branchId, uint256 indexed storyId, uint256 parentNodeId, string choiceText, address author);
    event Voted(uint256 indexed branchId, address indexed voter, uint256 totalVotes);
    event StoryAdvanced(uint256 indexed storyId, uint256 indexed newNodeId, uint256 winningBranchId);
    event StoryEnded(uint256 indexed storyId, uint256 totalNodes);
    event VotingPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    // ── Constructor ──────────────────────────────────────────
    constructor() {}

    // ── Core Functions ───────────────────────────────────────

    /**
     * @notice Create a new interactive story
     * @param title The story title
     * @param openingHash IPFS hash of the opening content
     * @return storyId The new story ID
     */
    function createStory(string calldata title, bytes32 openingHash)
        external
        whenNotPaused
        returns (uint256 storyId)
    {
        require(bytes(title).length > 0, "StoryEngine: empty title");
        require(openingHash != bytes32(0), "StoryEngine: empty hash");

        storyId = ++storyCounter;
        uint256 rootNodeId = ++nodeCounter;

        // Create root node
        nodes[rootNodeId] = StoryNode({
            storyId: storyId,
            parentNodeId: 0,
            choiceText: "Opening",
            contentHash: openingHash,
            author: msg.sender,
            childBranchIds: new uint256[](0),
            depth: 0,
            createdAt: block.timestamp
        });

        // Create story
        stories[storyId] = Story({
            title: title,
            author: msg.sender,
            openingHash: openingHash,
            currentNodeId: rootNodeId,
            nodeCount: 1,
            totalVoters: 0,
            votingPeriod: defaultVotingPeriod,
            lastAdvancedAt: block.timestamp,
            active: true,
            createdAt: block.timestamp
        });

        emit StoryCreated(storyId, title, msg.sender, openingHash);
    }

    /**
     * @notice Add a branch (choice) to a story node
     * @param storyId The story
     * @param parentNodeId The node to branch from
     * @param choiceText Description of this choice
     * @param contentHash IPFS hash of the branch content
     * @return branchId The new branch ID
     */
    function addBranch(
        uint256 storyId,
        uint256 parentNodeId,
        string calldata choiceText,
        bytes32 contentHash
    ) external whenNotPaused returns (uint256 branchId) {
        Story storage s = stories[storyId];
        require(s.active, "StoryEngine: story inactive");
        require(s.currentNodeId == parentNodeId, "StoryEngine: not current node");
        require(bytes(choiceText).length > 0, "StoryEngine: empty choice");
        require(contentHash != bytes32(0), "StoryEngine: empty hash");

        // Limit branches per node
        require(nodeBranches[storyId][parentNodeId].length < 10, "StoryEngine: too many branches");

        // Create the potential new node
        uint256 newNodeId = ++nodeCounter;
        nodes[newNodeId] = StoryNode({
            storyId: storyId,
            parentNodeId: parentNodeId,
            choiceText: choiceText,
            contentHash: contentHash,
            author: msg.sender,
            childBranchIds: new uint256[](0),
            depth: nodes[parentNodeId].depth + 1,
            createdAt: block.timestamp
        });

        branchId = ++branchCounter;
        branches[branchId] = Branch({
            storyId: storyId,
            parentNodeId: parentNodeId,
            nodeId: newNodeId,
            choiceText: choiceText,
            contentHash: contentHash,
            author: msg.sender,
            votes: 0,
            createdAt: block.timestamp
        });

        nodeBranches[storyId][parentNodeId].push(branchId);
        nodes[parentNodeId].childBranchIds.push(branchId);

        emit BranchAdded(branchId, storyId, parentNodeId, choiceText, msg.sender);
    }

    /**
     * @notice Vote for a branch
     * @param storyId The story
     * @param branchId The branch to vote for
     */
    function vote(uint256 storyId, uint256 branchId) external whenNotPaused {
        Story storage s = stories[storyId];
        require(s.active, "StoryEngine: story inactive");

        Branch storage b = branches[branchId];
        require(b.storyId == storyId, "StoryEngine: branch not in story");
        require(b.parentNodeId == s.currentNodeId, "StoryEngine: branch not for current node");
        require(!hasVoted[branchId][msg.sender], "StoryEngine: already voted");

        hasVoted[branchId][msg.sender] = true;
        b.votes++;

        if (voterContributions[storyId][msg.sender] == 0) {
            s.totalVoters++;
        }
        voterContributions[storyId][msg.sender]++;

        emit Voted(branchId, msg.sender, b.votes);
    }

    /**
     * @notice Advance the story to the winning branch (after voting period)
     * @param storyId The story to advance
     */
    function advanceStory(uint256 storyId) external whenNotPaused {
        Story storage s = stories[storyId];
        require(s.active, "StoryEngine: story inactive");
        require(
            block.timestamp >= s.lastAdvancedAt + s.votingPeriod,
            "StoryEngine: voting period not ended"
        );

        uint256[] storage branchIds = nodeBranches[storyId][s.currentNodeId];
        require(branchIds.length > 0, "StoryEngine: no branches to advance");

        // Find winning branch (most votes)
        uint256 winningBranchId = branchIds[0];
        uint256 maxVotes = branches[branchIds[0]].votes;

        for (uint256 i = 1; i < branchIds.length; i++) {
            if (branches[branchIds[i]].votes > maxVotes) {
                maxVotes = branches[branchIds[i]].votes;
                winningBranchId = branchIds[i];
            }
        }

        uint256 newNodeId = branches[winningBranchId].nodeId;
        s.currentNodeId = newNodeId;
        s.nodeCount++;
        s.lastAdvancedAt = block.timestamp;

        emit StoryAdvanced(storyId, newNodeId, winningBranchId);
    }

    /**
     * @notice End a story (author or owner only)
     * @param storyId The story to end
     */
    function endStory(uint256 storyId) external {
        Story storage s = stories[storyId];
        require(msg.sender == s.author || msg.sender == owner(), "StoryEngine: not authorized");
        require(s.active, "StoryEngine: already ended");

        s.active = false;
        emit StoryEnded(storyId, s.nodeCount);
    }

    // ── Admin ────────────────────────────────────────────────

    function setDefaultVotingPeriod(uint256 _period) external onlyOwner {
        require(_period >= 1 hours, "StoryEngine: period too short");
        emit VotingPeriodUpdated(defaultVotingPeriod, _period);
        defaultVotingPeriod = _period;
    }

    function setStoryVotingPeriod(uint256 storyId, uint256 _period) external {
        Story storage s = stories[storyId];
        require(msg.sender == s.author || msg.sender == owner(), "StoryEngine: not authorized");
        require(_period >= 1 hours, "StoryEngine: period too short");
        s.votingPeriod = _period;
    }

    // ── View Helpers ─────────────────────────────────────────

    function getNodeBranches(uint256 storyId, uint256 nodeId) external view returns (uint256[] memory) {
        return nodeBranches[storyId][nodeId];
    }

    function getChildBranchIds(uint256 nodeId) external view returns (uint256[] memory) {
        return nodes[nodeId].childBranchIds;
    }
}
