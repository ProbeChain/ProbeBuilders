// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NFTRental
 * @author ProbeChain Rydberg Testnet
 * @notice NFT rental marketplace with collateral-based lending, daily rates, and late return handling
 * @dev List NFTs for rent, rent with collateral, return or claim late penalties
 */

// ---------- Inlined Ownable ----------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: caller is not the owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner); _owner = newOwner;
    }
}

// ---------- Inlined ReentrancyGuard ----------
abstract contract ReentrancyGuard {
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    constructor() { _status = _NOT_ENTERED; }
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED; _; _status = _NOT_ENTERED;
    }
}

// ---------- Inlined Pausable ----------
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

contract NFTRental is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum ListingStatus { Active, Rented, Cancelled }
    enum RentalStatus { Active, Returned, LateClaimable, Defaulted }

    // ---------- Structs ----------
    struct Listing {
        uint256 id;
        address lender;
        address nftContract;
        uint256 tokenId;
        uint256 dailyRate;
        uint256 collateralRequired;
        uint256 maxDuration;
        ListingStatus status;
        uint256 listedAt;
    }

    struct Rental {
        uint256 id;
        uint256 listingId;
        address renter;
        uint256 startTime;
        uint256 endTime;
        uint256 rentalFee;
        uint256 collateral;
        RentalStatus status;
        uint256 returnedAt;
    }

    // ---------- State ----------
    uint256 public nextListingId;
    uint256 public nextRentalId;
    uint256 public platformFeeBPS;
    uint256 public lateReturnPenaltyBPS;
    uint256 public gracePeriod;

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Rental) public rentals;
    mapping(address => uint256[]) public lenderListings;
    mapping(address => uint256[]) public renterRentals;
    mapping(address => uint256) public lenderEarnings;

    // ---------- Events ----------
    /// @notice Emitted when an NFT is listed for rent
    event NFTListed(uint256 indexed listingId, address indexed lender, address nftContract, uint256 tokenId, uint256 dailyRate);
    /// @notice Emitted when an NFT is rented
    event NFTRented(uint256 indexed rentalId, uint256 indexed listingId, address indexed renter, uint256 days_, uint256 totalCost);
    /// @notice Emitted when an NFT is returned
    event NFTReturned(uint256 indexed rentalId, address indexed renter, uint256 collateralRefund);
    /// @notice Emitted when a late return is claimed by lender
    event LateReturnClaimed(uint256 indexed rentalId, address indexed lender, uint256 penalty);
    /// @notice Emitted when a listing is cancelled
    event ListingCancelled(uint256 indexed listingId);
    /// @notice Emitted when earnings are claimed
    event EarningsClaimed(address indexed lender, uint256 amount);

    // ---------- Constructor ----------
    constructor(uint256 _feeBPS, uint256 _lateReturnPenaltyBPS, uint256 _gracePeriod)
        Ownable() ReentrancyGuard() Pausable()
    {
        require(_feeBPS <= 500, "Fee too high");
        require(_lateReturnPenaltyBPS <= 5000, "Penalty too high");
        platformFeeBPS = _feeBPS;
        lateReturnPenaltyBPS = _lateReturnPenaltyBPS;
        gracePeriod = _gracePeriod;
        nextListingId = 1;
        nextRentalId = 1;
    }

    /**
     * @notice List an NFT for rent (must approve this contract first)
     * @param nftContract The NFT contract address
     * @param tokenId The token ID
     * @param dailyRate Daily rental rate in wei
     * @param maxDuration Maximum rental duration in days
     * @return listingId The listing ID
     */
    function listForRent(address nftContract, uint256 tokenId, uint256 dailyRate, uint256 maxDuration)
        external
        whenNotPaused
        returns (uint256 listingId)
    {
        require(nftContract != address(0), "Zero NFT address");
        require(dailyRate > 0, "Zero daily rate");
        require(maxDuration >= 1 && maxDuration <= 365, "Invalid max duration");

        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not NFT owner");

        // Transfer NFT to contract for escrow
        nft.transferFrom(msg.sender, address(this), tokenId);

        listingId = nextListingId++;
        Listing storage l = listings[listingId];
        l.id = listingId;
        l.lender = msg.sender;
        l.nftContract = nftContract;
        l.tokenId = tokenId;
        l.dailyRate = dailyRate;
        l.collateralRequired = dailyRate * maxDuration * 2;
        l.maxDuration = maxDuration;
        l.status = ListingStatus.Active;
        l.listedAt = block.timestamp;

        lenderListings[msg.sender].push(listingId);
        emit NFTListed(listingId, msg.sender, nftContract, tokenId, dailyRate);
    }

    /**
     * @notice Rent a listed NFT
     * @param listingId The listing to rent
     * @param days_ Number of days to rent
     * @return rentalId The rental ID
     */
    function rent(uint256 listingId, uint256 days_)
        external
        payable
        nonReentrant
        whenNotPaused
        returns (uint256 rentalId)
    {
        Listing storage l = listings[listingId];
        require(l.status == ListingStatus.Active, "Listing not active");
        require(days_ >= 1 && days_ <= l.maxDuration, "Invalid duration");

        uint256 rentalFee = l.dailyRate * days_;
        uint256 totalRequired = rentalFee + l.collateralRequired;
        require(msg.value >= totalRequired, "Insufficient payment (fee + collateral)");

        l.status = ListingStatus.Rented;

        rentalId = nextRentalId++;
        Rental storage r = rentals[rentalId];
        r.id = rentalId;
        r.listingId = listingId;
        r.renter = msg.sender;
        r.startTime = block.timestamp;
        r.endTime = block.timestamp + (days_ * 1 days);
        r.rentalFee = rentalFee;
        r.collateral = l.collateralRequired;
        r.status = RentalStatus.Active;

        // Transfer NFT to renter
        IERC721(l.nftContract).transferFrom(address(this), msg.sender, l.tokenId);

        // Pay lender (minus platform fee)
        uint256 fee = (rentalFee * platformFeeBPS) / 10000;
        lenderEarnings[l.lender] += rentalFee - fee;

        renterRentals[msg.sender].push(rentalId);
        emit NFTRented(rentalId, listingId, msg.sender, days_, totalRequired);
    }

    /**
     * @notice Return a rented NFT (must approve this contract first)
     * @param rentalId The rental to return
     */
    function returnNFT(uint256 rentalId) external nonReentrant whenNotPaused {
        Rental storage r = rentals[rentalId];
        require(r.renter == msg.sender, "Not renter");
        require(r.status == RentalStatus.Active, "Not active rental");

        Listing storage l = listings[r.listingId];

        // Transfer NFT back
        IERC721(l.nftContract).transferFrom(msg.sender, l.lender, l.tokenId);

        r.status = RentalStatus.Returned;
        r.returnedAt = block.timestamp;
        l.status = ListingStatus.Active;

        // Calculate late penalty
        uint256 refund = r.collateral;
        if (block.timestamp > r.endTime + gracePeriod) {
            uint256 lateDays = (block.timestamp - r.endTime) / 1 days + 1;
            uint256 penalty = l.dailyRate * lateDays * lateReturnPenaltyBPS / 10000;
            if (penalty > refund) penalty = refund;
            refund -= penalty;
            lenderEarnings[l.lender] += penalty;
        }

        if (refund > 0) {
            (bool ok, ) = msg.sender.call{value: refund}("");
            require(ok, "Refund failed");
        }

        emit NFTReturned(rentalId, msg.sender, refund);
    }

    /**
     * @notice Lender claims collateral for severely late return
     * @param rentalId The overdue rental
     */
    function claimLateReturn(uint256 rentalId) external nonReentrant {
        Rental storage r = rentals[rentalId];
        Listing storage l = listings[r.listingId];
        require(l.lender == msg.sender, "Not lender");
        require(r.status == RentalStatus.Active, "Not active");
        require(block.timestamp > r.endTime + gracePeriod + 7 days, "Default period not reached");

        r.status = RentalStatus.Defaulted;
        lenderEarnings[l.lender] += r.collateral;

        emit LateReturnClaimed(rentalId, msg.sender, r.collateral);
    }

    /**
     * @notice Cancel an active listing (not rented)
     * @param listingId The listing to cancel
     */
    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage l = listings[listingId];
        require(l.lender == msg.sender, "Not lender");
        require(l.status == ListingStatus.Active, "Not active");

        l.status = ListingStatus.Cancelled;
        IERC721(l.nftContract).transferFrom(address(this), msg.sender, l.tokenId);
        emit ListingCancelled(listingId);
    }

    /**
     * @notice Claim accumulated earnings
     */
    function claimEarnings() external nonReentrant {
        uint256 amount = lenderEarnings[msg.sender];
        require(amount > 0, "No earnings");
        lenderEarnings[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        emit EarningsClaimed(msg.sender, amount);
    }

    // ---------- View ----------
    function getLenderListings(address lender) external view returns (uint256[] memory) {
        return lenderListings[lender];
    }

    function getRenterRentals(address renter) external view returns (uint256[] memory) {
        return renterRentals[renter];
    }

    function setFees(uint256 _feeBPS, uint256 _penaltyBPS) external onlyOwner {
        require(_feeBPS <= 500 && _penaltyBPS <= 5000, "Too high");
        platformFeeBPS = _feeBPS;
        lateReturnPenaltyBPS = _penaltyBPS;
    }
}
