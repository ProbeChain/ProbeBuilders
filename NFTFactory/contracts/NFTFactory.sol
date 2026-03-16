// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NFTFactory
 * @author ProbeChain
 * @notice NFT collection factory with ERC-721 deployment, minting, and royalties
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract Pausable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function _pause() internal whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function _unpause() internal whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

/// @notice Minimal ERC-721 collection deployed by the factory
contract FactoryNFT {
    string public name;
    string public symbol;
    uint256 public maxSupply;
    uint256 public mintPrice;
    uint256 public royaltyBPS;
    address public creator;
    uint256 public totalMinted;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(uint256 => string) private _tokenURIs;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event Minted(address indexed to, uint256 indexed tokenId);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        uint256 _mintPrice,
        uint256 _royaltyBPS,
        address _creator
    ) {
        name = _name;
        symbol = _symbol;
        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
        royaltyBPS = _royaltyBPS;
        creator = _creator;
        totalMinted = 0;
    }

    function mint(address to, string calldata uri) external payable returns (uint256) {
        require(totalMinted < maxSupply, "NFT: max supply reached");
        require(msg.value >= mintPrice, "NFT: insufficient payment");

        totalMinted++;
        uint256 tokenId = totalMinted;

        _owners[tokenId] = to;
        _balances[to]++;
        _tokenURIs[tokenId] = uri;

        // Send mint payment to creator
        if (msg.value > 0) {
            (bool sent, ) = creator.call{value: msg.value}("");
            require(sent, "NFT: payment failed");
        }

        emit Transfer(address(0), to, tokenId);
        emit Minted(to, tokenId);
        return tokenId;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address tokenOwner = _owners[tokenId];
        require(tokenOwner != address(0), "NFT: nonexistent token");
        return tokenOwner;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_owners[tokenId] != address(0), "NFT: nonexistent token");
        return _tokenURIs[tokenId];
    }

    function approve(address to, uint256 tokenId) external {
        require(_owners[tokenId] == msg.sender, "NFT: not owner");
        _tokenApprovals[tokenId] = to;
        emit Approval(msg.sender, to, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_owners[tokenId] == from, "NFT: not owner");
        require(
            msg.sender == from || _tokenApprovals[tokenId] == msg.sender,
            "NFT: not approved"
        );
        require(to != address(0), "NFT: zero address");

        _tokenApprovals[tokenId] = address(0);
        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    /// @notice EIP-2981 royalty info
    function royaltyInfo(uint256 /*tokenId*/, uint256 salePrice)
        external view returns (address receiver, uint256 royaltyAmount)
    {
        return (creator, (salePrice * royaltyBPS) / 10000);
    }
}

contract NFTFactory is Ownable, Pausable {
    /// @notice Collection info
    struct CollectionInfo {
        address collectionAddress;
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 mintPrice;
        uint256 royaltyBPS;
        address creator;
        uint256 createdAt;
    }

    /// @dev Creation fee
    uint256 public creationFee;

    /// @dev All collections
    CollectionInfo[] private _allCollections;

    /// @dev Creator => collection addresses
    mapping(address => address[]) private _creatorCollections;

    /// @dev Collection address => index + 1
    mapping(address => uint256) private _collectionIndex;

    // ───────── Events ─────────

    /// @notice Emitted when a new NFT collection is created
    event CollectionCreated(address indexed collectionAddress, address indexed creator, string name, string symbol);

    /// @notice Emitted when an NFT is minted from a collection via factory
    event MintedFromCollection(address indexed collection, address indexed minter, uint256 tokenId);

    /// @notice Emitted when creation fee changes
    event CreationFeeUpdated(uint256 newFee);

    // ───────── Constructor ─────────

    constructor() {
        creationFee = 0;
    }

    // ───────── Admin ─────────

    function setCreationFee(uint256 fee) external onlyOwner {
        creationFee = fee;
        emit CreationFeeUpdated(fee);
    }

    function withdrawFees(address payable to) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "NFTFactory: no fees");
        (bool sent, ) = to.call{value: balance}("");
        require(sent, "NFTFactory: transfer failed");
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Create a new NFT collection
    /// @param _name Collection name
    /// @param _symbol Collection symbol
    /// @param _maxSupply Maximum number of tokens
    /// @param _mintPrice Price per mint in wei
    /// @param _royaltyBPS Royalty basis points (e.g., 250 = 2.5%)
    /// @return collectionAddress The deployed collection address
    function createCollection(
        string calldata _name,
        string calldata _symbol,
        uint256 _maxSupply,
        uint256 _mintPrice,
        uint256 _royaltyBPS
    ) external payable whenNotPaused returns (address collectionAddress) {
        require(bytes(_name).length > 0, "NFTFactory: empty name");
        require(bytes(_symbol).length > 0, "NFTFactory: empty symbol");
        require(_maxSupply > 0, "NFTFactory: zero supply");
        require(_royaltyBPS <= 1000, "NFTFactory: royalty too high");
        require(msg.value >= creationFee, "NFTFactory: insufficient fee");

        FactoryNFT nft = new FactoryNFT(
            _name, _symbol, _maxSupply, _mintPrice, _royaltyBPS, msg.sender
        );

        collectionAddress = address(nft);

        _allCollections.push(CollectionInfo({
            collectionAddress: collectionAddress,
            name: _name,
            symbol: _symbol,
            maxSupply: _maxSupply,
            mintPrice: _mintPrice,
            royaltyBPS: _royaltyBPS,
            creator: msg.sender,
            createdAt: block.timestamp
        }));

        _collectionIndex[collectionAddress] = _allCollections.length;
        _creatorCollections[msg.sender].push(collectionAddress);

        emit CollectionCreated(collectionAddress, msg.sender, _name, _symbol);
    }

    /// @notice Mint from a collection via factory
    /// @param collectionAddr The collection address
    /// @param uri The token metadata URI
    function mintFromCollection(address collectionAddr, string calldata uri) external payable whenNotPaused {
        require(_collectionIndex[collectionAddr] > 0, "NFTFactory: unknown collection");

        FactoryNFT nft = FactoryNFT(collectionAddr);
        uint256 tokenId = nft.mint{value: msg.value}(msg.sender, uri);

        emit MintedFromCollection(collectionAddr, msg.sender, tokenId);
    }

    // ───────── View Functions ─────────

    /// @notice Get collections by creator
    function getCollections(address creator) external view returns (address[] memory) {
        return _creatorCollections[creator];
    }

    /// @notice Get collection info
    function getCollectionInfo(address collectionAddr) external view returns (CollectionInfo memory) {
        uint256 idx = _collectionIndex[collectionAddr];
        require(idx > 0, "NFTFactory: not found");
        return _allCollections[idx - 1];
    }

    /// @notice Total collections created
    function totalCollections() external view returns (uint256) {
        return _allCollections.length;
    }
}
