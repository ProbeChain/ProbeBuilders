// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title SkillMarketplace — Agent skill marketplace for ProbeChain
/// @author ProbeBuilders
/// @notice List, purchase, and rate AI agent skills on-chain
/// @dev Implements ReentrancyGuard and Ownable inline. Rydberg Testnet (Chain ID 8004).
contract SkillMarketplace {
    // ─── ReentrancyGuard ─────────────────────────────────────────────────
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_status != _ENTERED, "SkillMarketplace: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // ─── Enums & Structs ─────────────────────────────────────────────────
    enum SkillStatus { Active, Suspended, Delisted }

    struct Skill {
        uint256 id;
        uint256 agentId;
        address seller;
        string description;
        uint256 price;
        SkillStatus status;
        uint256 totalPurchases;
        uint256 ratingSum;
        uint256 ratingCount;
        uint256 listedAt;
    }

    struct Purchase {
        uint256 skillId;
        address buyer;
        uint256 paidAmount;
        uint8 rating; // 0 = not rated, 1-5
        uint256 purchasedAt;
    }

    // ─── State ───────────────────────────────────────────────────────────
    address public owner;
    bool public paused;
    uint256 public platformFeeBps = 250; // 2.5%
    uint256 public constant MAX_FEE_BPS = 1000; // 10%

    uint256 private _nextSkillId = 1;
    uint256 private _nextPurchaseId = 1;

    mapping(uint256 => Skill) public skills;
    mapping(uint256 => Purchase) public purchases;
    mapping(address => uint256) public pendingWithdrawals;
    mapping(address => uint256[]) private _sellerSkills;
    mapping(address => uint256[]) private _buyerPurchases;
    // buyer => skillId => purchaseId (latest)
    mapping(address => mapping(uint256 => uint256)) private _buyerSkillPurchase;

    uint256 public totalSkillsListed;

    // ─── Events ──────────────────────────────────────────────────────────
    event SkillListed(uint256 indexed skillId, uint256 indexed agentId, address indexed seller, uint256 price, string description);
    event SkillPurchased(uint256 indexed skillId, uint256 indexed purchaseId, address indexed buyer, uint256 amount);
    event SkillRated(uint256 indexed skillId, uint256 indexed purchaseId, address indexed buyer, uint8 rating);
    event SkillUpdated(uint256 indexed skillId, uint256 newPrice, string newDescription);
    event SkillDelisted(uint256 indexed skillId);
    event EarningsWithdrawn(address indexed seller, uint256 amount);
    event PlatformFeeUpdated(uint256 oldBps, uint256 newBps);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "SkillMarketplace: not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "SkillMarketplace: paused");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    /// @notice Deploy marketplace
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ──────────────────────────────────────────────────

    /// @notice List a skill for sale
    /// @param agentId The agent offering this skill
    /// @param price Price in wei
    /// @param description Skill description
    /// @return skillId The new skill ID
    function listSkill(
        uint256 agentId,
        uint256 price,
        string calldata description
    ) external whenNotPaused returns (uint256 skillId) {
        require(price > 0, "SkillMarketplace: price must be > 0");
        require(bytes(description).length > 0 && bytes(description).length <= 1024, "SkillMarketplace: invalid description");

        skillId = _nextSkillId++;
        skills[skillId] = Skill({
            id: skillId,
            agentId: agentId,
            seller: msg.sender,
            description: description,
            price: price,
            status: SkillStatus.Active,
            totalPurchases: 0,
            ratingSum: 0,
            ratingCount: 0,
            listedAt: block.timestamp
        });

        _sellerSkills[msg.sender].push(skillId);
        totalSkillsListed++;

        emit SkillListed(skillId, agentId, msg.sender, price, description);
    }

    /// @notice Purchase a skill
    /// @param skillId The skill to purchase
    /// @return purchaseId The purchase receipt ID
    function purchaseSkill(uint256 skillId) external payable whenNotPaused nonReentrant returns (uint256 purchaseId) {
        Skill storage skill = skills[skillId];
        require(skill.listedAt != 0, "SkillMarketplace: skill not found");
        require(skill.status == SkillStatus.Active, "SkillMarketplace: skill not active");
        require(msg.sender != skill.seller, "SkillMarketplace: cannot buy own skill");
        require(msg.value >= skill.price, "SkillMarketplace: insufficient payment");

        uint256 fee = (skill.price * platformFeeBps) / 10000;
        uint256 sellerAmount = skill.price - fee;

        pendingWithdrawals[skill.seller] += sellerAmount;
        pendingWithdrawals[owner] += fee;

        // Refund excess
        if (msg.value > skill.price) {
            (bool refundOk, ) = payable(msg.sender).call{value: msg.value - skill.price}("");
            require(refundOk, "SkillMarketplace: refund failed");
        }

        purchaseId = _nextPurchaseId++;
        purchases[purchaseId] = Purchase({
            skillId: skillId,
            buyer: msg.sender,
            paidAmount: skill.price,
            rating: 0,
            purchasedAt: block.timestamp
        });

        skill.totalPurchases++;
        _buyerPurchases[msg.sender].push(purchaseId);
        _buyerSkillPurchase[msg.sender][skillId] = purchaseId;

        emit SkillPurchased(skillId, purchaseId, msg.sender, skill.price);
    }

    /// @notice Rate a purchased skill (1-5 stars)
    /// @param purchaseId The purchase to rate
    /// @param rating Rating from 1 to 5
    function rateSkill(uint256 purchaseId, uint8 rating) external {
        Purchase storage p = purchases[purchaseId];
        require(p.purchasedAt != 0, "SkillMarketplace: purchase not found");
        require(p.buyer == msg.sender, "SkillMarketplace: not the buyer");
        require(p.rating == 0, "SkillMarketplace: already rated");
        require(rating >= 1 && rating <= 5, "SkillMarketplace: rating 1-5");

        p.rating = rating;

        Skill storage skill = skills[p.skillId];
        skill.ratingSum += rating;
        skill.ratingCount++;

        emit SkillRated(p.skillId, purchaseId, msg.sender, rating);
    }

    /// @notice Withdraw accumulated earnings
    function withdrawEarnings() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "SkillMarketplace: nothing to withdraw");

        pendingWithdrawals[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "SkillMarketplace: transfer failed");

        emit EarningsWithdrawn(msg.sender, amount);
    }

    /// @notice Update skill price and description (seller only)
    /// @param skillId The skill to update
    /// @param newPrice New price (0 = keep current)
    /// @param newDescription New description (empty = keep current)
    function updateSkill(uint256 skillId, uint256 newPrice, string calldata newDescription) external {
        Skill storage skill = skills[skillId];
        require(skill.seller == msg.sender, "SkillMarketplace: not seller");
        require(skill.status != SkillStatus.Delisted, "SkillMarketplace: delisted");

        if (newPrice > 0) skill.price = newPrice;
        if (bytes(newDescription).length > 0) skill.description = newDescription;

        emit SkillUpdated(skillId, skill.price, skill.description);
    }

    /// @notice Delist a skill (seller only)
    /// @param skillId The skill to delist
    function delistSkill(uint256 skillId) external {
        Skill storage skill = skills[skillId];
        require(skill.seller == msg.sender, "SkillMarketplace: not seller");
        skill.status = SkillStatus.Delisted;
        emit SkillDelisted(skillId);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Get average rating for a skill (x100 for precision)
    /// @param skillId The skill to query
    /// @return avgRating Average rating multiplied by 100 (e.g., 450 = 4.50)
    function getAverageRating(uint256 skillId) external view returns (uint256 avgRating) {
        Skill storage skill = skills[skillId];
        if (skill.ratingCount == 0) return 0;
        avgRating = (skill.ratingSum * 100) / skill.ratingCount;
    }

    /// @notice Get skills listed by a seller
    function getSellerSkills(address seller) external view returns (uint256[] memory) {
        return _sellerSkills[seller];
    }

    /// @notice Get purchases by a buyer
    function getBuyerPurchases(address buyer) external view returns (uint256[] memory) {
        return _buyerPurchases[buyer];
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    /// @notice Update platform fee (max 10%)
    function setPlatformFee(uint256 newBps) external onlyOwner {
        require(newBps <= MAX_FEE_BPS, "SkillMarketplace: fee too high");
        uint256 old = platformFeeBps;
        platformFeeBps = newBps;
        emit PlatformFeeUpdated(old, newBps);
    }

    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "SkillMarketplace: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
