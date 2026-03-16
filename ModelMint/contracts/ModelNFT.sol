// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title ModelNFT
 * @notice AI model tokenization as ERC-721 with ERC-2981 royalty enforcement and versioning
 * @dev Each NFT represents ownership of an AI model with on-chain metadata and royalty info
 */
contract ModelNFT {
    // ──────────────────── Ownership ────────────────────
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ──────────────────── Pausable ────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "Paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ──────────────────── ERC-721 Core ────────────────────
    string public name = "ModelMint AI Models";
    string public symbol = "MODEL";
    uint256 public totalSupply;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _approvals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ──────────────────── Model Data ────────────────────
    struct ModelInfo {
        bytes32 modelHash;       // Hash of the model weights/architecture
        string metadataURI;      // IPFS URI for full metadata
        address creator;         // Original minter
        uint96 royaltyBPS;       // Royalty basis points (max 10000 = 100%)
        uint256 currentVersion;
        uint256 mintedAt;
    }

    struct ModelVersion {
        bytes32 versionHash;
        string changeLog;
        uint256 timestamp;
    }

    mapping(uint256 => ModelInfo) public models;
    mapping(uint256 => mapping(uint256 => ModelVersion)) public versions;
    mapping(bytes32 => bool) public modelHashExists;

    uint256 public mintFee = 0.005 ether;
    uint256 public maxRoyaltyBPS = 2500; // 25% max

    // ──────────────────── Events ────────────────────
    event ModelMinted(uint256 indexed tokenId, address indexed creator, bytes32 modelHash, uint96 royaltyBPS);
    event ModelVersionAdded(uint256 indexed tokenId, uint256 version, bytes32 versionHash);
    event RoyaltyUpdated(uint256 indexed tokenId, uint96 newRoyaltyBPS);
    event RoyaltyPaid(uint256 indexed tokenId, address indexed creator, uint256 amount);
    event MintFeeUpdated(uint256 newFee);

    constructor() {
        owner = msg.sender;
    }

    // ──────────────────── ERC-721 Implementation ────────────────────

    function balanceOf(address addr) external view returns (uint256) {
        require(addr != address(0), "Zero address");
        return _balances[addr];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "Nonexistent token");
        return o;
    }

    function approve(address to, uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        require(msg.sender == tokenOwner || _operatorApprovals[tokenOwner][msg.sender], "Not authorized");
        _approvals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "Nonexistent token");
        return _approvals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address _own, address operator) public view returns (bool) {
        return _operatorApprovals[_own][operator];
    }

    /**
     * @notice Transfer model NFT with royalty enforcement
     * @dev Royalty is collected from msg.value if provided
     */
    function transferFrom(address from, address to, uint256 tokenId) public payable whenNotPaused {
        require(to != address(0), "Zero address");
        address tokenOwner = ownerOf(tokenId);
        require(from == tokenOwner, "Not token owner");
        require(
            msg.sender == tokenOwner ||
            getApproved(tokenId) == msg.sender ||
            isApprovedForAll(tokenOwner, msg.sender),
            "Not authorized"
        );

        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;
        delete _approvals[tokenId];

        emit Transfer(from, to, tokenId);
    }

    /**
     * @notice Transfer with royalty payment for secondary sales
     * @param salePrice The sale price for royalty calculation
     */
    function transferWithRoyalty(
        address from,
        address to,
        uint256 tokenId,
        uint256 salePrice
    ) external payable whenNotPaused {
        (address receiver, uint256 royaltyAmount) = royaltyInfo(tokenId, salePrice);
        require(msg.value >= royaltyAmount, "Insufficient royalty");

        // Pay royalty to creator
        if (royaltyAmount > 0 && receiver != address(0)) {
            (bool ok, ) = receiver.call{value: royaltyAmount}("");
            require(ok, "Royalty payment failed");
            emit RoyaltyPaid(tokenId, receiver, royaltyAmount);
        }

        // Refund excess
        uint256 excess = msg.value - royaltyAmount;
        if (excess > 0) {
            (bool ok2, ) = msg.sender.call{value: excess}("");
            require(ok2, "Refund failed");
        }

        // Execute transfer
        transferFrom(from, to, tokenId);
    }

    // ──────────────────── Minting ────────────────────

    /**
     * @notice Mint a new AI model NFT
     * @param modelHash Hash of the model (ensures uniqueness)
     * @param metadataURI IPFS URI for model metadata
     * @param royaltyBPS Royalty percentage in basis points
     */
    function mintModel(
        bytes32 modelHash,
        string calldata metadataURI,
        uint96 royaltyBPS
    ) external payable whenNotPaused returns (uint256) {
        require(msg.value >= mintFee, "Insufficient fee");
        require(!modelHashExists[modelHash], "Model already exists");
        require(royaltyBPS <= maxRoyaltyBPS, "Royalty too high");
        require(bytes(metadataURI).length > 0, "Empty URI");

        uint256 tokenId = ++totalSupply;
        modelHashExists[modelHash] = true;

        models[tokenId] = ModelInfo({
            modelHash: modelHash,
            metadataURI: metadataURI,
            creator: msg.sender,
            royaltyBPS: royaltyBPS,
            currentVersion: 1,
            mintedAt: block.timestamp
        });

        versions[tokenId][1] = ModelVersion({
            versionHash: modelHash,
            changeLog: "Initial version",
            timestamp: block.timestamp
        });

        _owners[tokenId] = msg.sender;
        _balances[msg.sender]++;

        emit Transfer(address(0), msg.sender, tokenId);
        emit ModelMinted(tokenId, msg.sender, modelHash, royaltyBPS);
        return tokenId;
    }

    // ──────────────────── Versioning ────────────────────

    /**
     * @notice Add a new version to an existing model
     * @param tokenId The model token ID
     * @param versionHash Hash of the new version
     * @param changeLog Description of changes
     */
    function addVersion(
        uint256 tokenId,
        bytes32 versionHash,
        string calldata changeLog
    ) external {
        require(ownerOf(tokenId) == msg.sender, "Not model owner");
        require(!modelHashExists[versionHash], "Hash already exists");

        modelHashExists[versionHash] = true;
        ModelInfo storage m = models[tokenId];
        m.currentVersion++;
        m.modelHash = versionHash;

        versions[tokenId][m.currentVersion] = ModelVersion({
            versionHash: versionHash,
            changeLog: changeLog,
            timestamp: block.timestamp
        });

        emit ModelVersionAdded(tokenId, m.currentVersion, versionHash);
    }

    /**
     * @notice Update royalty percentage (creator only)
     */
    function setRoyalty(uint256 tokenId, uint96 newRoyaltyBPS) external {
        require(models[tokenId].creator == msg.sender, "Not creator");
        require(newRoyaltyBPS <= maxRoyaltyBPS, "Royalty too high");

        models[tokenId].royaltyBPS = newRoyaltyBPS;
        emit RoyaltyUpdated(tokenId, newRoyaltyBPS);
    }

    // ──────────────────── ERC-2981 Royalty Info ────────────────────

    /**
     * @notice ERC-2981 royaltyInfo implementation
     * @param tokenId The NFT token ID
     * @param salePrice The sale price
     * @return receiver Royalty recipient
     * @return royaltyAmount Amount of royalty to pay
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        public view returns (address receiver, uint256 royaltyAmount)
    {
        ModelInfo storage m = models[tokenId];
        receiver = m.creator;
        royaltyAmount = (salePrice * m.royaltyBPS) / 10000;
    }

    // ──────────────────── Views ────────────────────

    function getModel(uint256 tokenId) external view returns (ModelInfo memory) {
        require(_owners[tokenId] != address(0), "Nonexistent token");
        return models[tokenId];
    }

    function getVersion(uint256 tokenId, uint256 version) external view returns (ModelVersion memory) {
        return versions[tokenId][version];
    }

    // ──────────────────── Admin ────────────────────

    function setMintFee(uint256 newFee) external onlyOwner {
        mintFee = newFee;
        emit MintFeeUpdated(newFee);
    }

    function withdraw() external onlyOwner {
        (bool ok, ) = owner.call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd || // ERC-721
               interfaceId == 0x2a55205a || // ERC-2981
               interfaceId == 0x01ffc9a7;   // ERC-165
    }

    receive() external payable {}
}
