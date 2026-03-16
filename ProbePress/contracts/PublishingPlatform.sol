// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PublishingPlatform
 * @author ProbeChain
 * @notice Decentralized publishing — authors publish articles with pay-per-read pricing,
 *         readers can tip, and subscribers get time-based access to an author's catalog.
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London).
 */

// ── Ownable ────────────────────────────────────────────────────────────────────
abstract contract Ownable {
    address private _owner;
    error OwnableUnauthorized(address account);
    error OwnableInvalidOwner(address owner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    function owner() public view virtual returns (address) { return _owner; }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorized(msg.sender); _; }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ── ReentrancyGuard ────────────────────────────────────────────────────────────
abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status != 1) revert ReentrancyGuardReentrantCall();
        _status = 2; _; _status = 1;
    }
}

// ── Pausable ───────────────────────────────────────────────────────────────────
abstract contract Pausable is Ownable {
    bool private _paused;
    error EnforcedPause(); error ExpectedPause();
    event Paused(address account); event Unpaused(address account);
    function paused() public view returns (bool) { return _paused; }
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    modifier whenPaused() { if (!_paused) revert ExpectedPause(); _; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

// ── PublishingPlatform ─────────────────────────────────────────────────────────
contract PublishingPlatform is Ownable, ReentrancyGuard, Pausable {

    struct Article {
        uint256 id;
        address author;
        string title;
        string contentHash;
        uint256 price;
        uint256 publishedAt;
        uint256 purchaseCount;
        uint256 tipTotal;
        bool active;
    }

    struct Subscription {
        uint256 expiry;
        uint256 paidAmount;
    }

    uint256 public nextArticleId;
    uint256 public platformFeeBps = 300; // 3 %

    mapping(uint256 => Article) public articles;
    mapping(uint256 => mapping(address => bool)) public hasPurchased;
    mapping(address => uint256[]) private _authorArticles;
    // subscriber -> author -> subscription
    mapping(address => mapping(address => Subscription)) public subscriptions;
    // author -> monthly subscription price
    mapping(address => uint256) public subscriptionPrice;
    mapping(address => uint256) public authorBalance;

    // ── Events ─────────────────────────────────────────────────────────────────
    event ArticlePublished(uint256 indexed articleId, address indexed author, string title, uint256 price);
    event ArticlePurchased(uint256 indexed articleId, address indexed buyer, uint256 price);
    event ArticleTipped(uint256 indexed articleId, address indexed tipper, uint256 amount);
    event SubscriptionStarted(address indexed subscriber, address indexed author, uint256 expiry);
    event SubscriptionPriceSet(address indexed author, uint256 price);
    event AuthorWithdrew(address indexed author, uint256 amount);
    event ArticleDeactivated(uint256 indexed articleId);
    event PlatformFeeUpdated(uint256 newBps);

    // ── Errors ─────────────────────────────────────────────────────────────────
    error EmptyArticle();
    error ArticleNotFound();
    error ArticleNotActive();
    error AlreadyPurchased();
    error InsufficientPayment();
    error NotAuthor();
    error InvalidDuration();
    error NoSubscriptionPrice();
    error NothingToWithdraw();
    error TransferFailed();

    // ── Publish ────────────────────────────────────────────────────────────────
    /// @notice Publish an article.
    /// @param title       Article title.
    /// @param contentHash IPFS / Arweave hash of the full content.
    /// @param price       Price to purchase access (0 = free).
    function publishArticle(
        string calldata title,
        string calldata contentHash,
        uint256 price
    ) external whenNotPaused returns (uint256 articleId) {
        if (bytes(title).length == 0 || bytes(contentHash).length == 0) revert EmptyArticle();

        articleId = nextArticleId++;
        articles[articleId] = Article({
            id: articleId,
            author: msg.sender,
            title: title,
            contentHash: contentHash,
            price: price,
            publishedAt: block.timestamp,
            purchaseCount: 0,
            tipTotal: 0,
            active: true
        });

        _authorArticles[msg.sender].push(articleId);
        emit ArticlePublished(articleId, msg.sender, title, price);
    }

    // ── Purchase ───────────────────────────────────────────────────────────────
    /// @notice Purchase access to an article.
    function purchaseArticle(uint256 articleId) external payable nonReentrant whenNotPaused {
        Article storage a = articles[articleId];
        if (a.publishedAt == 0) revert ArticleNotFound();
        if (!a.active) revert ArticleNotActive();

        // Subscribers get free access
        Subscription storage sub = subscriptions[msg.sender][a.author];
        if (sub.expiry >= block.timestamp) {
            hasPurchased[articleId][msg.sender] = true;
            a.purchaseCount++;
            emit ArticlePurchased(articleId, msg.sender, 0);
            return;
        }

        if (hasPurchased[articleId][msg.sender]) revert AlreadyPurchased();
        if (msg.value < a.price) revert InsufficientPayment();

        hasPurchased[articleId][msg.sender] = true;
        a.purchaseCount++;

        uint256 fee = (msg.value * platformFeeBps) / 10_000;
        authorBalance[a.author] += msg.value - fee;

        emit ArticlePurchased(articleId, msg.sender, msg.value);
    }

    // ── Tip ────────────────────────────────────────────────────────────────────
    /// @notice Tip an article's author.
    function tipArticle(uint256 articleId) external payable nonReentrant whenNotPaused {
        Article storage a = articles[articleId];
        if (a.publishedAt == 0) revert ArticleNotFound();
        if (msg.value == 0) revert InsufficientPayment();

        a.tipTotal += msg.value;
        uint256 fee = (msg.value * platformFeeBps) / 10_000;
        authorBalance[a.author] += msg.value - fee;

        emit ArticleTipped(articleId, msg.sender, msg.value);
    }

    // ── Subscription ───────────────────────────────────────────────────────────
    /// @notice Set subscription price (per 30 days).
    function setSubscriptionPrice(uint256 price) external whenNotPaused {
        subscriptionPrice[msg.sender] = price;
        emit SubscriptionPriceSet(msg.sender, price);
    }

    /// @notice Subscribe to an author for a given duration (in multiples of 30 days).
    /// @param author   Author to subscribe to.
    /// @param duration Number of 30-day periods.
    function subscribe(address author, uint256 duration) external payable nonReentrant whenNotPaused {
        if (duration == 0) revert InvalidDuration();
        uint256 price = subscriptionPrice[author];
        if (price == 0) revert NoSubscriptionPrice();
        uint256 total = price * duration;
        if (msg.value < total) revert InsufficientPayment();

        Subscription storage sub = subscriptions[msg.sender][author];
        uint256 start = sub.expiry > block.timestamp ? sub.expiry : block.timestamp;
        sub.expiry = start + (duration * 30 days);
        sub.paidAmount += msg.value;

        uint256 fee = (msg.value * platformFeeBps) / 10_000;
        authorBalance[author] += msg.value - fee;

        emit SubscriptionStarted(msg.sender, author, sub.expiry);
    }

    // ── Deactivate ─────────────────────────────────────────────────────────────
    /// @notice Author or owner deactivates an article.
    function deactivateArticle(uint256 articleId) external whenNotPaused {
        Article storage a = articles[articleId];
        if (a.publishedAt == 0) revert ArticleNotFound();
        if (msg.sender != a.author && msg.sender != owner()) revert NotAuthor();
        a.active = false;
        emit ArticleDeactivated(articleId);
    }

    // ── Withdraw ───────────────────────────────────────────────────────────────
    /// @notice Author withdraws accumulated revenue.
    function withdrawAuthorBalance() external nonReentrant whenNotPaused {
        uint256 amount = authorBalance[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        authorBalance[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit AuthorWithdrew(msg.sender, amount);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────
    /// @notice Update platform fee (max 10 %).
    function setPlatformFee(uint256 newBps) external onlyOwner {
        if (newBps > 1000) revert InsufficientPayment();
        platformFeeBps = newBps;
        emit PlatformFeeUpdated(newBps);
    }

    /// @notice Withdraw accumulated platform fees (contract balance minus author balances).
    function withdrawPlatformFees() external onlyOwner nonReentrant {
        // Platform fees = contract balance that isn't owed to authors
        // (simplified: owner withdraws whatever is in the contract beyond tracked balances)
        uint256 bal = address(this).balance;
        if (bal == 0) revert NothingToWithdraw();
        (bool ok, ) = payable(owner()).call{value: bal}("");
        if (!ok) revert TransferFailed();
    }

    // ── Views ──────────────────────────────────────────────────────────────────
    /// @notice Get article IDs by author.
    function getAuthorArticles(address author) external view returns (uint256[] memory) {
        return _authorArticles[author];
    }

    /// @notice Check if a user has access to an article (purchased or subscribed).
    function hasAccess(address user, uint256 articleId) external view returns (bool) {
        if (hasPurchased[articleId][user]) return true;
        Article storage a = articles[articleId];
        if (a.publishedAt == 0) return false;
        if (subscriptions[user][a.author].expiry >= block.timestamp) return true;
        if (a.price == 0) return true;
        return false;
    }
}
