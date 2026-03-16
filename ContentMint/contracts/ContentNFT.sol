// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title ContentNFT
 * @author ProbeBuilders
 * @notice Content creation and NFT minting with royalties and limited editions
 * @dev ERC-721 compatible content NFT with versioning and edition support
 */

// ============ Minimal Ownable ============
abstract contract Ownable {
    address private _owner;
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert OwnableInvalidOwner(address(0));
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender);
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ============ Minimal ReentrancyGuard ============
abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardReentrantCall();
        _status = 2;
        _;
        _status = 1;
    }
}

// ============ Minimal Pausable ============
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    error ExpectedPause();

    modifier whenNotPaused() {
        if (_paused) revert EnforcedPause();
        _;
    }

    function paused() public view returns (bool) { return _paused; }

    function pause() external onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

// ============ Minimal ERC-721 ============
abstract contract ERC721 {
    string public name;
    string public symbol;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function balanceOf(address owner_) public view returns (uint256) { return _balances[owner_]; }
    function ownerOf(uint256 tokenId) public view returns (address) { return _owners[tokenId]; }

    function approve(address to, uint256 tokenId) external {
        address tokenOwner = _owners[tokenId];
        require(msg.sender == tokenOwner || _operatorApprovals[tokenOwner][msg.sender], "Not authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_owners[tokenId] == from, "Not owner");
        require(
            msg.sender == from ||
            _tokenApprovals[tokenId] == msg.sender ||
            _operatorApprovals[from][msg.sender],
            "Not authorized"
        );
        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;
        delete _tokenApprovals[tokenId];
        emit Transfer(from, to, tokenId);
    }

    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "Mint to zero");
        require(_owners[tokenId] == address(0), "Already minted");
        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }
}

/// @title ContentNFT — Content creation and NFT minting platform
contract ContentNFT is ERC721, Ownable, ReentrancyGuard, Pausable {

    /// @notice Content metadata structure
    struct Content {
        address creator;
        bytes32 contentHash;
        string metadataURI;
        uint16 royaltyBPS;       // basis points (100 = 1%)
        uint32 maxEditions;
        uint32 mintedEditions;
        uint64 createdAt;
        uint8 version;
    }

    uint256 public nextContentId = 1;
    uint256 public nextTokenId = 1;
    uint16 public constant MAX_ROYALTY_BPS = 2500; // 25% max
    uint32 public constant DEFAULT_MAX_EDITIONS = 100;

    /// @notice contentId => Content
    mapping(uint256 => Content) public contents;
    /// @notice tokenId => contentId
    mapping(uint256 => uint256) public tokenContentId;
    /// @notice tokenId => edition number
    mapping(uint256 => uint32) public tokenEdition;
    /// @notice tokenId => tokenURI
    mapping(uint256 => string) private _tokenURIs;

    event ContentCreated(uint256 indexed contentId, address indexed creator, bytes32 contentHash, uint16 royaltyBPS);
    event ContentVersionUpdated(uint256 indexed contentId, uint8 newVersion, bytes32 newHash, string newURI);
    event EditionMinted(uint256 indexed contentId, uint256 indexed tokenId, address indexed recipient, uint32 editionNumber);
    event RoyaltyUpdated(uint256 indexed contentId, uint16 newRoyaltyBPS);
    event MaxEditionsUpdated(uint256 indexed contentId, uint32 newMax);

    error NotContentCreator();
    error InvalidRoyalty();
    error EditionsExhausted();
    error ContentNotFound();

    constructor() ERC721("ContentNFT", "CNFT") Ownable(msg.sender) {}

    /// @notice Create new content entry
    /// @param contentHash Hash of the content for integrity verification
    /// @param metadataURI Off-chain metadata URI (IPFS etc.)
    /// @param royaltyBPS Royalty in basis points (max 2500 = 25%)
    /// @return contentId The ID of the created content
    function createContent(
        bytes32 contentHash,
        string calldata metadataURI,
        uint16 royaltyBPS
    ) external whenNotPaused returns (uint256 contentId) {
        if (royaltyBPS > MAX_ROYALTY_BPS) revert InvalidRoyalty();

        contentId = nextContentId++;
        contents[contentId] = Content({
            creator: msg.sender,
            contentHash: contentHash,
            metadataURI: metadataURI,
            royaltyBPS: royaltyBPS,
            maxEditions: DEFAULT_MAX_EDITIONS,
            mintedEditions: 0,
            createdAt: uint64(block.timestamp),
            version: 1
        });

        emit ContentCreated(contentId, msg.sender, contentHash, royaltyBPS);
    }

    /// @notice Create content with a custom edition limit
    function createContentWithEditions(
        bytes32 contentHash,
        string calldata metadataURI,
        uint16 royaltyBPS,
        uint32 maxEditions
    ) external whenNotPaused returns (uint256 contentId) {
        if (royaltyBPS > MAX_ROYALTY_BPS) revert InvalidRoyalty();
        require(maxEditions > 0, "Max editions must be > 0");

        contentId = nextContentId++;
        contents[contentId] = Content({
            creator: msg.sender,
            contentHash: contentHash,
            metadataURI: metadataURI,
            royaltyBPS: royaltyBPS,
            maxEditions: maxEditions,
            mintedEditions: 0,
            createdAt: uint64(block.timestamp),
            version: 1
        });

        emit ContentCreated(contentId, msg.sender, contentHash, royaltyBPS);
    }

    /// @notice Mint a new edition of existing content
    /// @param contentId The content to mint an edition of
    /// @param recipient Address to receive the NFT
    /// @return tokenId The minted token ID
    function mintEdition(uint256 contentId, address recipient)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 tokenId)
    {
        Content storage c = contents[contentId];
        if (c.creator == address(0)) revert ContentNotFound();
        if (c.mintedEditions >= c.maxEditions) revert EditionsExhausted();

        c.mintedEditions++;
        tokenId = nextTokenId++;
        tokenContentId[tokenId] = contentId;
        tokenEdition[tokenId] = c.mintedEditions;
        _tokenURIs[tokenId] = c.metadataURI;

        _mint(recipient, tokenId);
        emit EditionMinted(contentId, tokenId, recipient, c.mintedEditions);
    }

    /// @notice Update content version (creator only)
    function updateContent(
        uint256 contentId,
        bytes32 newHash,
        string calldata newURI
    ) external whenNotPaused {
        Content storage c = contents[contentId];
        if (c.creator != msg.sender) revert NotContentCreator();

        c.version++;
        c.contentHash = newHash;
        c.metadataURI = newURI;

        emit ContentVersionUpdated(contentId, c.version, newHash, newURI);
    }

    /// @notice Update royalty for content (creator only)
    /// @param contentId Content ID
    /// @param newRoyaltyBPS New royalty in basis points
    function setRoyalty(uint256 contentId, uint16 newRoyaltyBPS) external {
        Content storage c = contents[contentId];
        if (c.creator != msg.sender) revert NotContentCreator();
        if (newRoyaltyBPS > MAX_ROYALTY_BPS) revert InvalidRoyalty();

        c.royaltyBPS = newRoyaltyBPS;
        emit RoyaltyUpdated(contentId, newRoyaltyBPS);
    }

    /// @notice Update max editions (creator only, cannot reduce below minted)
    function setMaxEditions(uint256 contentId, uint32 newMax) external {
        Content storage c = contents[contentId];
        if (c.creator != msg.sender) revert NotContentCreator();
        require(newMax >= c.mintedEditions, "Below already minted");

        c.maxEditions = newMax;
        emit MaxEditionsUpdated(contentId, newMax);
    }

    /// @notice EIP-2981 royalty info
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        uint256 cId = tokenContentId[tokenId];
        Content storage c = contents[cId];
        return (c.creator, (salePrice * c.royaltyBPS) / 10000);
    }

    /// @notice Get token URI
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        return _tokenURIs[tokenId];
    }

    /// @notice Get remaining editions for content
    function remainingEditions(uint256 contentId) external view returns (uint32) {
        Content storage c = contents[contentId];
        return c.maxEditions - c.mintedEditions;
    }
}
