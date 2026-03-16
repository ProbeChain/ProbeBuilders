// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title LandValuation
 * @author ProbeChain Builders
 * @notice Virtual real estate AI valuation, appraisal, and marketplace
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
// LandValuation
// ──────────────────────────────────────────────────────────────
contract LandValuation is Ownable, ReentrancyGuard, Pausable {

    // ── Structs ──────────────────────────────────────────────
    struct Land {
        address landContract;
        uint256 tokenId;
        bytes32 metadataHash;
        address registrant;
        uint256 registeredAt;
        bool active;
    }

    struct Appraisal {
        uint256 landId;
        address appraiser;
        uint256 value;             // In wei
        string methodology;       // e.g., "comparable-sales", "AI-model-v2", "floor-price"
        uint256 timestamp;
    }

    struct Listing {
        uint256 landId;
        address seller;
        uint256 askPrice;
        bool active;
        uint256 listedAt;
    }

    struct Bid {
        uint256 landId;
        address bidder;
        uint256 amount;
        uint256 bidAt;
        bool accepted;
        bool withdrawn;
    }

    // ── State ────────────────────────────────────────────────
    uint256 public landCounter;
    uint256 public appraisalCounter;
    uint256 public listingCounter;
    uint256 public bidCounter;
    uint256 public platformFeePercent = 3;

    mapping(uint256 => Land) public lands;
    mapping(uint256 => Appraisal) public appraisals;
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Bid) public bids;

    /// @dev landContract => tokenId => landId
    mapping(address => mapping(uint256 => uint256)) public landLookup;
    /// @dev landId => appraisal IDs
    mapping(uint256 => uint256[]) public landAppraisals;
    /// @dev landId => listing ID (latest)
    mapping(uint256 => uint256) public activeListing;
    /// @dev landId => bid IDs
    mapping(uint256 => uint256[]) public landBids;
    /// @dev address => is approved appraiser
    mapping(address => bool) public approvedAppraisers;

    // ── Events ───────────────────────────────────────────────
    event LandRegistered(uint256 indexed landId, address indexed landContract, uint256 tokenId, address registrant);
    event AppraisalSubmitted(uint256 indexed appraisalId, uint256 indexed landId, address appraiser, uint256 value, string methodology);
    event LandListed(uint256 indexed listingId, uint256 indexed landId, uint256 askPrice);
    event ListingCancelled(uint256 indexed listingId, uint256 indexed landId);
    event BidPlaced(uint256 indexed bidId, uint256 indexed landId, address bidder, uint256 amount);
    event BidAccepted(uint256 indexed bidId, uint256 indexed landId, address seller, address buyer, uint256 amount);
    event BidWithdrawn(uint256 indexed bidId, uint256 indexed landId);
    event AppraiserUpdated(address indexed appraiser, bool approved);

    // ── Constructor ──────────────────────────────────────────
    constructor() {}

    // ── Receive ──────────────────────────────────────────────
    receive() external payable {}

    // ── Appraiser Management ─────────────────────────────────

    /**
     * @notice Approve or revoke an appraiser
     * @param appraiser The appraiser address
     * @param approved Whether to approve
     */
    function setAppraiser(address appraiser, bool approved) external onlyOwner {
        approvedAppraisers[appraiser] = approved;
        emit AppraiserUpdated(appraiser, approved);
    }

    // ── Core Functions ───────────────────────────────────────

    /**
     * @notice Register a virtual land asset for valuation
     * @param landContract The NFT contract address
     * @param tokenId The token ID in that contract
     * @param metadataHash IPFS hash of land metadata
     * @return landId The registered land ID
     */
    function registerLand(address landContract, uint256 tokenId, bytes32 metadataHash)
        external
        whenNotPaused
        returns (uint256 landId)
    {
        require(landContract != address(0), "LandValuation: zero contract");
        require(landLookup[landContract][tokenId] == 0, "LandValuation: already registered");

        landId = ++landCounter;
        lands[landId] = Land({
            landContract: landContract,
            tokenId: tokenId,
            metadataHash: metadataHash,
            registrant: msg.sender,
            registeredAt: block.timestamp,
            active: true
        });
        landLookup[landContract][tokenId] = landId;

        emit LandRegistered(landId, landContract, tokenId, msg.sender);
    }

    /**
     * @notice Submit an appraisal for a registered land
     * @param landId The land to appraise
     * @param value Appraised value in wei
     * @param methodology Methodology used for appraisal
     * @return appraisalId The appraisal record ID
     */
    function submitAppraisal(uint256 landId, uint256 value, string calldata methodology)
        external
        whenNotPaused
        returns (uint256 appraisalId)
    {
        require(lands[landId].active, "LandValuation: land not active");
        require(approvedAppraisers[msg.sender], "LandValuation: not approved appraiser");
        require(value > 0, "LandValuation: zero value");

        appraisalId = ++appraisalCounter;
        appraisals[appraisalId] = Appraisal({
            landId: landId,
            appraiser: msg.sender,
            value: value,
            methodology: methodology,
            timestamp: block.timestamp
        });
        landAppraisals[landId].push(appraisalId);

        emit AppraisalSubmitted(appraisalId, landId, msg.sender, value, methodology);
    }

    /**
     * @notice Get the average valuation of a land from all appraisals
     * @param landId The land ID
     * @return avgValue Average appraised value
     * @return appraisalCount Number of appraisals
     */
    function getValuation(uint256 landId)
        external
        view
        returns (uint256 avgValue, uint256 appraisalCount)
    {
        uint256[] storage ids = landAppraisals[landId];
        appraisalCount = ids.length;
        if (appraisalCount == 0) return (0, 0);

        uint256 total;
        for (uint256 i = 0; i < appraisalCount; i++) {
            total += appraisals[ids[i]].value;
        }
        avgValue = total / appraisalCount;
    }

    /**
     * @notice List a land for sale
     * @param landId The land to list
     * @param askPrice Asking price in wei
     * @return listingId The listing ID
     */
    function listForSale(uint256 landId, uint256 askPrice)
        external
        whenNotPaused
        returns (uint256 listingId)
    {
        Land storage l = lands[landId];
        require(l.active, "LandValuation: land not active");
        require(l.registrant == msg.sender, "LandValuation: not registrant");
        require(askPrice > 0, "LandValuation: zero price");
        require(activeListing[landId] == 0, "LandValuation: already listed");

        listingId = ++listingCounter;
        listings[listingId] = Listing({
            landId: landId,
            seller: msg.sender,
            askPrice: askPrice,
            active: true,
            listedAt: block.timestamp
        });
        activeListing[landId] = listingId;

        emit LandListed(listingId, landId, askPrice);
    }

    /**
     * @notice Cancel a listing
     * @param landId The land to delist
     */
    function cancelListing(uint256 landId) external {
        uint256 listingId = activeListing[landId];
        require(listingId != 0, "LandValuation: not listed");
        Listing storage lst = listings[listingId];
        require(lst.seller == msg.sender || msg.sender == owner(), "LandValuation: not authorized");

        lst.active = false;
        activeListing[landId] = 0;
        emit ListingCancelled(listingId, landId);
    }

    /**
     * @notice Make a bid on a listed land
     * @param landId The land to bid on
     * @return bidId The bid ID
     */
    function makeBid(uint256 landId) external payable whenNotPaused nonReentrant returns (uint256 bidId) {
        uint256 listingId = activeListing[landId];
        require(listingId != 0, "LandValuation: not listed");
        require(msg.value > 0, "LandValuation: zero bid");

        bidId = ++bidCounter;
        bids[bidId] = Bid({
            landId: landId,
            bidder: msg.sender,
            amount: msg.value,
            bidAt: block.timestamp,
            accepted: false,
            withdrawn: false
        });
        landBids[landId].push(bidId);

        emit BidPlaced(bidId, landId, msg.sender, msg.value);
    }

    /**
     * @notice Accept a bid (seller only)
     * @param bidId The bid to accept
     */
    function acceptBid(uint256 bidId) external nonReentrant {
        Bid storage b = bids[bidId];
        require(!b.accepted && !b.withdrawn, "LandValuation: bid closed");

        Land storage l = lands[b.landId];
        require(l.registrant == msg.sender, "LandValuation: not registrant");

        b.accepted = true;

        // Close listing
        uint256 listingId = activeListing[b.landId];
        if (listingId != 0) {
            listings[listingId].active = false;
            activeListing[b.landId] = 0;
        }

        // Transfer registrant
        l.registrant = b.bidder;

        // Pay seller minus fee
        uint256 fee = (b.amount * platformFeePercent) / 100;
        uint256 payout = b.amount - fee;

        (bool sent,) = msg.sender.call{value: payout}("");
        require(sent, "LandValuation: payout failed");

        if (fee > 0) {
            (bool feeSent,) = owner().call{value: fee}("");
            require(feeSent, "LandValuation: fee transfer failed");
        }

        emit BidAccepted(bidId, b.landId, msg.sender, b.bidder, b.amount);
    }

    /**
     * @notice Withdraw a bid (bidder only)
     * @param bidId The bid to withdraw
     */
    function withdrawBid(uint256 bidId) external nonReentrant {
        Bid storage b = bids[bidId];
        require(b.bidder == msg.sender, "LandValuation: not bidder");
        require(!b.accepted && !b.withdrawn, "LandValuation: bid closed");

        b.withdrawn = true;

        (bool sent,) = msg.sender.call{value: b.amount}("");
        require(sent, "LandValuation: refund failed");

        emit BidWithdrawn(bidId, b.landId);
    }

    // ── Admin ────────────────────────────────────────────────

    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 10, "LandValuation: fee too high");
        platformFeePercent = _fee;
    }

    // ── View Helpers ─────────────────────────────────────────

    function getLandAppraisals(uint256 landId) external view returns (uint256[] memory) {
        return landAppraisals[landId];
    }

    function getLandBids(uint256 landId) external view returns (uint256[] memory) {
        return landBids[landId];
    }
}
