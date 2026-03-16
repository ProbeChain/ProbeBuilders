// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title EventLogger
 * @author ProbeChain Rydberg Testnet
 * @notice Immutable event logging system with categories, severity levels, and subscriptions
 * @dev Log events on-chain by category/severity, subscribe to categories for notifications
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

contract EventLogger is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum Severity { Info, Warning, Error, Critical }

    // ---------- Structs ----------
    struct LogEntry {
        uint256 id;
        address logger;
        string category;
        Severity severity;
        string message;
        bytes32 dataHash;
        uint256 blockNumber;
        uint256 timestamp;
    }

    struct CategoryInfo {
        string name;
        uint256 entryCount;
        uint256 subscriberCount;
        uint256 subscriptionPrice;
        bool active;
    }

    struct Subscription {
        address subscriber;
        string category;
        uint256 subscribedAt;
        uint256 expiresAt;
        bool active;
    }

    // ---------- State ----------
    uint256 public nextLogId;
    uint256 public nextSubscriptionId;
    uint256 public defaultSubscriptionDuration;

    mapping(uint256 => LogEntry) public logs;
    mapping(bytes32 => CategoryInfo) public categories;
    mapping(bytes32 => uint256[]) public categoryLogIds;
    mapping(bytes32 => bool) public categoryExists;
    mapping(uint256 => Subscription) public subscriptions;
    mapping(address => uint256[]) public userSubscriptions;
    mapping(address => bool) public authorizedLoggers;

    // Severity counters
    mapping(Severity => uint256) public severityCounts;
    uint256 public totalLogs;

    // ---------- Events ----------
    /// @notice Emitted when an event is logged
    event EventLogged(uint256 indexed logId, address indexed logger, string category, Severity severity, string message);
    /// @notice Emitted when a critical event is logged (separate for easy filtering)
    event CriticalEventLogged(uint256 indexed logId, string category, string message, bytes32 dataHash);
    /// @notice Emitted when a category subscription is purchased
    event CategorySubscribed(uint256 indexed subscriptionId, address indexed subscriber, string category, uint256 duration);
    /// @notice Emitted when a new category is created
    event CategoryCreated(string category, uint256 subscriptionPrice);
    /// @notice Emitted when a logger is authorized
    event LoggerAuthorized(address indexed logger);

    // ---------- Constructor ----------
    constructor(uint256 _defaultSubDuration) Ownable() ReentrancyGuard() Pausable() {
        defaultSubscriptionDuration = _defaultSubDuration;
        nextLogId = 1;
        nextSubscriptionId = 1;
    }

    /**
     * @notice Authorize a logger
     * @param logger Address to authorize
     */
    function authorizeLogger(address logger) external onlyOwner {
        require(logger != address(0), "Zero address");
        authorizedLoggers[logger] = true;
        emit LoggerAuthorized(logger);
    }

    /**
     * @notice Revoke logger authorization
     * @param logger Address to revoke
     */
    function revokeLogger(address logger) external onlyOwner {
        authorizedLoggers[logger] = false;
    }

    /**
     * @notice Create a log category
     * @param category Category name
     * @param subscriptionPrice Subscription price in wei
     */
    function createCategory(string calldata category, uint256 subscriptionPrice) external onlyOwner {
        bytes32 catHash = keccak256(abi.encodePacked(category));
        require(!categoryExists[catHash], "Category already exists");

        categoryExists[catHash] = true;
        CategoryInfo storage ci = categories[catHash];
        ci.name = category;
        ci.subscriptionPrice = subscriptionPrice;
        ci.active = true;

        emit CategoryCreated(category, subscriptionPrice);
    }

    /**
     * @notice Log an event
     * @param category Event category
     * @param severity Severity level
     * @param message Event message
     * @param dataHash Optional hash of additional data
     * @return logId The log entry ID
     */
    function logEvent(string calldata category, Severity severity, string calldata message, bytes32 dataHash)
        external
        whenNotPaused
        returns (uint256 logId)
    {
        require(authorizedLoggers[msg.sender] || msg.sender == owner(), "Not authorized logger");
        bytes32 catHash = keccak256(abi.encodePacked(category));
        require(categoryExists[catHash], "Category does not exist");
        require(bytes(message).length > 0 && bytes(message).length <= 512, "Invalid message length");

        logId = nextLogId++;
        LogEntry storage entry = logs[logId];
        entry.id = logId;
        entry.logger = msg.sender;
        entry.category = category;
        entry.severity = severity;
        entry.message = message;
        entry.dataHash = dataHash;
        entry.blockNumber = block.number;
        entry.timestamp = block.timestamp;

        categoryLogIds[catHash].push(logId);
        categories[catHash].entryCount++;
        severityCounts[severity]++;
        totalLogs++;

        emit EventLogged(logId, msg.sender, category, severity, message);

        if (severity == Severity.Critical) {
            emit CriticalEventLogged(logId, category, message, dataHash);
        }
    }

    /**
     * @notice Batch log multiple events
     * @param _categories Array of categories
     * @param severities Array of severities
     * @param messages Array of messages
     * @param dataHashes Array of data hashes
     */
    function batchLogEvents(
        string[] calldata _categories,
        Severity[] calldata severities,
        string[] calldata messages,
        bytes32[] calldata dataHashes
    ) external whenNotPaused {
        require(authorizedLoggers[msg.sender] || msg.sender == owner(), "Not authorized");
        uint256 len = _categories.length;
        require(len == severities.length && len == messages.length && len == dataHashes.length, "Length mismatch");
        require(len <= 50, "Batch too large");

        for (uint256 i = 0; i < len; i++) {
            bytes32 catHash = keccak256(abi.encodePacked(_categories[i]));
            if (categoryExists[catHash] && bytes(messages[i]).length > 0) {
                uint256 logId = nextLogId++;
                LogEntry storage entry = logs[logId];
                entry.id = logId;
                entry.logger = msg.sender;
                entry.category = _categories[i];
                entry.severity = severities[i];
                entry.message = messages[i];
                entry.dataHash = dataHashes[i];
                entry.blockNumber = block.number;
                entry.timestamp = block.timestamp;

                categoryLogIds[catHash].push(logId);
                categories[catHash].entryCount++;
                severityCounts[severities[i]]++;
                totalLogs++;

                emit EventLogged(logId, msg.sender, _categories[i], severities[i], messages[i]);
            }
        }
    }

    /**
     * @notice Get log entries for a category within a block range
     * @param category The category to query
     * @param fromBlock Start block
     * @param toBlock End block
     * @return logIds Array of matching log entry IDs
     */
    function getEvents(string calldata category, uint256 fromBlock, uint256 toBlock)
        external
        view
        returns (uint256[] memory logIds)
    {
        bytes32 catHash = keccak256(abi.encodePacked(category));
        uint256[] storage allIds = categoryLogIds[catHash];

        uint256 count;
        for (uint256 i = 0; i < allIds.length; i++) {
            LogEntry storage e = logs[allIds[i]];
            if (e.blockNumber >= fromBlock && e.blockNumber <= toBlock) count++;
        }

        logIds = new uint256[](count);
        uint256 idx;
        for (uint256 i = 0; i < allIds.length; i++) {
            LogEntry storage e = logs[allIds[i]];
            if (e.blockNumber >= fromBlock && e.blockNumber <= toBlock) {
                logIds[idx++] = allIds[i];
            }
        }
    }

    /**
     * @notice Subscribe to a category
     * @param category The category to subscribe to
     * @return subscriptionId The subscription ID
     */
    function subscribeToCategory(string calldata category)
        external
        payable
        whenNotPaused
        returns (uint256 subscriptionId)
    {
        bytes32 catHash = keccak256(abi.encodePacked(category));
        require(categoryExists[catHash], "Category does not exist");
        CategoryInfo storage ci = categories[catHash];
        require(ci.active, "Category not active");
        require(msg.value >= ci.subscriptionPrice, "Insufficient payment");

        subscriptionId = nextSubscriptionId++;
        Subscription storage sub = subscriptions[subscriptionId];
        sub.subscriber = msg.sender;
        sub.category = category;
        sub.subscribedAt = block.timestamp;
        sub.expiresAt = block.timestamp + defaultSubscriptionDuration;
        sub.active = true;

        ci.subscriberCount++;
        userSubscriptions[msg.sender].push(subscriptionId);

        emit CategorySubscribed(subscriptionId, msg.sender, category, defaultSubscriptionDuration);
    }

    // ---------- View ----------
    function getCategoryLogCount(string calldata category) external view returns (uint256) {
        return categories[keccak256(abi.encodePacked(category))].entryCount;
    }

    function getUserSubscriptions(address user) external view returns (uint256[] memory) {
        return userSubscriptions[user];
    }

    function getSeverityCount(Severity severity) external view returns (uint256) {
        return severityCounts[severity];
    }

    function setSubscriptionDuration(uint256 duration) external onlyOwner {
        defaultSubscriptionDuration = duration;
    }

    function withdrawFees() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "No fees");
        (bool ok, ) = owner().call{value: bal}("");
        require(ok, "Withdraw failed");
    }
}
