// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IndexerRegistry
 * @author ProbeChain
 * @notice Blockchain indexer registry for discovering and subscribing to data indexers
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

contract IndexerRegistry is Ownable, ReentrancyGuard, Pausable {
    /// @notice Indexer registration data
    struct Indexer {
        uint256 id;
        address owner;
        string name;
        string endpoint;
        string[] supportedEvents;
        uint256 subscriberCount;
        uint256 totalReports;
        uint256 registeredAt;
        bool active;
    }

    /// @notice Data report from an indexer
    struct DataReport {
        uint256 indexerId;
        uint256 blockStart;
        uint256 blockEnd;
        bytes32 dataHash;
        uint256 reportedAt;
    }

    /// @dev Subscription fee per indexer
    uint256 public subscriptionFee;

    /// @dev Counter for indexer IDs
    uint256 private _nextIndexerId;

    /// @dev Indexer ID => Indexer
    mapping(uint256 => Indexer) private _indexers;

    /// @dev All indexer IDs
    uint256[] private _indexerIds;

    /// @dev User => Indexer ID => subscribed
    mapping(address => mapping(uint256 => bool)) private _subscriptions;

    /// @dev Indexer ID => data reports
    mapping(uint256 => DataReport[]) private _reports;

    /// @dev Address => owned indexer IDs
    mapping(address => uint256[]) private _ownerIndexers;

    // ───────── Events ─────────

    /// @notice Emitted when an indexer is registered
    event IndexerRegistered(uint256 indexed indexerId, address indexed owner, string name, string endpoint);

    /// @notice Emitted when a user subscribes to an indexer
    event SubscribedToIndex(uint256 indexed indexerId, address indexed subscriber);

    /// @notice Emitted when data is reported
    event DataReported(uint256 indexed indexerId, uint256 blockStart, uint256 blockEnd, bytes32 dataHash);

    /// @notice Emitted when an indexer is deactivated
    event IndexerDeactivated(uint256 indexed indexerId);

    /// @notice Emitted when subscription fee is updated
    event SubscriptionFeeUpdated(uint256 newFee);

    /// @notice Emitted when fees are withdrawn
    event FeesWithdrawn(address indexed to, uint256 amount);

    // ───────── Constructor ─────────

    constructor() {
        _nextIndexerId = 1;
        subscriptionFee = 0.01 ether;
    }

    // ───────── Admin ─────────

    /// @notice Update subscription fee
    function setSubscriptionFee(uint256 fee) external onlyOwner {
        subscriptionFee = fee;
        emit SubscriptionFeeUpdated(fee);
    }

    /// @notice Withdraw collected fees
    function withdrawFees(address payable to) external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "IndexerRegistry: no fees");
        (bool sent, ) = to.call{value: balance}("");
        require(sent, "IndexerRegistry: transfer failed");
        emit FeesWithdrawn(to, balance);
    }

    /// @notice Pause/unpause
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Register a new indexer
    /// @param _name Indexer name
    /// @param _endpoint API endpoint URL
    /// @param _supportedEvents Array of event signatures this indexer tracks
    /// @return indexerId The new indexer ID
    function registerIndexer(
        string calldata _name,
        string calldata _endpoint,
        string[] calldata _supportedEvents
    ) external whenNotPaused returns (uint256 indexerId) {
        require(bytes(_name).length > 0, "IndexerRegistry: empty name");
        require(bytes(_endpoint).length > 0, "IndexerRegistry: empty endpoint");
        require(_supportedEvents.length > 0, "IndexerRegistry: no events");

        indexerId = _nextIndexerId++;

        Indexer storage idx = _indexers[indexerId];
        idx.id = indexerId;
        idx.owner = msg.sender;
        idx.name = _name;
        idx.endpoint = _endpoint;
        idx.subscriberCount = 0;
        idx.totalReports = 0;
        idx.registeredAt = block.timestamp;
        idx.active = true;

        for (uint256 i = 0; i < _supportedEvents.length; i++) {
            idx.supportedEvents.push(_supportedEvents[i]);
        }

        _indexerIds.push(indexerId);
        _ownerIndexers[msg.sender].push(indexerId);

        emit IndexerRegistered(indexerId, msg.sender, _name, _endpoint);
    }

    /// @notice Subscribe to an indexer
    /// @param indexerId The indexer to subscribe to
    function subscribeToIndex(uint256 indexerId) external payable whenNotPaused nonReentrant {
        require(_indexers[indexerId].active, "IndexerRegistry: not active");
        require(!_subscriptions[msg.sender][indexerId], "IndexerRegistry: already subscribed");
        require(msg.value >= subscriptionFee, "IndexerRegistry: insufficient fee");

        _subscriptions[msg.sender][indexerId] = true;
        _indexers[indexerId].subscriberCount++;

        // Refund excess
        if (msg.value > subscriptionFee) {
            (bool sent, ) = msg.sender.call{value: msg.value - subscriptionFee}("");
            require(sent, "IndexerRegistry: refund failed");
        }

        emit SubscribedToIndex(indexerId, msg.sender);
    }

    /// @notice Report indexed data for a block range
    /// @param indexerId The indexer reporting
    /// @param blockStart Start block number
    /// @param blockEnd End block number
    /// @param dataHash Hash of the indexed data
    function reportData(
        uint256 indexerId,
        uint256 blockStart,
        uint256 blockEnd,
        bytes32 dataHash
    ) external whenNotPaused {
        Indexer storage idx = _indexers[indexerId];
        require(idx.active, "IndexerRegistry: not active");
        require(idx.owner == msg.sender, "IndexerRegistry: not indexer owner");
        require(blockEnd >= blockStart, "IndexerRegistry: invalid range");
        require(dataHash != bytes32(0), "IndexerRegistry: empty hash");

        _reports[indexerId].push(DataReport({
            indexerId: indexerId,
            blockStart: blockStart,
            blockEnd: blockEnd,
            dataHash: dataHash,
            reportedAt: block.timestamp
        }));

        idx.totalReports++;

        emit DataReported(indexerId, blockStart, blockEnd, dataHash);
    }

    /// @notice Deactivate an indexer
    /// @param indexerId The indexer to deactivate
    function deactivateIndexer(uint256 indexerId) external {
        Indexer storage idx = _indexers[indexerId];
        require(idx.owner == msg.sender || msg.sender == owner(), "IndexerRegistry: not authorized");
        require(idx.active, "IndexerRegistry: not active");
        idx.active = false;
        emit IndexerDeactivated(indexerId);
    }

    // ───────── View Functions ─────────

    /// @notice Get all active indexers
    /// @return result Array of active indexer IDs
    function getIndexers() external view returns (uint256[] memory result) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < _indexerIds.length; i++) {
            if (_indexers[_indexerIds[i]].active) activeCount++;
        }
        result = new uint256[](activeCount);
        uint256 j = 0;
        for (uint256 i = 0; i < _indexerIds.length; i++) {
            if (_indexers[_indexerIds[i]].active) {
                result[j++] = _indexerIds[i];
            }
        }
    }

    /// @notice Get indexer details
    function getIndexer(uint256 indexerId) external view returns (
        address idxOwner, string memory _name, string memory endpoint,
        string[] memory supportedEvents, uint256 subscriberCount,
        uint256 totalReports, bool active
    ) {
        Indexer storage idx = _indexers[indexerId];
        require(idx.registeredAt > 0, "IndexerRegistry: not found");
        return (idx.owner, idx.name, idx.endpoint, idx.supportedEvents, idx.subscriberCount, idx.totalReports, idx.active);
    }

    /// @notice Check subscription status
    function isSubscribed(address user, uint256 indexerId) external view returns (bool) {
        return _subscriptions[user][indexerId];
    }

    /// @notice Get reports for an indexer
    function getReports(uint256 indexerId) external view returns (DataReport[] memory) {
        return _reports[indexerId];
    }

    /// @notice Get total indexers registered
    function totalIndexers() external view returns (uint256) {
        return _nextIndexerId - 1;
    }
}
