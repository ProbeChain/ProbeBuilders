// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AuctionHouse
 * @author ProbeChain
 * @notice English auction house for NFTs with minimum bid increments
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

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() { _status = _NOT_ENTERED; }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
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

contract AuctionHouse is Ownable, ReentrancyGuard, Pausable {
    /// @notice Auction status
    enum AuctionStatus { Active, Settled, Cancelled }

    /// @notice Auction record
    struct Auction {
        uint256 id;
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 startPrice;
        uint256 highestBid;
        address highestBidder;
        uint256 startTime;
        uint256 endTime;
        AuctionStatus status;
    }

    /// @dev Minimum bid increment BPS (500 = 5%)
    uint256 public minBidIncrementBPS;

    /// @dev Platform fee BPS
    uint256 public platformFeeBPS;

    /// @dev Auction counter
    uint256 private _nextAuctionId;

    /// @dev Auction ID => Auction
    mapping(uint256 => Auction) private _auctions;

    /// @dev Auction ID => bidder => pending withdrawal
    mapping(uint256 => mapping(address => uint256)) private _pendingReturns;

    /// @dev All auction IDs
    uint256[] private _auctionIds;

    /// @dev Collected fees
    uint256 public collectedFees;

    // ───────── Events ─────────

    /// @notice Emitted when an auction is created
    event AuctionCreated(uint256 indexed auctionId, address indexed seller, address nftContract, uint256 tokenId, uint256 startPrice, uint256 duration);

    /// @notice Emitted when a bid is placed
    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 amount);

    /// @notice Emitted when an auction is settled
    event AuctionSettled(uint256 indexed auctionId, address indexed winner, uint256 amount);

    /// @notice Emitted when an auction is cancelled
    event AuctionCancelled(uint256 indexed auctionId);

    /// @notice Emitted when a bid is withdrawn
    event BidWithdrawn(uint256 indexed auctionId, address indexed bidder, uint256 amount);

    // ───────── Constructor ─────────

    constructor() {
        _nextAuctionId = 1;
        minBidIncrementBPS = 500; // 5%
        platformFeeBPS = 250; // 2.5%
    }

    // ───────── Admin ─────────

    function setMinBidIncrement(uint256 bps) external onlyOwner {
        require(bps >= 100 && bps <= 2000, "Auction: invalid BPS");
        minBidIncrementBPS = bps;
    }

    function setPlatformFee(uint256 bps) external onlyOwner {
        require(bps <= 500, "Auction: fee too high");
        platformFeeBPS = bps;
    }

    function withdrawFees(address payable to) external onlyOwner nonReentrant {
        require(collectedFees > 0, "Auction: no fees");
        uint256 amount = collectedFees;
        collectedFees = 0;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Auction: transfer failed");
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Create a new auction
    /// @param nftContract The NFT contract address
    /// @param tokenId The NFT token ID
    /// @param startPrice Starting bid price
    /// @param duration Auction duration in seconds
    /// @return auctionId The new auction ID
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startPrice,
        uint256 duration
    ) external whenNotPaused returns (uint256 auctionId) {
        require(nftContract != address(0), "Auction: zero nft");
        require(startPrice > 0, "Auction: zero price");
        require(duration >= 1 hours, "Auction: too short");
        require(duration <= 30 days, "Auction: too long");

        auctionId = _nextAuctionId++;

        _auctions[auctionId] = Auction({
            id: auctionId,
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            startPrice: startPrice,
            highestBid: 0,
            highestBidder: address(0),
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            status: AuctionStatus.Active
        });

        _auctionIds.push(auctionId);

        emit AuctionCreated(auctionId, msg.sender, nftContract, tokenId, startPrice, duration);
    }

    /// @notice Place a bid on an auction
    /// @param auctionId The auction to bid on
    function placeBid(uint256 auctionId) external payable whenNotPaused nonReentrant {
        Auction storage a = _auctions[auctionId];
        require(a.id != 0, "Auction: not found");
        require(a.status == AuctionStatus.Active, "Auction: not active");
        require(block.timestamp < a.endTime, "Auction: ended");
        require(msg.sender != a.seller, "Auction: seller cannot bid");

        if (a.highestBid == 0) {
            require(msg.value >= a.startPrice, "Auction: below start price");
        } else {
            uint256 minBid = a.highestBid + (a.highestBid * minBidIncrementBPS) / 10000;
            require(msg.value >= minBid, "Auction: bid too low");
        }

        // Make previous highest bid available for withdrawal
        if (a.highestBidder != address(0)) {
            _pendingReturns[auctionId][a.highestBidder] += a.highestBid;
        }

        a.highestBid = msg.value;
        a.highestBidder = msg.sender;

        // Extend auction if bid placed in last 10 minutes
        if (a.endTime - block.timestamp < 10 minutes) {
            a.endTime = block.timestamp + 10 minutes;
        }

        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    /// @notice Settle an ended auction
    /// @param auctionId The auction to settle
    function settleAuction(uint256 auctionId) external whenNotPaused nonReentrant {
        Auction storage a = _auctions[auctionId];
        require(a.id != 0, "Auction: not found");
        require(a.status == AuctionStatus.Active, "Auction: not active");
        require(block.timestamp >= a.endTime, "Auction: not ended");

        a.status = AuctionStatus.Settled;

        if (a.highestBidder != address(0) && a.highestBid > 0) {
            uint256 fee = (a.highestBid * platformFeeBPS) / 10000;
            uint256 sellerPayment = a.highestBid - fee;
            collectedFees += fee;

            (bool sent, ) = a.seller.call{value: sellerPayment}("");
            require(sent, "Auction: payment failed");
        }

        emit AuctionSettled(auctionId, a.highestBidder, a.highestBid);
    }

    /// @notice Cancel an auction with no bids
    /// @param auctionId The auction to cancel
    function cancelAuction(uint256 auctionId) external whenNotPaused {
        Auction storage a = _auctions[auctionId];
        require(a.id != 0, "Auction: not found");
        require(a.status == AuctionStatus.Active, "Auction: not active");
        require(msg.sender == a.seller, "Auction: not seller");
        require(a.highestBidder == address(0), "Auction: has bids");

        a.status = AuctionStatus.Cancelled;
        emit AuctionCancelled(auctionId);
    }

    /// @notice Withdraw outbid funds
    /// @param auctionId The auction to withdraw from
    function withdrawBid(uint256 auctionId) external nonReentrant {
        uint256 amount = _pendingReturns[auctionId][msg.sender];
        require(amount > 0, "Auction: nothing to withdraw");

        _pendingReturns[auctionId][msg.sender] = 0;

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Auction: withdraw failed");

        emit BidWithdrawn(auctionId, msg.sender, amount);
    }

    // ───────── View Functions ─────────

    /// @notice Get auction details
    function getAuction(uint256 auctionId) external view returns (Auction memory) {
        require(_auctions[auctionId].id != 0, "Auction: not found");
        return _auctions[auctionId];
    }

    /// @notice Get pending withdrawal for a bidder
    function getPendingReturn(uint256 auctionId, address bidder) external view returns (uint256) {
        return _pendingReturns[auctionId][bidder];
    }

    /// @notice Total auctions
    function totalAuctions() external view returns (uint256) {
        return _nextAuctionId - 1;
    }

    /// @notice Get active auction IDs
    function getActiveAuctions() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < _auctionIds.length; i++) {
            if (_auctions[_auctionIds[i]].status == AuctionStatus.Active) count++;
        }
        uint256[] memory result = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < _auctionIds.length; i++) {
            if (_auctions[_auctionIds[i]].status == AuctionStatus.Active) {
                result[j++] = _auctionIds[i];
            }
        }
        return result;
    }
}
