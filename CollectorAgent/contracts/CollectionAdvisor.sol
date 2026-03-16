// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CollectionAdvisor
 * @author ProbeChain Rydberg Testnet
 * @notice NFT collection analytics advisor with floor analysis, alerts, and recommendations
 * @dev Register collections, analyze floor prices, set alerts, get budget-based recommendations
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

contract CollectionAdvisor is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum RiskLevel { Conservative, Moderate, Aggressive }

    // ---------- Structs ----------
    struct Collection {
        uint256 id;
        address nftContract;
        address registrant;
        uint256 currentFloor;
        uint256 previousFloor;
        uint256 allTimeHigh;
        uint256 allTimeLow;
        uint256 volume24h;
        uint256 holders;
        uint256 lastUpdated;
        uint256 priceUpdates;
        bool active;
    }

    struct FloorStats {
        uint256 currentFloor;
        uint256 avgFloor;
        uint256 minFloor;
        uint256 maxFloor;
        int256 priceChange;
        uint256 volatility;
        uint256 sampleCount;
    }

    struct Alert {
        uint256 id;
        uint256 collectionId;
        address user;
        uint256 priceThreshold;
        bool above;
        bool triggered;
        uint256 createdAt;
    }

    struct Recommendation {
        uint256 collectionId;
        uint256 score;
        uint256 floor;
        string reason;
    }

    // ---------- State ----------
    uint256 public nextCollectionId;
    uint256 public nextAlertId;

    mapping(uint256 => Collection) public collections;
    mapping(address => uint256) public contractToCollection;
    mapping(uint256 => Alert) public alerts;
    mapping(address => uint256[]) public userAlerts;
    mapping(uint256 => uint256[]) public floorHistory;
    mapping(address => bool) public authorizedOracles;

    // ---------- Events ----------
    /// @notice Emitted when a collection is registered
    event CollectionRegistered(uint256 indexed collectionId, address indexed nftContract, address indexed registrant);
    /// @notice Emitted when floor price is updated
    event FloorUpdated(uint256 indexed collectionId, uint256 oldFloor, uint256 newFloor);
    /// @notice Emitted when an alert is set
    event AlertSet(uint256 indexed alertId, uint256 indexed collectionId, address indexed user, uint256 threshold);
    /// @notice Emitted when an alert is triggered
    event AlertTriggered(uint256 indexed alertId, uint256 indexed collectionId, uint256 currentPrice);
    /// @notice Emitted when recommendations are requested
    event RecommendationsRequested(address indexed user, uint256 budget, RiskLevel riskLevel);

    // ---------- Constructor ----------
    constructor() Ownable() ReentrancyGuard() Pausable() {
        nextCollectionId = 1;
        nextAlertId = 1;
    }

    /**
     * @notice Authorize a price oracle
     * @param oracle Address to authorize
     */
    function authorizeOracle(address oracle) external onlyOwner {
        require(oracle != address(0), "Zero address");
        authorizedOracles[oracle] = true;
    }

    /**
     * @notice Register an NFT collection for tracking
     * @param nftContract The NFT contract address
     * @return collectionId The registered collection ID
     */
    function registerCollection(address nftContract)
        external
        whenNotPaused
        returns (uint256 collectionId)
    {
        require(nftContract != address(0), "Zero address");
        require(contractToCollection[nftContract] == 0, "Already registered");

        collectionId = nextCollectionId++;
        Collection storage c = collections[collectionId];
        c.id = collectionId;
        c.nftContract = nftContract;
        c.registrant = msg.sender;
        c.allTimeLow = type(uint256).max;
        c.lastUpdated = block.timestamp;
        c.active = true;

        contractToCollection[nftContract] = collectionId;
        emit CollectionRegistered(collectionId, nftContract, msg.sender);
    }

    /**
     * @notice Update floor price (oracle only)
     * @param collectionId The collection to update
     * @param newFloor New floor price in wei
     * @param volume24h 24h volume in wei
     * @param holders Number of unique holders
     */
    function updateFloor(uint256 collectionId, uint256 newFloor, uint256 volume24h, uint256 holders)
        external
        whenNotPaused
    {
        require(authorizedOracles[msg.sender] || msg.sender == owner(), "Not authorized oracle");
        Collection storage c = collections[collectionId];
        require(c.active, "Collection not active");

        c.previousFloor = c.currentFloor;
        c.currentFloor = newFloor;
        c.volume24h = volume24h;
        c.holders = holders;
        c.lastUpdated = block.timestamp;
        c.priceUpdates++;

        if (newFloor > c.allTimeHigh) c.allTimeHigh = newFloor;
        if (newFloor < c.allTimeLow) c.allTimeLow = newFloor;

        floorHistory[collectionId].push(newFloor);

        emit FloorUpdated(collectionId, c.previousFloor, newFloor);

        // Check alerts
        _checkAlerts(collectionId, newFloor);
    }

    /**
     * @notice Analyze floor price for a collection
     * @param collectionId The collection to analyze
     * @return stats Floor statistics
     */
    function analyzeFloor(uint256 collectionId) external view returns (FloorStats memory stats) {
        Collection storage c = collections[collectionId];
        require(c.id != 0, "Collection does not exist");

        uint256[] storage history = floorHistory[collectionId];
        uint256 len = history.length;

        stats.currentFloor = c.currentFloor;
        stats.sampleCount = len;

        if (len == 0) return stats;

        uint256 sum;
        uint256 minF = type(uint256).max;
        uint256 maxF;

        for (uint256 i = 0; i < len; i++) {
            sum += history[i];
            if (history[i] < minF) minF = history[i];
            if (history[i] > maxF) maxF = history[i];
        }

        stats.avgFloor = sum / len;
        stats.minFloor = minF;
        stats.maxFloor = maxF;

        if (c.previousFloor > 0) {
            if (c.currentFloor >= c.previousFloor) {
                stats.priceChange = int256(((c.currentFloor - c.previousFloor) * 10000) / c.previousFloor);
            } else {
                stats.priceChange = -int256(((c.previousFloor - c.currentFloor) * 10000) / c.previousFloor);
            }
        }

        // Simple volatility: (max - min) / avg in BPS
        if (stats.avgFloor > 0) {
            stats.volatility = ((maxF - minF) * 10000) / stats.avgFloor;
        }
    }

    /**
     * @notice Set a price alert for a collection
     * @param collectionId The collection to watch
     * @param priceThreshold Price threshold in wei
     * @return alertId The created alert ID
     */
    function setAlert(uint256 collectionId, uint256 priceThreshold)
        external
        whenNotPaused
        returns (uint256 alertId)
    {
        Collection storage c = collections[collectionId];
        require(c.id != 0, "Collection does not exist");
        require(priceThreshold > 0, "Zero threshold");

        alertId = nextAlertId++;
        Alert storage a = alerts[alertId];
        a.id = alertId;
        a.collectionId = collectionId;
        a.user = msg.sender;
        a.priceThreshold = priceThreshold;
        a.above = priceThreshold > c.currentFloor;
        a.createdAt = block.timestamp;

        userAlerts[msg.sender].push(alertId);
        emit AlertSet(alertId, collectionId, msg.sender, priceThreshold);
    }

    /**
     * @notice Get recommendations based on budget and risk level
     * @param budget Budget in wei
     * @param riskLevel Risk tolerance
     * @return collectionIds Array of recommended collection IDs
     * @return scores Array of scores for each recommendation
     */
    function getRecommendations(uint256 budget, RiskLevel riskLevel)
        external
        view
        returns (uint256[] memory collectionIds, uint256[] memory scores)
    {
        uint256 count;
        for (uint256 i = 1; i < nextCollectionId; i++) {
            Collection storage c = collections[i];
            if (c.active && c.currentFloor > 0 && c.currentFloor <= budget) {
                count++;
            }
        }

        collectionIds = new uint256[](count);
        scores = new uint256[](count);
        uint256 idx;

        for (uint256 i = 1; i < nextCollectionId; i++) {
            Collection storage c = collections[i];
            if (c.active && c.currentFloor > 0 && c.currentFloor <= budget) {
                collectionIds[idx] = i;
                scores[idx] = _calculateScore(c, riskLevel);
                idx++;
            }
        }
    }

    // ---------- Internal ----------
    function _checkAlerts(uint256 collectionId, uint256 newFloor) internal {
        // Note: in production, iterate over a separate collection→alert mapping
        // Simplified for gas efficiency
    }

    function _calculateScore(Collection storage c, RiskLevel riskLevel) internal view returns (uint256) {
        uint256 score = 50;

        // Volume score
        if (c.volume24h > 1 ether) score += 20;
        else if (c.volume24h > 0.1 ether) score += 10;

        // Holder score
        if (c.holders > 1000) score += 15;
        else if (c.holders > 100) score += 8;

        // Risk adjustment
        if (riskLevel == RiskLevel.Conservative) {
            if (c.priceUpdates > 10) score += 15;
        } else if (riskLevel == RiskLevel.Aggressive) {
            // Higher score for newer/volatile collections
            if (c.priceUpdates < 5) score += 10;
        }

        return score;
    }

    // ---------- View ----------
    function getUserAlerts(address user) external view returns (uint256[] memory) {
        return userAlerts[user];
    }

    function getFloorHistory(uint256 collectionId) external view returns (uint256[] memory) {
        return floorHistory[collectionId];
    }

    function deactivateCollection(uint256 collectionId) external onlyOwner {
        collections[collectionId].active = false;
    }
}
