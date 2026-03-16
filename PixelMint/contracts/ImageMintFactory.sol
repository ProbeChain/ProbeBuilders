// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ImageMintFactory
 * @author ProbeChain
 * @notice ERC-721 AI image minting with provenance tracking on ProbeChain Rydberg Testnet
 * @dev Tracks prompt-to-model-to-image provenance chain, supports sales and royalties
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

contract ImageMintFactory is Ownable, ReentrancyGuard, Pausable {
    // ─── ERC-721 Core ────────────────────────────────────────────────────
    string public name = "PixelMint AI Images";
    string public symbol = "PIXEL";

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ─── Image Types ─────────────────────────────────────────────────────
    struct ImageProvenance {
        bytes32 promptHash;
        bytes32 imageHash;
        string modelUsed;
        address creator;
        uint256 mintedAt;
    }

    struct Listing {
        uint256 price;
        bool active;
    }

    struct RoyaltyInfo {
        address receiver;
        uint256 bps; // basis points
    }

    // ─── State ───────────────────────────────────────────────────────────
    uint256 public totalSupply;
    uint256 public mintFee = 0.001 ether;

    mapping(uint256 => ImageProvenance) public provenance;
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => RoyaltyInfo) public royalties;
    mapping(bytes32 => bool) public imageHashExists;

    // ─── Image Events ────────────────────────────────────────────────────
    /// @notice Emitted when a new AI image is minted
    event ImageMinted(uint256 indexed tokenId, address indexed creator, bytes32 promptHash, bytes32 imageHash, string modelUsed);

    /// @notice Emitted when an image is listed for sale
    event ImageListed(uint256 indexed tokenId, uint256 price);

    /// @notice Emitted when an image is sold
    event ImageSold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);

    /// @notice Emitted when royalty is set
    event RoyaltySet(uint256 indexed tokenId, uint256 bps);

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

    // ─── Image Functions ─────────────────────────────────────────────────

    /**
     * @notice Mint a new AI-generated image NFT
     * @param _promptHash Hash of the prompt used to generate the image
     * @param _imageHash Hash of the generated image
     * @param _modelUsed AI model used for generation
     * @return tokenId The ID of the minted NFT
     */
    function mintImage(bytes32 _promptHash, bytes32 _imageHash, string calldata _modelUsed)
        external
        payable
        whenNotPaused
        returns (uint256 tokenId)
    {
        require(_promptHash != bytes32(0), "Empty prompt hash");
        require(_imageHash != bytes32(0), "Empty image hash");
        require(!imageHashExists[_imageHash], "Image already minted");
        require(bytes(_modelUsed).length > 0, "Empty model name");
        require(msg.value >= mintFee, "Insufficient mint fee");

        imageHashExists[_imageHash] = true;
        tokenId = ++totalSupply;

        _mint(msg.sender, tokenId);

        provenance[tokenId] = ImageProvenance({
            promptHash: _promptHash,
            imageHash: _imageHash,
            modelUsed: _modelUsed,
            creator: msg.sender,
            mintedAt: block.timestamp
        });

        // Default royalty to creator at 5%
        royalties[tokenId] = RoyaltyInfo({
            receiver: msg.sender,
            bps: 500
        });

        emit ImageMinted(tokenId, msg.sender, _promptHash, _imageHash, _modelUsed);
    }

    /**
     * @notice List an image NFT for sale
     * @param _tokenId The token ID
     * @param _price Sale price in wei
     */
    function listForSale(uint256 _tokenId, uint256 _price) external whenNotPaused {
        require(ownerOf(_tokenId) == msg.sender, "Not token owner");
        require(_price > 0, "Price must be > 0");

        listings[_tokenId] = Listing({ price: _price, active: true });
        emit ImageListed(_tokenId, _price);
    }

    /**
     * @notice Buy a listed image NFT
     * @param _tokenId The token ID
     */
    function buyImage(uint256 _tokenId)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        Listing storage listing = listings[_tokenId];
        require(listing.active, "Not listed");
        require(msg.value >= listing.price, "Insufficient payment");

        address seller = ownerOf(_tokenId);
        require(msg.sender != seller, "Cannot buy own token");

        listing.active = false;

        // Calculate royalty
        RoyaltyInfo storage royalty = royalties[_tokenId];
        uint256 royaltyAmount = (msg.value * royalty.bps) / 10000;
        uint256 sellerPayment = msg.value - royaltyAmount;

        _transfer(seller, msg.sender, _tokenId);

        // Pay seller
        (bool sentSeller, ) = seller.call{value: sellerPayment}("");
        require(sentSeller, "Seller payment failed");

        // Pay royalty
        if (royaltyAmount > 0 && royalty.receiver != seller) {
            (bool sentRoyalty, ) = royalty.receiver.call{value: royaltyAmount}("");
            require(sentRoyalty, "Royalty payment failed");
        }

        emit ImageSold(_tokenId, seller, msg.sender, msg.value);
    }

    /**
     * @notice Set royalty for a token (creator only)
     * @param _tokenId The token ID
     * @param _bps Royalty in basis points (max 1000 = 10%)
     */
    function setRoyalty(uint256 _tokenId, uint256 _bps) external {
        require(provenance[_tokenId].creator == msg.sender, "Not creator");
        require(_bps <= 1000, "Royalty too high (max 10%)");

        royalties[_tokenId].bps = _bps;
        emit RoyaltySet(_tokenId, _bps);
    }

    /**
     * @notice Update mint fee
     * @param _newFee New mint fee in wei
     */
    function setMintFee(uint256 _newFee) external onlyOwner {
        mintFee = _newFee;
    }

    /**
     * @notice Withdraw contract balance
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");
        (bool sent, ) = owner().call{value: balance}("");
        require(sent, "Withdraw failed");
    }

    /**
     * @notice Get image provenance
     * @param _tokenId The token ID
     */
    function getProvenance(uint256 _tokenId) external view returns (ImageProvenance memory) {
        return provenance[_tokenId];
    }
}
