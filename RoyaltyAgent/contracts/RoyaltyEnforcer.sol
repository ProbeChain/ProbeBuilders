// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title RoyaltyEnforcer
 * @author ProbeBuilders
 * @notice Tracks NFT secondary sales and enforces royalty payments to creators
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */
contract RoyaltyEnforcer {
    // ─── Ownership ───────────────────────────────────────────────────
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "RoyaltyEnforcer: not owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "RoyaltyEnforcer: zero address");
        owner = newOwner;
    }

    // ─── Pausable ────────────────────────────────────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "RoyaltyEnforcer: paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ─── Reentrancy Guard ────────────────────────────────────────────
    uint256 private _status = 1;
    modifier nonReentrant() { require(_status != 2, "RoyaltyEnforcer: reentrant"); _status = 2; _; _status = 1; }

    // ─── Structs ─────────────────────────────────────────────────────

    /// @notice Royalty configuration for an NFT collection
    struct CollectionConfig {
        address creator;          // royalty recipient
        uint256 royaltyBPS;       // basis points (e.g., 500 = 5%)
        uint256 totalSalesVolume; // total volume of recorded sales
        uint256 totalRoyaltiesAccrued;
        uint256 totalRoyaltiesClaimed;
        uint256 saleCount;
        bool registered;
        uint256 registeredAt;
    }

    /// @notice Record of a single secondary sale
    struct SaleRecord {
        address nftContract;
        uint256 tokenId;
        address seller;
        address buyer;
        uint256 salePrice;
        uint256 royaltyAmount;
        uint256 timestamp;
    }

    // ─── State ───────────────────────────────────────────────────────
    uint256 public constant MAX_ROYALTY_BPS = 2500; // 25% max
    uint256 public nextSaleId = 1;
    uint256 public registrationFee = 0.001 ether;

    mapping(address => CollectionConfig) public collections;
    mapping(uint256 => SaleRecord) public saleRecords;
    mapping(address => uint256[]) public collectionSales; // nftContract => saleIds
    mapping(address => bool) public authorizedRecorders; // can record sales

    // ─── Events ──────────────────────────────────────────────────────
    event CollectionRegistered(address indexed nftContract, address indexed creator, uint256 royaltyBPS);
    event CollectionUpdated(address indexed nftContract, uint256 newRoyaltyBPS, address newRecipient);
    event SaleRecorded(uint256 indexed saleId, address indexed nftContract, uint256 tokenId, uint256 salePrice, uint256 royaltyAmount);
    event RoyaltiesClaimed(address indexed nftContract, address indexed creator, uint256 amount);
    event RecorderAuthorized(address indexed recorder);
    event RecorderRevoked(address indexed recorder);
    event RoyaltyPaid(address indexed nftContract, uint256 indexed saleId, address indexed buyer, uint256 amount);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        authorizedRecorders[msg.sender] = true;
    }

    // ─── Registration ────────────────────────────────────────────────

    /// @notice Register an NFT collection with royalty settings
    /// @param nftContract The NFT contract address
    /// @param royaltyBPS Royalty percentage in basis points (100 = 1%)
    /// @param recipient Address that receives royalties
    function registerCollection(
        address nftContract,
        uint256 royaltyBPS,
        address recipient
    ) external payable whenNotPaused {
        require(nftContract != address(0), "RoyaltyEnforcer: zero contract");
        require(recipient != address(0), "RoyaltyEnforcer: zero recipient");
        require(royaltyBPS > 0 && royaltyBPS <= MAX_ROYALTY_BPS, "RoyaltyEnforcer: invalid BPS");
        require(!collections[nftContract].registered, "RoyaltyEnforcer: already registered");
        require(msg.value >= registrationFee, "RoyaltyEnforcer: insufficient fee");

        collections[nftContract] = CollectionConfig({
            creator: recipient,
            royaltyBPS: royaltyBPS,
            totalSalesVolume: 0,
            totalRoyaltiesAccrued: 0,
            totalRoyaltiesClaimed: 0,
            saleCount: 0,
            registered: true,
            registeredAt: block.timestamp
        });

        emit CollectionRegistered(nftContract, recipient, royaltyBPS);
    }

    /// @notice Update royalty settings (creator only)
    /// @param nftContract The NFT contract address
    /// @param newRoyaltyBPS New royalty basis points
    /// @param newRecipient New royalty recipient
    function updateCollection(address nftContract, uint256 newRoyaltyBPS, address newRecipient) external {
        CollectionConfig storage config = collections[nftContract];
        require(config.registered, "RoyaltyEnforcer: not registered");
        require(config.creator == msg.sender, "RoyaltyEnforcer: not creator");
        require(newRoyaltyBPS > 0 && newRoyaltyBPS <= MAX_ROYALTY_BPS, "RoyaltyEnforcer: invalid BPS");
        require(newRecipient != address(0), "RoyaltyEnforcer: zero recipient");

        config.royaltyBPS = newRoyaltyBPS;
        config.creator = newRecipient;

        emit CollectionUpdated(nftContract, newRoyaltyBPS, newRecipient);
    }

    // ─── Sale Recording ──────────────────────────────────────────────

    /// @notice Record a secondary sale and collect royalty payment
    /// @param nftContract The NFT contract address
    /// @param tokenId The token that was sold
    /// @param seller The seller address
    /// @param buyer The buyer address
    /// @param salePrice The total sale price
    function recordSale(
        address nftContract,
        uint256 tokenId,
        address seller,
        address buyer,
        uint256 salePrice
    ) external payable whenNotPaused {
        require(
            authorizedRecorders[msg.sender] || msg.sender == owner,
            "RoyaltyEnforcer: not authorized recorder"
        );

        CollectionConfig storage config = collections[nftContract];
        require(config.registered, "RoyaltyEnforcer: collection not registered");
        require(salePrice > 0, "RoyaltyEnforcer: zero sale price");

        uint256 royaltyAmount = (salePrice * config.royaltyBPS) / 10000;

        uint256 saleId = nextSaleId++;
        saleRecords[saleId] = SaleRecord({
            nftContract: nftContract,
            tokenId: tokenId,
            seller: seller,
            buyer: buyer,
            salePrice: salePrice,
            royaltyAmount: royaltyAmount,
            timestamp: block.timestamp
        });

        collectionSales[nftContract].push(saleId);
        config.totalSalesVolume += salePrice;
        config.totalRoyaltiesAccrued += royaltyAmount;
        config.saleCount++;

        // If royalty payment included in msg.value, credit it immediately
        if (msg.value >= royaltyAmount) {
            config.totalRoyaltiesClaimed += royaltyAmount;
            (bool success, ) = payable(config.creator).call{value: royaltyAmount}("");
            require(success, "RoyaltyEnforcer: royalty payment failed");
            emit RoyaltyPaid(nftContract, saleId, buyer, royaltyAmount);

            // Refund excess
            if (msg.value > royaltyAmount) {
                (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - royaltyAmount}("");
                require(refundSuccess, "RoyaltyEnforcer: refund failed");
            }
        }

        emit SaleRecorded(saleId, nftContract, tokenId, salePrice, royaltyAmount);
    }

    /// @notice Claim accumulated unpaid royalties for a collection
    /// @param nftContract The NFT contract address
    function claimRoyalties(address nftContract) external nonReentrant whenNotPaused {
        CollectionConfig storage config = collections[nftContract];
        require(config.registered, "RoyaltyEnforcer: not registered");
        require(config.creator == msg.sender, "RoyaltyEnforcer: not creator");

        uint256 unclaimed = config.totalRoyaltiesAccrued - config.totalRoyaltiesClaimed;
        require(unclaimed > 0, "RoyaltyEnforcer: nothing to claim");
        require(address(this).balance >= unclaimed, "RoyaltyEnforcer: insufficient balance");

        config.totalRoyaltiesClaimed = config.totalRoyaltiesAccrued;

        (bool success, ) = payable(msg.sender).call{value: unclaimed}("");
        require(success, "RoyaltyEnforcer: claim failed");

        emit RoyaltiesClaimed(nftContract, msg.sender, unclaimed);
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get royalty info for a collection
    function getRoyaltyInfo(address nftContract)
        external
        view
        returns (
            address creator,
            uint256 royaltyBPS,
            uint256 totalVolume,
            uint256 totalRoyalties,
            uint256 unclaimedRoyalties,
            uint256 saleCount
        )
    {
        CollectionConfig storage c = collections[nftContract];
        uint256 unclaimed = c.totalRoyaltiesAccrued - c.totalRoyaltiesClaimed;
        return (c.creator, c.royaltyBPS, c.totalSalesVolume, c.totalRoyaltiesAccrued, unclaimed, c.saleCount);
    }

    /// @notice Calculate royalty for a given price
    function calculateRoyalty(address nftContract, uint256 salePrice) external view returns (uint256) {
        CollectionConfig storage c = collections[nftContract];
        if (!c.registered) return 0;
        return (salePrice * c.royaltyBPS) / 10000;
    }

    /// @notice Get sale IDs for a collection
    function getCollectionSales(address nftContract) external view returns (uint256[] memory) {
        return collectionSales[nftContract];
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function authorizeRecorder(address recorder) external onlyOwner {
        authorizedRecorders[recorder] = true;
        emit RecorderAuthorized(recorder);
    }

    function revokeRecorder(address recorder) external onlyOwner {
        authorizedRecorders[recorder] = false;
        emit RecorderRevoked(recorder);
    }

    function setRegistrationFee(uint256 newFee) external onlyOwner {
        registrationFee = newFee;
    }

    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = payable(owner).call{value: address(this).balance}("");
        require(success, "RoyaltyEnforcer: withdraw failed");
    }

    receive() external payable {}
}
