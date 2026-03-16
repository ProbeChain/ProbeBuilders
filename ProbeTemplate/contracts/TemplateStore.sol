// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TemplateStore
 * @author ProbeChain Team
 * @notice Dapp template marketplace for publishing and using project templates
 * @dev Categories: DeFi, NFT, DAO, GameFi with pricing and rating system
 */
contract TemplateStore {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "TemplateStore: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "TemplateStore: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _guardStatus = 1;
    modifier nonReentrant() {
        require(_guardStatus == 1, "TemplateStore: reentrant call");
        _guardStatus = 2;
        _;
        _guardStatus = 1;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "TemplateStore: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums ──────────────────────────────────────────────────────────
    enum Category { DeFi, NFT, DAO, GameFi }

    // ─── Structs ────────────────────────────────────────────────────────
    struct Template {
        uint256 id;
        string name;
        Category category;
        bytes32 bytecodeHash;
        bytes32 docsHash;
        uint256 price;
        address publisher;
        uint256 useCount;
        uint256 totalRating;
        uint256 ratingCount;
        uint256 revenue;
        uint256 createdAt;
        bool featured;
        bool active;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public templateCount;
    uint256 public platformFeePercent = 5;
    uint256 public collectedFees;

    mapping(uint256 => Template) public templates;
    mapping(uint256 => mapping(address => bool)) public hasRated;
    mapping(uint256 => mapping(address => bool)) public hasUsed;
    mapping(uint8 => uint256[]) public categoryTemplates;
    mapping(address => uint256[]) public publisherTemplates;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a new template is published
    event TemplatePublished(uint256 indexed templateId, string name, Category category, uint256 price, address indexed publisher);
    /// @notice Emitted when a template is used/purchased
    event TemplateUsed(uint256 indexed templateId, address indexed user, uint256 pricePaid);
    /// @notice Emitted when a template is rated
    event TemplateRated(uint256 indexed templateId, address indexed rater, uint256 score);
    /// @notice Emitted when a template is featured/unfeatured
    event TemplateFeatured(uint256 indexed templateId, bool featured);
    /// @notice Emitted when publisher withdraws revenue
    event RevenueWithdrawn(address indexed publisher, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Publish a new Dapp template
     * @param name Template name
     * @param category Template category (0=DeFi, 1=NFT, 2=DAO, 3=GameFi)
     * @param bytecodeHash Hash of the template bytecode
     * @param docsHash Hash of the documentation
     * @param price Price in wei to use the template (0 for free)
     */
    function publishTemplate(
        string calldata name,
        Category category,
        bytes32 bytecodeHash,
        bytes32 docsHash,
        uint256 price
    ) external whenNotPaused {
        require(bytes(name).length > 0 && bytes(name).length <= 64, "TemplateStore: invalid name");
        require(bytecodeHash != bytes32(0), "TemplateStore: empty bytecode hash");

        templateCount++;
        templates[templateCount] = Template({
            id: templateCount,
            name: name,
            category: category,
            bytecodeHash: bytecodeHash,
            docsHash: docsHash,
            price: price,
            publisher: msg.sender,
            useCount: 0,
            totalRating: 0,
            ratingCount: 0,
            revenue: 0,
            createdAt: block.timestamp,
            featured: false,
            active: true
        });

        categoryTemplates[uint8(category)].push(templateCount);
        publisherTemplates[msg.sender].push(templateCount);

        emit TemplatePublished(templateCount, name, category, price, msg.sender);
    }

    /**
     * @notice Use/purchase a template
     * @param templateId ID of the template to use
     */
    function useTemplate(uint256 templateId) external payable whenNotPaused nonReentrant {
        Template storage t = templates[templateId];
        require(t.active, "TemplateStore: template not active");
        require(msg.value >= t.price, "TemplateStore: insufficient payment");
        require(!hasUsed[templateId][msg.sender], "TemplateStore: already used");

        hasUsed[templateId][msg.sender] = true;
        t.useCount++;

        if (t.price > 0) {
            uint256 fee = (msg.value * platformFeePercent) / 100;
            collectedFees += fee;
            t.revenue += msg.value - fee;
        }

        emit TemplateUsed(templateId, msg.sender, msg.value);
    }

    /**
     * @notice Rate a template (1-5 stars)
     * @param templateId ID of the template
     * @param score Rating score (1-5)
     */
    function rateTemplate(uint256 templateId, uint256 score) external whenNotPaused {
        require(score >= 1 && score <= 5, "TemplateStore: invalid score");
        require(hasUsed[templateId][msg.sender], "TemplateStore: must use first");
        require(!hasRated[templateId][msg.sender], "TemplateStore: already rated");

        Template storage t = templates[templateId];
        hasRated[templateId][msg.sender] = true;
        t.totalRating += score;
        t.ratingCount++;

        emit TemplateRated(templateId, msg.sender, score);
    }

    /**
     * @notice Get featured templates (up to 10)
     * @return ids Array of featured template IDs
     */
    function getFeaturedTemplates() external view returns (uint256[] memory ids) {
        uint256 count = 0;
        for (uint256 i = 1; i <= templateCount && count < 10; i++) {
            if (templates[i].featured && templates[i].active) count++;
        }

        ids = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= templateCount && idx < count; i++) {
            if (templates[i].featured && templates[i].active) {
                ids[idx] = i;
                idx++;
            }
        }
    }

    /**
     * @notice Set featured status for a template
     * @param templateId Template ID
     * @param featured Whether to feature it
     */
    function setFeatured(uint256 templateId, bool featured) external onlyOwner {
        templates[templateId].featured = featured;
        emit TemplateFeatured(templateId, featured);
    }

    /**
     * @notice Publisher withdraws accumulated revenue
     */
    function withdrawRevenue() external nonReentrant {
        uint256 total = 0;
        uint256[] storage pubTemplates = publisherTemplates[msg.sender];

        for (uint256 i = 0; i < pubTemplates.length; i++) {
            Template storage t = templates[pubTemplates[i]];
            total += t.revenue;
            t.revenue = 0;
        }

        require(total > 0, "TemplateStore: no revenue");
        (bool success, ) = payable(msg.sender).call{value: total}("");
        require(success, "TemplateStore: withdrawal failed");

        emit RevenueWithdrawn(msg.sender, total);
    }

    /**
     * @notice Withdraw platform fees
     * @param to Recipient address
     */
    function withdrawFees(address to) external onlyOwner nonReentrant {
        uint256 amount = collectedFees;
        collectedFees = 0;
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "TemplateStore: withdrawal failed");
    }

    /**
     * @notice Get templates by category
     * @param category Category enum value
     * @return ids Array of template IDs
     */
    function getByCategory(Category category) external view returns (uint256[] memory ids) {
        return categoryTemplates[uint8(category)];
    }

    /**
     * @notice Get average rating for a template
     * @param templateId Template ID
     * @return avg Average rating (multiplied by 100 for precision)
     */
    function getAverageRating(uint256 templateId) external view returns (uint256 avg) {
        Template storage t = templates[templateId];
        if (t.ratingCount == 0) return 0;
        return (t.totalRating * 100) / t.ratingCount;
    }
}
