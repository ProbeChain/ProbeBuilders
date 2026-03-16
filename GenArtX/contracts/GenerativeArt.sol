// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GenerativeArt
 * @author ProbeChain
 * @notice ERC-721 generative art platform with on-chain seed generation on ProbeChain Rydberg Testnet
 * @dev Collections define scripts; minting generates unique on-chain seeds that determine art output
 */

/// @dev Minimal Ownable implementation
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/// @dev Minimal ReentrancyGuard implementation
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/// @dev Minimal Pausable implementation
abstract contract Pausable is Ownable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    function pause() public onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract GenerativeArt is Ownable, ReentrancyGuard, Pausable {
    // ─── ERC-721 Core ────────────────────────────────────────────────────
    string public name = "GenArtX";
    string public symbol = "GENX";

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ─── Generative Art Types ────────────────────────────────────────────
    struct Collection {
        uint256 id;
        address artist;
        string collectionName;
        bytes32 scriptHash;
        uint256 maxSupply;
        uint256 mintPrice;
        uint256 minted;
        uint256 royaltyBps;
        bool active;
        uint256 createdAt;
    }

    struct ArtPiece {
        uint256 tokenId;
        uint256 collectionId;
        bytes32 seed;
        address minter;
        uint256 mintedAt;
    }

    struct Listing {
        uint256 price;
        bool active;
    }

    // ─── State ───────────────────────────────────────────────────────────
    uint256 public totalSupply;
    uint256 public collectionCount;
    uint256 public platformFeeBps = 250; // 2.5%

    mapping(uint256 => Collection) public collections;
    mapping(uint256 => ArtPiece) public artPieces;
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => uint256[]) public collectionTokens;

    // ─── Art Events ──────────────────────────────────────────────────────
    /// @notice Emitted when a new collection is created
    event CollectionCreated(uint256 indexed collectionId, address indexed artist, string collectionName, uint256 maxSupply, uint256 mintPrice);

    /// @notice Emitted when a new piece is minted with its unique seed
    event ArtMinted(uint256 indexed tokenId, uint256 indexed collectionId, address indexed minter, bytes32 seed);

    /// @notice Emitted when a piece is listed for sale
    event ArtListed(uint256 indexed tokenId, uint256 price);

    /// @notice Emitted when a piece is sold
    event ArtSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);

    /// @notice Emitted when collection royalty is updated
    event CollectionRoyaltySet(uint256 indexed collectionId, uint256 royaltyBps);

    /// @notice Emitted when a collection is toggled active/inactive
    event CollectionToggled(uint256 indexed collectionId, bool active);

    // ─── ERC-721 Implementation ──────────────────────────────────────────
    function balanceOf(address _ownerAddr) public view returns (uint256) {
        require(_ownerAddr != address(0), "Zero address");
        return _balances[_ownerAddr];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        require(tokenOwner != address(0), "Token does not exist");
        return tokenOwner;
    }

    function approve(address to, uint256 tokenId) public {
        address tokenOwner = ownerOf(tokenId);
        require(msg.sender == tokenOwner || _operatorApprovals[tokenOwner][msg.sender], "Not authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "Token does not exist");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address _ownerAddr, address operator) public view returns (bool) {
        return _operatorApprovals[_ownerAddr][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not authorized");
        _transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address tokenOwner = ownerOf(tokenId);
        return (spender == tokenOwner || _tokenApprovals[tokenId] == spender || _operatorApprovals[tokenOwner][spender]);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "Not token owner");
        require(to != address(0), "Transfer to zero");
        _tokenApprovals[tokenId] = address(0);
        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "Mint to zero");
        require(_owners[tokenId] == address(0), "Already minted");
        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

    // ─── Generative Art Functions ────────────────────────────────────────

    /**
     * @notice Create a new generative art collection
     * @param _name Collection name
     * @param _scriptHash Hash of the generative script
     * @param _maxSupply Maximum number of pieces
     * @param _mintPrice Price per mint in wei
     * @return collectionId The ID of the created collection
     */
    function createCollection(
        string calldata _name,
        bytes32 _scriptHash,
        uint256 _maxSupply,
        uint256 _mintPrice
    ) external whenNotPaused returns (uint256 collectionId) {
        require(bytes(_name).length > 0 && bytes(_name).length <= 128, "Invalid name");
        require(_scriptHash != bytes32(0), "Empty script hash");
        require(_maxSupply > 0 && _maxSupply <= 10000, "Invalid max supply");
        require(_mintPrice > 0, "Price must be > 0");

        collectionId = ++collectionCount;
        collections[collectionId] = Collection({
            id: collectionId,
            artist: msg.sender,
            collectionName: _name,
            scriptHash: _scriptHash,
            maxSupply: _maxSupply,
            mintPrice: _mintPrice,
            minted: 0,
            royaltyBps: 500, // default 5%
            active: true,
            createdAt: block.timestamp
        });

        emit CollectionCreated(collectionId, msg.sender, _name, _maxSupply, _mintPrice);
    }

    /**
     * @notice Mint a piece from a collection (generates unique on-chain seed)
     * @param _collectionId The collection ID
     * @return tokenId The minted token ID
     */
    function mint(uint256 _collectionId)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 tokenId)
    {
        Collection storage collection = collections[_collectionId];
        require(collection.active, "Collection not active");
        require(collection.minted < collection.maxSupply, "Max supply reached");
        require(msg.value >= collection.mintPrice, "Insufficient payment");

        collection.minted++;
        tokenId = ++totalSupply;

        // Generate unique seed from on-chain entropy
        bytes32 seed = keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            msg.sender,
            tokenId,
            _collectionId,
            collection.minted
        ));

        _mint(msg.sender, tokenId);

        artPieces[tokenId] = ArtPiece({
            tokenId: tokenId,
            collectionId: _collectionId,
            seed: seed,
            minter: msg.sender,
            mintedAt: block.timestamp
        });

        collectionTokens[_collectionId].push(tokenId);

        // Pay artist
        uint256 platformCut = (msg.value * platformFeeBps) / 10000;
        uint256 artistPayment = msg.value - platformCut;

        (bool sent, ) = collection.artist.call{value: artistPayment}("");
        require(sent, "Artist payment failed");

        emit ArtMinted(tokenId, _collectionId, msg.sender, seed);
    }

    /**
     * @notice Set royalty for a collection (artist only)
     * @param _collectionId The collection ID
     * @param _royaltyBps Royalty in basis points (max 1000 = 10%)
     */
    function setCollectionRoyalty(uint256 _collectionId, uint256 _royaltyBps) external {
        require(collections[_collectionId].artist == msg.sender, "Not artist");
        require(_royaltyBps <= 1000, "Royalty too high");

        collections[_collectionId].royaltyBps = _royaltyBps;
        emit CollectionRoyaltySet(_collectionId, _royaltyBps);
    }

    /**
     * @notice List an art piece for sale
     * @param _tokenId The token ID
     * @param _price Sale price in wei
     */
    function listForSale(uint256 _tokenId, uint256 _price) external whenNotPaused {
        require(ownerOf(_tokenId) == msg.sender, "Not token owner");
        require(_price > 0, "Price must be > 0");
        listings[_tokenId] = Listing({ price: _price, active: true });
        emit ArtListed(_tokenId, _price);
    }

    /**
     * @notice Buy a listed art piece (with royalty to artist)
     * @param _tokenId The token ID
     */
    function buyArt(uint256 _tokenId)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        Listing storage listing = listings[_tokenId];
        require(listing.active, "Not listed");
        require(msg.value >= listing.price, "Insufficient payment");

        address seller = ownerOf(_tokenId);
        require(msg.sender != seller, "Cannot buy own piece");

        listing.active = false;

        ArtPiece storage piece = artPieces[_tokenId];
        Collection storage collection = collections[piece.collectionId];

        uint256 royaltyAmount = (msg.value * collection.royaltyBps) / 10000;
        uint256 sellerPayment = msg.value - royaltyAmount;

        _transfer(seller, msg.sender, _tokenId);

        (bool sentSeller, ) = seller.call{value: sellerPayment}("");
        require(sentSeller, "Seller payment failed");

        if (royaltyAmount > 0) {
            (bool sentRoyalty, ) = collection.artist.call{value: royaltyAmount}("");
            require(sentRoyalty, "Royalty payment failed");
        }

        emit ArtSold(_tokenId, seller, msg.sender, msg.value);
    }

    /**
     * @notice Toggle collection active status
     * @param _collectionId The collection ID
     */
    function toggleCollection(uint256 _collectionId) external {
        require(collections[_collectionId].artist == msg.sender, "Not artist");
        collections[_collectionId].active = !collections[_collectionId].active;
        emit CollectionToggled(_collectionId, collections[_collectionId].active);
    }

    /**
     * @notice Get tokens in a collection
     * @param _collectionId The collection ID
     */
    function getCollectionTokens(uint256 _collectionId) external view returns (uint256[] memory) {
        return collectionTokens[_collectionId];
    }

    /**
     * @notice Update platform fee
     * @param _newFeeBps New fee in basis points
     */
    function setPlatformFee(uint256 _newFeeBps) external onlyOwner {
        require(_newFeeBps <= 1000, "Fee too high");
        platformFeeBps = _newFeeBps;
    }

    /**
     * @notice Withdraw platform fees
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");
        (bool sent, ) = owner().call{value: balance}("");
        require(sent, "Withdraw failed");
    }
}
