// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PlaygroundRegistry
 * @author ProbeChain Team
 * @notice On-chain code snippet sharing and discovery platform
 * @dev Supports saving, forking, and liking code snippets with popularity tracking
 */
contract PlaygroundRegistry {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "PlaygroundRegistry: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "PlaygroundRegistry: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "PlaygroundRegistry: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Structs ────────────────────────────────────────────────────────
    struct Snippet {
        uint256 id;
        address author;
        string title;
        bytes32 codeHash;
        string language;
        bool isPublic;
        uint256 likes;
        uint256 forkCount;
        uint256 forkedFrom;
        uint256 createdAt;
        bool active;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public snippetCount;
    mapping(uint256 => Snippet) public snippets;
    mapping(uint256 => mapping(address => bool)) public hasLiked;
    mapping(address => uint256[]) public userSnippets;
    mapping(string => uint256[]) public languageSnippets;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a new snippet is saved
    event SnippetSaved(uint256 indexed snippetId, address indexed author, string title, string language);
    /// @notice Emitted when a snippet is forked
    event SnippetForked(uint256 indexed newSnippetId, uint256 indexed originalId, address indexed forker);
    /// @notice Emitted when a snippet receives a like
    event SnippetLiked(uint256 indexed snippetId, address indexed liker, uint256 totalLikes);
    /// @notice Emitted when a snippet is deleted
    event SnippetDeleted(uint256 indexed snippetId);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Save a new code snippet to the registry
     * @param title Human-readable title
     * @param codeHash IPFS or SHA-256 hash of the code content
     * @param language Programming language (e.g., "Solidity", "TypeScript")
     * @param isPublic Whether the snippet is publicly discoverable
     * @return snippetId The ID of the created snippet
     */
    function saveSnippet(
        string calldata title,
        bytes32 codeHash,
        string calldata language,
        bool isPublic
    ) external whenNotPaused returns (uint256 snippetId) {
        require(bytes(title).length > 0 && bytes(title).length <= 128, "PlaygroundRegistry: invalid title");
        require(codeHash != bytes32(0), "PlaygroundRegistry: empty hash");
        require(bytes(language).length > 0, "PlaygroundRegistry: empty language");

        snippetCount++;
        snippetId = snippetCount;

        snippets[snippetId] = Snippet({
            id: snippetId,
            author: msg.sender,
            title: title,
            codeHash: codeHash,
            language: language,
            isPublic: isPublic,
            likes: 0,
            forkCount: 0,
            forkedFrom: 0,
            createdAt: block.timestamp,
            active: true
        });

        userSnippets[msg.sender].push(snippetId);
        if (isPublic) {
            languageSnippets[language].push(snippetId);
        }

        emit SnippetSaved(snippetId, msg.sender, title, language);
    }

    /**
     * @notice Fork an existing snippet to create a derivative
     * @param snippetId ID of the snippet to fork
     * @param newTitle Title for the forked snippet
     * @param newCodeHash Hash of the modified code
     * @return newSnippetId The ID of the new forked snippet
     */
    function forkSnippet(
        uint256 snippetId,
        string calldata newTitle,
        bytes32 newCodeHash
    ) external whenNotPaused returns (uint256 newSnippetId) {
        Snippet storage original = snippets[snippetId];
        require(original.active, "PlaygroundRegistry: snippet not active");
        require(original.isPublic, "PlaygroundRegistry: snippet not public");
        require(bytes(newTitle).length > 0, "PlaygroundRegistry: empty title");

        snippetCount++;
        newSnippetId = snippetCount;

        snippets[newSnippetId] = Snippet({
            id: newSnippetId,
            author: msg.sender,
            title: newTitle,
            codeHash: newCodeHash,
            language: original.language,
            isPublic: true,
            likes: 0,
            forkCount: 0,
            forkedFrom: snippetId,
            createdAt: block.timestamp,
            active: true
        });

        original.forkCount++;
        userSnippets[msg.sender].push(newSnippetId);
        languageSnippets[original.language].push(newSnippetId);

        emit SnippetForked(newSnippetId, snippetId, msg.sender);
    }

    /**
     * @notice Like a public snippet
     * @param snippetId ID of the snippet to like
     */
    function likeSnippet(uint256 snippetId) external whenNotPaused {
        Snippet storage s = snippets[snippetId];
        require(s.active, "PlaygroundRegistry: snippet not active");
        require(s.isPublic, "PlaygroundRegistry: snippet not public");
        require(!hasLiked[snippetId][msg.sender], "PlaygroundRegistry: already liked");

        hasLiked[snippetId][msg.sender] = true;
        s.likes++;

        emit SnippetLiked(snippetId, msg.sender, s.likes);
    }

    /**
     * @notice Get popular snippets for a language (returns up to 10 IDs)
     * @param language Programming language to filter by
     * @return ids Array of snippet IDs sorted by popularity (most recent first)
     */
    function getPopularSnippets(string calldata language) external view returns (uint256[] memory ids) {
        uint256[] storage allIds = languageSnippets[language];
        uint256 len = allIds.length > 10 ? 10 : allIds.length;
        ids = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            ids[i] = allIds[allIds.length - 1 - i];
        }
    }

    /**
     * @notice Delete a snippet (author only)
     * @param snippetId ID of the snippet to delete
     */
    function deleteSnippet(uint256 snippetId) external {
        Snippet storage s = snippets[snippetId];
        require(s.author == msg.sender || msg.sender == _owner, "PlaygroundRegistry: unauthorized");
        s.active = false;
        emit SnippetDeleted(snippetId);
    }

    /**
     * @notice Get snippet count for a user
     * @param user Address of the user
     * @return count Number of snippets
     */
    function getUserSnippetCount(address user) external view returns (uint256 count) {
        return userSnippets[user].length;
    }
}
