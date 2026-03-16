// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ThreeDMarket
 * @author ProbeChain
 * @notice ERC-721 3D model marketplace with licensing on ProbeChain Rydberg Testnet
 * @dev Manages 3D model minting, listing, purchasing, and usage licensing (glTF, FBX, OBJ formats)
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

contract ThreeDMarket is Ownable, ReentrancyGuard, Pausable {
    // ─── ERC-721 Core ────────────────────────────────────────────────────
    string public name = "ThreeDForge Models";
    string public symbol = "3DF";

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ─── 3D Model Types ──────────────────────────────────────────────────
    enum FormatType { glTF, FBX, OBJ }
    enum LicenseTerms { Personal, Commercial, Extended, Exclusive }

    struct Model3D {
        bytes32 modelHash;
        FormatType formatType;
        uint256 polyCount;
        string metadataURI;
        address creator;
        uint256 mintedAt;
    }

    struct Listing {
        uint256 price;
        bool active;
    }

    struct UseLicense {
        uint256 id;
        uint256 tokenId;
        address licensee;
        LicenseTerms terms;
        uint256 fee;
        uint256 grantedAt;
        uint256 expiresAt;
        bool active;
    }

    // ─── State ───────────────────────────────────────────────────────────
    uint256 public totalSupply;
    uint256 public licenseCount;
    uint256 public mintFee = 0.001 ether;
    uint256 public platformFeeBps = 300; // 3%

    mapping(uint256 => Model3D) public models;
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => UseLicense) public useLicenses;
    mapping(bytes32 => bool) public modelHashExists;

    // ─── 3D Events ───────────────────────────────────────────────────────
    /// @notice Emitted when a 3D model is minted
    event Model3DMinted(uint256 indexed tokenId, address indexed creator, bytes32 modelHash, FormatType formatType, uint256 polyCount);

    /// @notice Emitted when a model is listed for sale
    event ModelListedForSale(uint256 indexed tokenId, uint256 price);

    /// @notice Emitted when a model is purchased
    event ModelPurchased(uint256 indexed tokenId, address indexed buyer, uint256 price);

    /// @notice Emitted when a usage license is granted
    event LicenseGranted(uint256 indexed licenseId, uint256 indexed tokenId, address indexed licensee, LicenseTerms terms);

    /// @notice Emitted when a listing is cancelled
    event ListingCancelled(uint256 indexed tokenId);

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

    // ─── 3D Model Functions ──────────────────────────────────────────────

    /**
     * @notice Mint a new 3D model NFT
     * @param _modelHash Hash of the 3D model file
     * @param _formatType File format (glTF, FBX, OBJ)
     * @param _polyCount Polygon count of the model
     * @param _metadataURI URI to model metadata
     * @return tokenId The minted token ID
     */
    function mint3DModel(
        bytes32 _modelHash,
        FormatType _formatType,
        uint256 _polyCount,
        string calldata _metadataURI
    ) external payable whenNotPaused returns (uint256 tokenId) {
        require(_modelHash != bytes32(0), "Empty model hash");
        require(!modelHashExists[_modelHash], "Model already minted");
        require(_polyCount > 0, "Invalid poly count");
        require(bytes(_metadataURI).length > 0, "Empty metadata URI");
        require(msg.value >= mintFee, "Insufficient mint fee");

        modelHashExists[_modelHash] = true;
        tokenId = ++totalSupply;

        _mint(msg.sender, tokenId);

        models[tokenId] = Model3D({
            modelHash: _modelHash,
            formatType: _formatType,
            polyCount: _polyCount,
            metadataURI: _metadataURI,
            creator: msg.sender,
            mintedAt: block.timestamp
        });

        emit Model3DMinted(tokenId, msg.sender, _modelHash, _formatType, _polyCount);
    }

    /**
     * @notice List a 3D model for sale
     * @param _tokenId The token ID
     * @param _price Sale price in wei
     */
    function listModel(uint256 _tokenId, uint256 _price) external whenNotPaused {
        require(ownerOf(_tokenId) == msg.sender, "Not token owner");
        require(_price > 0, "Price must be > 0");

        listings[_tokenId] = Listing({ price: _price, active: true });
        emit ModelListedForSale(_tokenId, _price);
    }

    /**
     * @notice Purchase a listed 3D model
     * @param _tokenId The token ID
     */
    function purchaseModel(uint256 _tokenId)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        Listing storage listing = listings[_tokenId];
        require(listing.active, "Not listed");
        require(msg.value >= listing.price, "Insufficient payment");

        address seller = ownerOf(_tokenId);
        require(msg.sender != seller, "Cannot buy own model");

        listing.active = false;

        uint256 platformCut = (msg.value * platformFeeBps) / 10000;
        uint256 sellerPayment = msg.value - platformCut;

        _transfer(seller, msg.sender, _tokenId);

        (bool sent, ) = seller.call{value: sellerPayment}("");
        require(sent, "Payment failed");

        emit ModelPurchased(_tokenId, msg.sender, msg.value);
    }

    /**
     * @notice Grant a usage license for a 3D model
     * @param _tokenId The token ID
     * @param _licensee The licensee address
     * @param _terms License terms
     * @return licenseId The ID of the granted license
     */
    function licenseForUse(uint256 _tokenId, address _licensee, LicenseTerms _terms)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 licenseId)
    {
        require(ownerOf(_tokenId) == msg.sender || msg.sender == _licensee, "Not authorized");
        require(_licensee != address(0), "Invalid licensee");

        address tokenOwner = ownerOf(_tokenId);

        if (msg.sender == _licensee && msg.value > 0) {
            (bool sent, ) = tokenOwner.call{value: msg.value}("");
            require(sent, "License fee transfer failed");
        }

        uint256 duration = _terms == LicenseTerms.Exclusive ? 365 days * 5 : 365 days;

        licenseId = ++licenseCount;
        useLicenses[licenseId] = UseLicense({
            id: licenseId,
            tokenId: _tokenId,
            licensee: _licensee,
            terms: _terms,
            fee: msg.value,
            grantedAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            active: true
        });

        emit LicenseGranted(licenseId, _tokenId, _licensee, _terms);
    }

    /**
     * @notice Cancel a listing
     * @param _tokenId The token ID
     */
    function cancelListing(uint256 _tokenId) external {
        require(ownerOf(_tokenId) == msg.sender, "Not token owner");
        listings[_tokenId].active = false;
        emit ListingCancelled(_tokenId);
    }

    /**
     * @notice Update mint fee
     * @param _newFee New fee in wei
     */
    function setMintFee(uint256 _newFee) external onlyOwner {
        mintFee = _newFee;
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
     * @notice Withdraw accumulated fees
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");
        (bool sent, ) = owner().call{value: balance}("");
        require(sent, "Withdraw failed");
    }

    /**
     * @notice Get 3D model info
     * @param _tokenId The token ID
     */
    function getModel(uint256 _tokenId) external view returns (Model3D memory) {
        return models[_tokenId];
    }
}
