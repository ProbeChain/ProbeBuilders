// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NewsletterDAO
 * @author ProbeChain Team
 * @notice Decentralized newsletter subscription platform with publisher rewards
 * @dev Supports paid subscriptions, edition publishing, and publisher revenue
 */
contract NewsletterDAO {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "NewsletterDAO: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "NewsletterDAO: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _guardStatus = 1;
    modifier nonReentrant() {
        require(_guardStatus == 1, "NewsletterDAO: reentrant call");
        _guardStatus = 2;
        _;
        _guardStatus = 1;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "NewsletterDAO: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums ──────────────────────────────────────────────────────────
    enum Frequency { Daily, Weekly, Biweekly, Monthly }

    // ─── Structs ────────────────────────────────────────────────────────
    struct Newsletter {
        uint256 id;
        address publisher;
        string name;
        Frequency frequency;
        uint256 subscriptionPrice;
        uint256 subscriberCount;
        uint256 editionCount;
        uint256 revenue;
        uint256 createdAt;
        bool active;
    }

    struct Edition {
        uint256 id;
        uint256 newsletterId;
        bytes32 contentHash;
        uint256 publishedAt;
    }

    struct Subscription {
        bool active;
        uint256 subscribedAt;
        uint256 expiresAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public newsletterCount;
    uint256 public editionCount;
    uint256 public platformFeePercent = 5;
    uint256 public collectedFees;
    uint256 public constant SUBSCRIPTION_DURATION = 30 days;

    mapping(uint256 => Newsletter) public newsletters;
    mapping(uint256 => Edition) public editions;
    mapping(uint256 => uint256[]) public newsletterEditions;
    mapping(uint256 => mapping(address => Subscription)) public subscriptions;
    mapping(address => uint256[]) public publisherNewsletters;
    mapping(address => uint256[]) public userSubscriptions;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a newsletter is created
    event NewsletterCreated(uint256 indexed newsletterId, address indexed publisher, string name, Frequency frequency);
    /// @notice Emitted when someone subscribes
    event Subscribed(uint256 indexed newsletterId, address indexed subscriber, uint256 expiresAt);
    /// @notice Emitted when an edition is published
    event EditionPublished(uint256 indexed editionId, uint256 indexed newsletterId, bytes32 contentHash);
    /// @notice Emitted when someone unsubscribes
    event Unsubscribed(uint256 indexed newsletterId, address indexed subscriber);
    /// @notice Emitted when publisher claims rewards
    event RewardsClaimed(address indexed publisher, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Create a new newsletter
     * @param name Newsletter name
     * @param frequency Publication frequency
     * @param subscriptionPrice Price per subscription period in wei
     */
    function createNewsletter(
        string calldata name,
        Frequency frequency,
        uint256 subscriptionPrice
    ) external whenNotPaused {
        require(bytes(name).length > 0 && bytes(name).length <= 64, "NewsletterDAO: invalid name");

        newsletterCount++;
        newsletters[newsletterCount] = Newsletter({
            id: newsletterCount,
            publisher: msg.sender,
            name: name,
            frequency: frequency,
            subscriptionPrice: subscriptionPrice,
            subscriberCount: 0,
            editionCount: 0,
            revenue: 0,
            createdAt: block.timestamp,
            active: true
        });

        publisherNewsletters[msg.sender].push(newsletterCount);
        emit NewsletterCreated(newsletterCount, msg.sender, name, frequency);
    }

    /**
     * @notice Subscribe to a newsletter
     * @param newsletterId Newsletter to subscribe to
     */
    function subscribe(uint256 newsletterId) external payable whenNotPaused nonReentrant {
        Newsletter storage nl = newsletters[newsletterId];
        require(nl.active, "NewsletterDAO: not active");
        require(msg.value >= nl.subscriptionPrice, "NewsletterDAO: insufficient payment");

        Subscription storage sub = subscriptions[newsletterId][msg.sender];
        uint256 startTime = sub.expiresAt > block.timestamp ? sub.expiresAt : block.timestamp;

        if (!sub.active) {
            nl.subscriberCount++;
            userSubscriptions[msg.sender].push(newsletterId);
        }

        sub.active = true;
        sub.subscribedAt = block.timestamp;
        sub.expiresAt = startTime + SUBSCRIPTION_DURATION;

        if (nl.subscriptionPrice > 0) {
            uint256 fee = (msg.value * platformFeePercent) / 100;
            collectedFees += fee;
            nl.revenue += msg.value - fee;
        }

        emit Subscribed(newsletterId, msg.sender, sub.expiresAt);
    }

    /**
     * @notice Publish a new edition
     * @param newsletterId Newsletter to publish for
     * @param contentHash IPFS hash of the edition content
     */
    function publishEdition(uint256 newsletterId, bytes32 contentHash) external whenNotPaused {
        Newsletter storage nl = newsletters[newsletterId];
        require(msg.sender == nl.publisher, "NewsletterDAO: not publisher");
        require(nl.active, "NewsletterDAO: not active");
        require(contentHash != bytes32(0), "NewsletterDAO: empty content");

        editionCount++;
        editions[editionCount] = Edition({
            id: editionCount,
            newsletterId: newsletterId,
            contentHash: contentHash,
            publishedAt: block.timestamp
        });

        nl.editionCount++;
        newsletterEditions[newsletterId].push(editionCount);

        emit EditionPublished(editionCount, newsletterId, contentHash);
    }

    /**
     * @notice Unsubscribe from a newsletter
     * @param newsletterId Newsletter to unsubscribe from
     */
    function unsubscribe(uint256 newsletterId) external {
        Subscription storage sub = subscriptions[newsletterId][msg.sender];
        require(sub.active, "NewsletterDAO: not subscribed");

        sub.active = false;
        newsletters[newsletterId].subscriberCount--;

        emit Unsubscribed(newsletterId, msg.sender);
    }

    /**
     * @notice Claim accumulated publisher rewards
     */
    function claimPublisherRewards() external nonReentrant {
        uint256 total = 0;
        uint256[] storage pubNLs = publisherNewsletters[msg.sender];

        for (uint256 i = 0; i < pubNLs.length; i++) {
            Newsletter storage nl = newsletters[pubNLs[i]];
            total += nl.revenue;
            nl.revenue = 0;
        }

        require(total > 0, "NewsletterDAO: no rewards");
        (bool success, ) = payable(msg.sender).call{value: total}("");
        require(success, "NewsletterDAO: payment failed");

        emit RewardsClaimed(msg.sender, total);
    }

    /**
     * @notice Withdraw platform fees
     * @param to Recipient
     */
    function withdrawFees(address to) external onlyOwner nonReentrant {
        uint256 amount = collectedFees;
        collectedFees = 0;
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "NewsletterDAO: withdrawal failed");
    }

    /**
     * @notice Check subscription status
     * @param newsletterId Newsletter ID
     * @param subscriber Subscriber address
     * @return active Whether subscription is active
     * @return expiresAt Expiration timestamp
     */
    function isSubscribed(uint256 newsletterId, address subscriber) external view returns (bool active, uint256 expiresAt) {
        Subscription storage sub = subscriptions[newsletterId][subscriber];
        return (sub.active && sub.expiresAt > block.timestamp, sub.expiresAt);
    }

    /**
     * @notice Get editions for a newsletter
     * @param newsletterId Newsletter ID
     * @return editionIds Array of edition IDs
     */
    function getEditions(uint256 newsletterId) external view returns (uint256[] memory editionIds) {
        return newsletterEditions[newsletterId];
    }
}
