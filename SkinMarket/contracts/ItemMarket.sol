// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ItemMarket
 * @author ProbeBuilders
 * @notice Cross-game item marketplace supporting ERC-721 and ERC-1155 NFT trading
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

/// @dev Minimal ERC-721 interface for transfers
interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

/// @dev Minimal ERC-1155 interface for transfers
interface IERC1155 {
    function balanceOf(address account, uint256 id) external view returns (uint256);
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
    function isApprovedForAll(address account, address operator) external view returns (bool);
}

contract ItemMarket {
    // ─── Ownership ───────────────────────────────────────────────────
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "ItemMarket: not owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ItemMarket: zero address");
        owner = newOwner;
    }

    // ─── Pausable ────────────────────────────────────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "ItemMarket: paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ─── Reentrancy Guard ────────────────────────────────────────────
    uint256 private _status = 1;
    modifier nonReentrant() { require(_status != 2, "ItemMarket: reentrant"); _status = 2; _; _status = 1; }

    // ─── Enums & Structs ─────────────────────────────────────────────
    enum TokenStandard { ERC721, ERC1155 }
    enum ListingStatus { Active, Sold, Cancelled }
    enum OfferStatus { Pending, Accepted, Rejected, Cancelled }

    /// @notice A marketplace listing
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 amount;         // 1 for ERC-721, 1+ for ERC-1155
        uint256 price;
        string gameId;          // off-chain game identifier
        TokenStandard standard;
        ListingStatus status;
        uint256 createdAt;
    }

    /// @notice An offer on a listing
    struct Offer {
        address buyer;
        uint256 listingId;
        uint256 price;
        OfferStatus status;
        uint256 createdAt;
        uint256 expiresAt;
    }

    // ─── State ───────────────────────────────────────────────────────
    uint256 public nextListingId = 1;
    uint256 public nextOfferId = 1;
    uint256 public platformFeeBPS = 250; // 2.5%
    uint256 public constant MAX_FEE_BPS = 1000; // 10% cap

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Offer) public offers;
    mapping(uint256 => uint256[]) public listingOffers; // listingId => offerIds
    mapping(address => uint256) public pendingWithdrawals;

    // ─── Events ──────────────────────────────────────────────────────
    event ItemListed(uint256 indexed listingId, address indexed seller, address nftContract, uint256 tokenId, uint256 price, string gameId);
    event ItemSold(uint256 indexed listingId, address indexed buyer, uint256 price);
    event OfferMade(uint256 indexed offerId, uint256 indexed listingId, address indexed buyer, uint256 price);
    event OfferAccepted(uint256 indexed offerId, uint256 indexed listingId);
    event OfferRejected(uint256 indexed offerId);
    event ListingCancelled(uint256 indexed listingId);
    event FeeUpdated(uint256 newFeeBPS);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
    }

    // ─── Listing Functions ───────────────────────────────────────────

    /// @notice List an item for sale
    /// @param nftContract The NFT contract address
    /// @param tokenId The token ID
    /// @param amount Quantity (1 for ERC-721)
    /// @param price Listing price in wei
    /// @param gameId Off-chain game identifier string
    /// @param standard 0 = ERC721, 1 = ERC1155
    function listItem(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        string calldata gameId,
        TokenStandard standard
    ) external whenNotPaused {
        require(nftContract != address(0), "ItemMarket: zero contract");
        require(price > 0, "ItemMarket: zero price");
        require(bytes(gameId).length > 0, "ItemMarket: empty gameId");

        if (standard == TokenStandard.ERC721) {
            require(amount == 1, "ItemMarket: ERC721 amount must be 1");
            IERC721 nft = IERC721(nftContract);
            require(nft.ownerOf(tokenId) == msg.sender, "ItemMarket: not token owner");
            require(
                nft.getApproved(tokenId) == address(this) || nft.isApprovedForAll(msg.sender, address(this)),
                "ItemMarket: not approved"
            );
        } else {
            require(amount > 0, "ItemMarket: zero amount");
            IERC1155 nft = IERC1155(nftContract);
            require(nft.balanceOf(msg.sender, tokenId) >= amount, "ItemMarket: insufficient balance");
            require(nft.isApprovedForAll(msg.sender, address(this)), "ItemMarket: not approved");
        }

        uint256 listingId = nextListingId++;
        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            amount: amount,
            price: price,
            gameId: gameId,
            standard: standard,
            status: ListingStatus.Active,
            createdAt: block.timestamp
        });

        emit ItemListed(listingId, msg.sender, nftContract, tokenId, price, gameId);
    }

    /// @notice Buy an item at the listed price
    /// @param listingId The listing to purchase
    function buyItem(uint256 listingId) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.status == ListingStatus.Active, "ItemMarket: listing not active");
        require(msg.value >= listing.price, "ItemMarket: insufficient payment");
        require(msg.sender != listing.seller, "ItemMarket: cannot buy own listing");

        listing.status = ListingStatus.Sold;
        _executeTransfer(listing, msg.sender);
        _distributeFunds(listing.seller, listing.price);

        emit ItemSold(listingId, msg.sender, listing.price);
    }

    /// @notice Make an offer on a listing
    /// @param listingId The listing to make an offer on
    /// @param expirationHours Hours until the offer expires
    function makeOffer(uint256 listingId, uint256 expirationHours) external payable whenNotPaused {
        require(msg.value > 0, "ItemMarket: zero offer");
        require(expirationHours > 0 && expirationHours <= 168, "ItemMarket: invalid expiration");
        Listing storage listing = listings[listingId];
        require(listing.status == ListingStatus.Active, "ItemMarket: listing not active");
        require(msg.sender != listing.seller, "ItemMarket: cannot offer on own listing");

        uint256 offerId = nextOfferId++;
        offers[offerId] = Offer({
            buyer: msg.sender,
            listingId: listingId,
            price: msg.value,
            status: OfferStatus.Pending,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + (expirationHours * 1 hours)
        });
        listingOffers[listingId].push(offerId);

        emit OfferMade(offerId, listingId, msg.sender, msg.value);
    }

    /// @notice Accept an offer (seller only)
    /// @param offerId The offer to accept
    function acceptOffer(uint256 offerId) external nonReentrant whenNotPaused {
        Offer storage offer = offers[offerId];
        require(offer.status == OfferStatus.Pending, "ItemMarket: offer not pending");
        require(block.timestamp < offer.expiresAt, "ItemMarket: offer expired");

        Listing storage listing = listings[offer.listingId];
        require(listing.seller == msg.sender, "ItemMarket: not seller");
        require(listing.status == ListingStatus.Active, "ItemMarket: listing not active");

        offer.status = OfferStatus.Accepted;
        listing.status = ListingStatus.Sold;

        _executeTransfer(listing, offer.buyer);
        _distributeFunds(listing.seller, offer.price);

        emit OfferAccepted(offerId, offer.listingId);
    }

    /// @notice Cancel an offer and get refund (buyer only, or if expired)
    /// @param offerId The offer to cancel
    function cancelOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        require(offer.status == OfferStatus.Pending, "ItemMarket: offer not pending");
        require(offer.buyer == msg.sender || block.timestamp >= offer.expiresAt, "ItemMarket: not authorized");

        offer.status = OfferStatus.Cancelled;

        (bool success, ) = payable(offer.buyer).call{value: offer.price}("");
        require(success, "ItemMarket: refund failed");
    }

    /// @notice Cancel a listing (seller only)
    /// @param listingId The listing to cancel
    function cancelListing(uint256 listingId) external {
        Listing storage listing = listings[listingId];
        require(listing.seller == msg.sender, "ItemMarket: not seller");
        require(listing.status == ListingStatus.Active, "ItemMarket: listing not active");
        listing.status = ListingStatus.Cancelled;
        emit ListingCancelled(listingId);
    }

    // ─── Internal ────────────────────────────────────────────────────

    function _executeTransfer(Listing storage listing, address buyer) internal {
        if (listing.standard == TokenStandard.ERC721) {
            IERC721(listing.nftContract).transferFrom(listing.seller, buyer, listing.tokenId);
        } else {
            IERC1155(listing.nftContract).safeTransferFrom(
                listing.seller, buyer, listing.tokenId, listing.amount, ""
            );
        }
    }

    function _distributeFunds(address seller, uint256 price) internal {
        uint256 fee = (price * platformFeeBPS) / 10000;
        uint256 sellerAmount = price - fee;

        (bool success, ) = payable(seller).call{value: sellerAmount}("");
        require(success, "ItemMarket: seller payment failed");
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get all offer IDs for a listing
    function getListingOffers(uint256 listingId) external view returns (uint256[] memory) {
        return listingOffers[listingId];
    }

    // ─── Admin ───────────────────────────────────────────────────────

    /// @notice Update platform fee (max 10%)
    function setFee(uint256 newFeeBPS) external onlyOwner {
        require(newFeeBPS <= MAX_FEE_BPS, "ItemMarket: fee too high");
        platformFeeBPS = newFeeBPS;
        emit FeeUpdated(newFeeBPS);
    }

    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = payable(owner).call{value: address(this).balance}("");
        require(success, "ItemMarket: withdraw failed");
    }

    receive() external payable {}
}
