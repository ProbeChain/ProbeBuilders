// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PriceFeed
 * @author ProbeChain Team
 * @notice On-chain price oracle with TWAP support and heartbeat monitoring
 * @dev Authorized reporters update prices, consumers read latest/historical/TWAP data
 */
contract PriceFeed {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "PriceFeed: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "PriceFeed: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "PriceFeed: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Structs ────────────────────────────────────────────────────────
    struct Feed {
        uint256 id;
        string pairName;
        uint256 heartbeat;
        address creator;
        uint256 latestPrice;
        uint256 latestTimestamp;
        uint256 updateCount;
        uint256 createdAt;
        bool active;
    }

    struct PricePoint {
        uint256 price;
        uint256 timestamp;
        address reporter;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public feedCount;
    uint256 public constant MAX_HISTORY = 1000;

    mapping(uint256 => Feed) public feeds;
    mapping(uint256 => PricePoint[]) public priceHistory;
    mapping(uint256 => uint256) public cumulativePrice;
    mapping(string => uint256) public pairToFeedId;
    mapping(address => bool) public authorizedReporters;
    mapping(uint256 => mapping(address => bool)) public feedReporters;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a new price feed is created
    event FeedCreated(uint256 indexed feedId, string pairName, uint256 heartbeat, address indexed creator);
    /// @notice Emitted when a price is updated
    event PriceUpdated(uint256 indexed feedId, uint256 price, uint256 timestamp, address indexed reporter);
    /// @notice Emitted when a reporter is authorized
    event ReporterAuthorized(address indexed reporter, bool status);
    /// @notice Emitted when a feed-specific reporter is set
    event FeedReporterSet(uint256 indexed feedId, address indexed reporter, bool status);
    /// @notice Emitted when heartbeat is missed
    event HeartbeatMissed(uint256 indexed feedId, uint256 lastUpdate, uint256 heartbeat);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Reporter Management ────────────────────────────────────────────
    /**
     * @notice Set global reporter authorization
     * @param reporter Reporter address
     * @param status Authorization status
     */
    function setAuthorizedReporter(address reporter, bool status) external onlyOwner {
        authorizedReporters[reporter] = status;
        emit ReporterAuthorized(reporter, status);
    }

    /**
     * @notice Set feed-specific reporter
     * @param feedId Feed ID
     * @param reporter Reporter address
     * @param status Authorization status
     */
    function setFeedReporter(uint256 feedId, address reporter, bool status) external {
        require(
            msg.sender == feeds[feedId].creator || msg.sender == _owner,
            "PriceFeed: unauthorized"
        );
        feedReporters[feedId][reporter] = status;
        emit FeedReporterSet(feedId, reporter, status);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Create a new price feed
     * @param pairName Trading pair name (e.g., "ETH/USD")
     * @param heartbeat Expected update interval in seconds
     * @return feedId The new feed ID
     */
    function createFeed(
        string calldata pairName,
        uint256 heartbeat
    ) external whenNotPaused returns (uint256 feedId) {
        require(bytes(pairName).length > 0 && bytes(pairName).length <= 32, "PriceFeed: invalid pair name");
        require(heartbeat > 0, "PriceFeed: zero heartbeat");
        require(pairToFeedId[pairName] == 0, "PriceFeed: pair already exists");

        feedCount++;
        feedId = feedCount;

        feeds[feedId] = Feed({
            id: feedId,
            pairName: pairName,
            heartbeat: heartbeat,
            creator: msg.sender,
            latestPrice: 0,
            latestTimestamp: 0,
            updateCount: 0,
            createdAt: block.timestamp,
            active: true
        });

        pairToFeedId[pairName] = feedId;
        emit FeedCreated(feedId, pairName, heartbeat, msg.sender);
    }

    /**
     * @notice Update a price feed with new data
     * @param feedId Feed to update
     * @param price New price (scaled by 1e8)
     * @param timestamp Price observation timestamp
     */
    function updatePrice(
        uint256 feedId,
        uint256 price,
        uint256 timestamp
    ) external whenNotPaused {
        Feed storage feed = feeds[feedId];
        require(feed.active, "PriceFeed: feed not active");
        require(
            authorizedReporters[msg.sender] || feedReporters[feedId][msg.sender],
            "PriceFeed: unauthorized reporter"
        );
        require(price > 0, "PriceFeed: zero price");
        require(timestamp <= block.timestamp, "PriceFeed: future timestamp");
        require(timestamp >= feed.latestTimestamp, "PriceFeed: stale timestamp");

        // Update TWAP accumulator
        if (feed.latestTimestamp > 0) {
            uint256 timeElapsed = timestamp - feed.latestTimestamp;
            cumulativePrice[feedId] += feed.latestPrice * timeElapsed;
        }

        feed.latestPrice = price;
        feed.latestTimestamp = timestamp;
        feed.updateCount++;

        priceHistory[feedId].push(PricePoint({
            price: price,
            timestamp: timestamp,
            reporter: msg.sender
        }));

        emit PriceUpdated(feedId, price, timestamp, msg.sender);
    }

    /**
     * @notice Get the latest price for a feed
     * @param feedId Feed ID
     * @return price Latest price
     * @return timestamp Last update timestamp
     * @return stale Whether the heartbeat has been missed
     */
    function getLatestPrice(uint256 feedId) external view returns (
        uint256 price,
        uint256 timestamp,
        bool stale
    ) {
        Feed storage feed = feeds[feedId];
        require(feed.active, "PriceFeed: feed not active");

        price = feed.latestPrice;
        timestamp = feed.latestTimestamp;
        stale = (block.timestamp - feed.latestTimestamp) > feed.heartbeat;
    }

    /**
     * @notice Get a historical price closest to a target timestamp
     * @param feedId Feed ID
     * @param targetTimestamp Target timestamp to look up
     * @return price Price at the closest available time
     * @return actualTimestamp Actual timestamp of the price point
     */
    function getHistoricalPrice(
        uint256 feedId,
        uint256 targetTimestamp
    ) external view returns (uint256 price, uint256 actualTimestamp) {
        PricePoint[] storage history = priceHistory[feedId];
        require(history.length > 0, "PriceFeed: no history");

        uint256 closest = 0;
        uint256 closestDiff = type(uint256).max;

        for (uint256 i = 0; i < history.length; i++) {
            uint256 diff = history[i].timestamp > targetTimestamp
                ? history[i].timestamp - targetTimestamp
                : targetTimestamp - history[i].timestamp;

            if (diff < closestDiff) {
                closestDiff = diff;
                closest = i;
            }
        }

        return (history[closest].price, history[closest].timestamp);
    }

    /**
     * @notice Calculate TWAP over the feed's lifetime
     * @param feedId Feed ID
     * @return twap Time-weighted average price (scaled by 1e8)
     */
    function getTWAP(uint256 feedId) external view returns (uint256 twap) {
        Feed storage feed = feeds[feedId];
        require(feed.latestTimestamp > feed.createdAt, "PriceFeed: insufficient data");

        uint256 totalTime = feed.latestTimestamp - priceHistory[feedId][0].timestamp;
        if (totalTime == 0) return feed.latestPrice;

        uint256 cumulative = cumulativePrice[feedId];
        cumulative += feed.latestPrice * (block.timestamp - feed.latestTimestamp);
        totalTime = block.timestamp - priceHistory[feedId][0].timestamp;

        return cumulative / totalTime;
    }

    /**
     * @notice Check if heartbeat is missed
     * @param feedId Feed ID
     * @return missed True if heartbeat was missed
     */
    function isHeartbeatMissed(uint256 feedId) external view returns (bool missed) {
        Feed storage feed = feeds[feedId];
        return feed.latestTimestamp > 0 && (block.timestamp - feed.latestTimestamp) > feed.heartbeat;
    }

    /**
     * @notice Deactivate a feed
     * @param feedId Feed to deactivate
     */
    function deactivateFeed(uint256 feedId) external {
        require(
            feeds[feedId].creator == msg.sender || msg.sender == _owner,
            "PriceFeed: unauthorized"
        );
        feeds[feedId].active = false;
    }
}
