// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DashboardRegistry
 * @author ProbeChain
 * @notice Analytics dashboard registry with creation, publishing, subscriptions, and creator monetization
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London)
 */

// --- Inline Ownable ---
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorized(address account);
    error OwnableInvalidOwner(address owner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorized(msg.sender);
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(newOwner);
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// --- Inline ReentrancyGuard ---
abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardReentrantCall();
        _status = 2;
        _;
        _status = 1;
    }
}

// --- Inline Pausable ---
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();

    modifier whenNotPaused() {
        if (_paused) revert ContractPaused();
        _;
    }

    function paused() public view returns (bool) { return _paused; }

    function pause() external onlyOwner {
        if (_paused) revert ContractPaused();
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        if (!_paused) revert ContractNotPaused();
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract DashboardRegistry is Ownable, ReentrancyGuard, Pausable {
    // --- Types ---
    enum DashboardStatus { Draft, Published, Archived }

    struct Dashboard {
        uint256 id;
        address creator;
        string name;
        string description;
        bytes32[] queryHashes;
        uint256 price;
        DashboardStatus status;
        uint256 subscriberCount;
        uint256 totalRating;
        uint256 ratingCount;
        uint256 totalEarned;
        uint256 createdAt;
        uint256 publishedAt;
    }

    struct Subscription {
        address subscriber;
        uint256 dashboardId;
        uint256 subscribedAt;
        uint256 expiresAt;
        bool active;
    }

    // --- State ---
    uint256 public nextDashboardId;
    uint256 public constant PLATFORM_FEE_BPS = 250; // 2.5%
    uint256 public constant SUBSCRIPTION_DURATION = 30 days;

    mapping(uint256 => Dashboard) public dashboards;
    mapping(uint256 => mapping(address => Subscription)) public subscriptions;
    mapping(uint256 => mapping(address => bool)) public hasRated;
    mapping(address => uint256[]) private _creatorDashboards;
    mapping(address => uint256[]) private _userSubscriptions;
    mapping(address => uint256) public creatorEarnings;
    uint256 public platformFees;

    // --- Events ---
    event DashboardCreated(uint256 indexed dashboardId, address indexed creator, string name);
    event DashboardPublished(uint256 indexed dashboardId, uint256 price);
    event DashboardArchived(uint256 indexed dashboardId);
    event DashboardSubscribed(uint256 indexed dashboardId, address indexed subscriber, uint256 price, uint256 expiresAt);
    event DashboardRated(uint256 indexed dashboardId, address indexed rater, uint8 rating);
    event EarningsWithdrawn(address indexed creator, uint256 amount);
    event FeesWithdrawn(address indexed to, uint256 amount);
    event DashboardUpdated(uint256 indexed dashboardId, string name);

    // --- Errors ---
    error DashboardNotFound();
    error NotDashboardCreator();
    error DashboardNotPublished();
    error DashboardNotDraft();
    error AlreadySubscribed();
    error NotSubscribed();
    error AlreadyRated();
    error InvalidRating();
    error InsufficientPayment();
    error NothingToWithdraw();
    error InvalidPrice();
    error EmptyQueryHashes();

    // --- Dashboard Management ---

    /// @notice Create a new analytics dashboard
    /// @param name Dashboard name
    /// @param queryHashes Array of query hashes that make up the dashboard
    /// @param description Dashboard description
    /// @return dashboardId The ID of the created dashboard
    function createDashboard(
        string calldata name,
        bytes32[] calldata queryHashes,
        string calldata description
    ) external whenNotPaused returns (uint256 dashboardId) {
        if (queryHashes.length == 0) revert EmptyQueryHashes();

        dashboardId = nextDashboardId++;

        Dashboard storage d = dashboards[dashboardId];
        d.id = dashboardId;
        d.creator = msg.sender;
        d.name = name;
        d.description = description;
        d.queryHashes = queryHashes;
        d.price = 0;
        d.status = DashboardStatus.Draft;
        d.subscriberCount = 0;
        d.totalRating = 0;
        d.ratingCount = 0;
        d.totalEarned = 0;
        d.createdAt = block.timestamp;
        d.publishedAt = 0;

        _creatorDashboards[msg.sender].push(dashboardId);
        emit DashboardCreated(dashboardId, msg.sender, name);
    }

    /// @notice Publish a draft dashboard with a subscription price
    /// @param dashboardId The dashboard to publish
    /// @param price Subscription price in wei (0 for free)
    function publishDashboard(uint256 dashboardId, uint256 price) external whenNotPaused {
        Dashboard storage d = dashboards[dashboardId];
        if (d.creator == address(0)) revert DashboardNotFound();
        if (d.creator != msg.sender) revert NotDashboardCreator();
        if (d.status != DashboardStatus.Draft) revert DashboardNotDraft();

        d.price = price;
        d.status = DashboardStatus.Published;
        d.publishedAt = block.timestamp;

        emit DashboardPublished(dashboardId, price);
    }

    /// @notice Update dashboard metadata
    /// @param dashboardId The dashboard to update
    /// @param name New name
    /// @param description New description
    function updateDashboard(
        uint256 dashboardId,
        string calldata name,
        string calldata description
    ) external whenNotPaused {
        Dashboard storage d = dashboards[dashboardId];
        if (d.creator != msg.sender) revert NotDashboardCreator();
        d.name = name;
        d.description = description;
        emit DashboardUpdated(dashboardId, name);
    }

    /// @notice Archive a dashboard
    function archiveDashboard(uint256 dashboardId) external {
        Dashboard storage d = dashboards[dashboardId];
        if (d.creator != msg.sender) revert NotDashboardCreator();
        d.status = DashboardStatus.Archived;
        emit DashboardArchived(dashboardId);
    }

    // --- Subscriptions ---

    /// @notice Subscribe to a published dashboard
    /// @param dashboardId The dashboard to subscribe to
    function subscribeToDashboard(uint256 dashboardId) external payable nonReentrant whenNotPaused {
        Dashboard storage d = dashboards[dashboardId];
        if (d.creator == address(0)) revert DashboardNotFound();
        if (d.status != DashboardStatus.Published) revert DashboardNotPublished();

        Subscription storage sub = subscriptions[dashboardId][msg.sender];

        // Allow re-subscription if expired
        if (sub.active && block.timestamp < sub.expiresAt) revert AlreadySubscribed();

        if (d.price > 0) {
            if (msg.value < d.price) revert InsufficientPayment();

            uint256 fee = (d.price * PLATFORM_FEE_BPS) / 10000;
            platformFees += fee;
            uint256 creatorPayment = d.price - fee;
            creatorEarnings[d.creator] += creatorPayment;
            d.totalEarned += creatorPayment;
        }

        uint256 expiresAt = block.timestamp + SUBSCRIPTION_DURATION;

        subscriptions[dashboardId][msg.sender] = Subscription({
            subscriber: msg.sender,
            dashboardId: dashboardId,
            subscribedAt: block.timestamp,
            expiresAt: expiresAt,
            active: true
        });

        if (!sub.active) {
            d.subscriberCount++;
            _userSubscriptions[msg.sender].push(dashboardId);
        }

        emit DashboardSubscribed(dashboardId, msg.sender, d.price, expiresAt);
    }

    /// @notice Check if a user has an active subscription
    /// @param dashboardId The dashboard to check
    /// @param user The user address
    /// @return Whether the subscription is active
    function isSubscribed(uint256 dashboardId, address user) external view returns (bool) {
        Subscription storage sub = subscriptions[dashboardId][user];
        return sub.active && block.timestamp < sub.expiresAt;
    }

    // --- Ratings ---

    /// @notice Rate a dashboard (subscribers only)
    /// @param dashboardId The dashboard to rate
    /// @param rating Rating from 1 to 5
    function rateDashboard(uint256 dashboardId, uint8 rating) external whenNotPaused {
        if (rating < 1 || rating > 5) revert InvalidRating();

        Dashboard storage d = dashboards[dashboardId];
        if (d.creator == address(0)) revert DashboardNotFound();

        Subscription storage sub = subscriptions[dashboardId][msg.sender];
        if (!sub.active) revert NotSubscribed();
        if (hasRated[dashboardId][msg.sender]) revert AlreadyRated();

        hasRated[dashboardId][msg.sender] = true;
        d.totalRating += rating;
        d.ratingCount++;

        emit DashboardRated(dashboardId, msg.sender, rating);
    }

    /// @notice Get average rating for a dashboard (scaled by 100)
    function getAverageRating(uint256 dashboardId) external view returns (uint256) {
        Dashboard storage d = dashboards[dashboardId];
        if (d.ratingCount == 0) return 0;
        return (d.totalRating * 100) / d.ratingCount;
    }

    // --- Withdrawals ---

    /// @notice Creator withdraws accumulated earnings
    function withdrawEarnings() external nonReentrant {
        uint256 amount = creatorEarnings[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        creatorEarnings[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit EarningsWithdrawn(msg.sender, amount);
    }

    /// @notice Withdraw platform fees
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = platformFees;
        if (amount == 0) revert NothingToWithdraw();
        platformFees = 0;
        payable(owner()).transfer(amount);
        emit FeesWithdrawn(owner(), amount);
    }

    // --- View Helpers ---

    /// @notice Get dashboards created by an address
    function getCreatorDashboards(address creator) external view returns (uint256[] memory) {
        return _creatorDashboards[creator];
    }

    /// @notice Get user subscriptions
    function getUserSubscriptions(address user) external view returns (uint256[] memory) {
        return _userSubscriptions[user];
    }

    /// @notice Get query hashes for a dashboard
    function getDashboardQueries(uint256 dashboardId) external view returns (bytes32[] memory) {
        return dashboards[dashboardId].queryHashes;
    }
}
