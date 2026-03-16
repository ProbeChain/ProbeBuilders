// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title NFTFragments
 * @notice NFT fractionalization — lock an ERC-721 and issue ERC-20 shares.
 *         Buyout mechanism triggers when one holder accumulates >80% of shares.
 * @dev Implements a minimal ERC-20 per fragment set and interfaces with external ERC-721s
 */
contract NFTFragments {
    // ──────────────────── Ownership ────────────────────
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ──────────────────── Reentrancy Guard ────────────────────
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "Reentrant");
        _locked = 2;
        _;
        _locked = 1;
    }

    // ──────────────────── Pausable ────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "Paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ──────────────────── Data Structures ────────────────────
    enum FragmentStatus { Active, BuyoutInitiated, Redeemed }

    struct Fragment {
        address nftContract;
        uint256 tokenId;
        address originalOwner;
        uint256 totalShares;
        uint256 sharePrice;       // price per share in wei
        uint256 sharesAvailable;  // unsold shares
        FragmentStatus status;
        uint256 buyoutPrice;      // total buyout valuation
        address buyoutInitiator;
        uint256 buyoutDeadline;
        uint256 createdAt;
    }

    // Per-fragment ERC-20-like share balances
    // fragmentId => holder => balance
    mapping(uint256 => mapping(address => uint256)) public shareBalances;
    // fragmentId => owner => spender => allowance
    mapping(uint256 => mapping(address => mapping(address => uint256))) public shareAllowances;

    mapping(uint256 => Fragment) public fragments;
    uint256 public nextFragmentId = 1;
    uint256 public platformFeeBPS = 250; // 2.5%
    uint256 public constant BUYOUT_THRESHOLD_BPS = 8000; // 80%
    uint256 public constant BUYOUT_PERIOD = 3 days;

    // ──────────────────── Events ────────────────────
    event Fractionalized(uint256 indexed fragmentId, address indexed nftContract, uint256 tokenId, uint256 totalShares, uint256 sharePrice);
    event SharesPurchased(uint256 indexed fragmentId, address indexed buyer, uint256 amount, uint256 cost);
    event SharesTransferred(uint256 indexed fragmentId, address indexed from, address indexed to, uint256 amount);
    event BuyoutInitiated(uint256 indexed fragmentId, address indexed initiator, uint256 buyoutPrice);
    event BuyoutCompleted(uint256 indexed fragmentId, address indexed buyer);
    event NFTRedeemed(uint256 indexed fragmentId, address indexed redeemer);
    event ShareApproval(uint256 indexed fragmentId, address indexed owner, address indexed spender, uint256 amount);

    // ──────────────────── ERC-721 Interface (minimal) ────────────────────
    interface IERC721 {
        function ownerOf(uint256 tokenId) external view returns (address);
        function transferFrom(address from, address to, uint256 tokenId) external;
    }

    constructor() {
        owner = msg.sender;
    }

    // ──────────────────── Fractionalization ────────────────────

    /**
     * @notice Lock an ERC-721 NFT and create fractional shares
     * @param nftContract Address of the ERC-721 contract
     * @param tokenId Token ID to fractionalize
     * @param totalShares Number of shares to create
     * @param sharePrice Price per share in wei
     */
    function fractionalize(
        address nftContract,
        uint256 tokenId,
        uint256 totalShares,
        uint256 sharePrice
    ) external whenNotPaused returns (uint256) {
        require(nftContract != address(0), "Zero address");
        require(totalShares > 0 && totalShares <= 1_000_000, "Invalid shares");
        require(sharePrice > 0, "Zero price");

        // Transfer NFT to this contract (caller must have approved)
        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not NFT owner");
        nft.transferFrom(msg.sender, address(this), tokenId);

        uint256 fragmentId = nextFragmentId++;
        fragments[fragmentId] = Fragment({
            nftContract: nftContract,
            tokenId: tokenId,
            originalOwner: msg.sender,
            totalShares: totalShares,
            sharePrice: sharePrice,
            sharesAvailable: totalShares,
            status: FragmentStatus.Active,
            buyoutPrice: 0,
            buyoutInitiator: address(0),
            buyoutDeadline: 0,
            createdAt: block.timestamp
        });

        emit Fractionalized(fragmentId, nftContract, tokenId, totalShares, sharePrice);
        return fragmentId;
    }

    // ──────────────────── Share Trading ────────────────────

    /**
     * @notice Buy shares of a fractionalized NFT
     * @param fragmentId The fragment ID
     * @param amount Number of shares to buy
     */
    function buyShares(uint256 fragmentId, uint256 amount) external payable whenNotPaused nonReentrant {
        Fragment storage f = fragments[fragmentId];
        require(f.status == FragmentStatus.Active, "Not active");
        require(amount > 0 && amount <= f.sharesAvailable, "Invalid amount");

        uint256 cost = amount * f.sharePrice;
        require(msg.value >= cost, "Insufficient payment");

        f.sharesAvailable -= amount;
        shareBalances[fragmentId][msg.sender] += amount;

        // Pay original owner (minus fee)
        uint256 fee = (cost * platformFeeBPS) / 10000;
        uint256 payout = cost - fee;
        (bool ok, ) = f.originalOwner.call{value: payout}("");
        require(ok, "Payment failed");

        // Refund excess
        if (msg.value > cost) {
            (bool ok2, ) = msg.sender.call{value: msg.value - cost}("");
            require(ok2, "Refund failed");
        }

        emit SharesPurchased(fragmentId, msg.sender, amount, cost);

        // Check buyout threshold
        _checkBuyoutEligibility(fragmentId, msg.sender);
    }

    /**
     * @notice Transfer shares to another address
     */
    function transferShares(uint256 fragmentId, address to, uint256 amount) external whenNotPaused {
        require(to != address(0), "Zero address");
        require(shareBalances[fragmentId][msg.sender] >= amount, "Insufficient shares");

        shareBalances[fragmentId][msg.sender] -= amount;
        shareBalances[fragmentId][to] += amount;

        emit SharesTransferred(fragmentId, msg.sender, to, amount);
        _checkBuyoutEligibility(fragmentId, to);
    }

    /**
     * @notice Approve share spending
     */
    function approveShares(uint256 fragmentId, address spender, uint256 amount) external {
        shareAllowances[fragmentId][msg.sender][spender] = amount;
        emit ShareApproval(fragmentId, msg.sender, spender, amount);
    }

    /**
     * @notice Transfer shares from (with allowance)
     */
    function transferSharesFrom(uint256 fragmentId, address from, address to, uint256 amount) external whenNotPaused {
        require(shareAllowances[fragmentId][from][msg.sender] >= amount, "Allowance exceeded");
        require(shareBalances[fragmentId][from] >= amount, "Insufficient shares");

        shareAllowances[fragmentId][from][msg.sender] -= amount;
        shareBalances[fragmentId][from] -= amount;
        shareBalances[fragmentId][to] += amount;

        emit SharesTransferred(fragmentId, from, to, amount);
    }

    // ──────────────────── Buyout Mechanism ────────────────────

    /**
     * @dev Check if holder has crossed the 80% buyout threshold
     */
    function _checkBuyoutEligibility(uint256 fragmentId, address holder) internal {
        Fragment storage f = fragments[fragmentId];
        uint256 held = shareBalances[fragmentId][holder];
        uint256 soldShares = f.totalShares - f.sharesAvailable;
        if (soldShares == 0) return;

        // >80% of total shares
        if (held * 10000 >= f.totalShares * BUYOUT_THRESHOLD_BPS) {
            if (f.status == FragmentStatus.Active) {
                f.status = FragmentStatus.BuyoutInitiated;
                f.buyoutInitiator = holder;
                f.buyoutPrice = f.totalShares * f.sharePrice;
                f.buyoutDeadline = block.timestamp + BUYOUT_PERIOD;
                emit BuyoutInitiated(fragmentId, holder, f.buyoutPrice);
            }
        }
    }

    /**
     * @notice Complete buyout by paying remaining shareholders
     * @param fragmentId The fragment to buy out
     */
    function completeBuyout(uint256 fragmentId) external payable nonReentrant {
        Fragment storage f = fragments[fragmentId];
        require(f.status == FragmentStatus.BuyoutInitiated, "No buyout");
        require(f.buyoutInitiator == msg.sender, "Not initiator");
        require(block.timestamp <= f.buyoutDeadline, "Buyout expired");

        // Calculate cost for remaining shares
        uint256 ownedShares = shareBalances[fragmentId][msg.sender];
        uint256 remainingShares = f.totalShares - ownedShares;
        uint256 remainingCost = remainingShares * f.sharePrice;
        require(msg.value >= remainingCost, "Insufficient funds");

        // Give initiator all shares
        shareBalances[fragmentId][msg.sender] = f.totalShares;
        f.sharesAvailable = 0;

        emit BuyoutCompleted(fragmentId, msg.sender);
    }

    /**
     * @notice Redeem the underlying NFT (must hold 100% of shares)
     * @param fragmentId The fragment to redeem
     */
    function redeemNFT(uint256 fragmentId) external nonReentrant {
        Fragment storage f = fragments[fragmentId];
        require(f.status != FragmentStatus.Redeemed, "Already redeemed");
        require(shareBalances[fragmentId][msg.sender] == f.totalShares, "Must hold all shares");

        f.status = FragmentStatus.Redeemed;
        shareBalances[fragmentId][msg.sender] = 0;

        IERC721(f.nftContract).transferFrom(address(this), msg.sender, f.tokenId);
        emit NFTRedeemed(fragmentId, msg.sender);
    }

    // ──────────────────── Views ────────────────────

    function getFragment(uint256 fragmentId) external view returns (Fragment memory) {
        return fragments[fragmentId];
    }

    function getShareBalance(uint256 fragmentId, address holder) external view returns (uint256) {
        return shareBalances[fragmentId][holder];
    }

    // ──────────────────── Admin ────────────────────

    function setFee(uint256 newFeeBPS) external onlyOwner {
        require(newFeeBPS <= 1000, "Fee too high");
        platformFeeBPS = newFeeBPS;
    }

    function withdraw() external onlyOwner {
        (bool ok, ) = owner.call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }

    receive() external payable {}
}
