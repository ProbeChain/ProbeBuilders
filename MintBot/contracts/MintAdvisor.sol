// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MintAdvisor
 * @author ProbeChain Rydberg Testnet
 * @notice Strategic minting advisor for upcoming NFT mints with analysis, alerts, and results
 * @dev Register upcoming mints, analyze potential, set alerts, record outcomes
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

contract MintAdvisor is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum MintStatus { Upcoming, Live, Completed, Cancelled }
    enum MintResult { Unknown, Success, SoldOut, Partial, Failed }

    // ---------- Structs ----------
    struct MintInfo {
        uint256 id;
        address collection;
        uint256 mintDate;
        uint256 price;
        uint256 supply;
        address registrant;
        MintStatus status;
        MintResult result;
        uint256 registeredAt;
        uint256 hypeScore;
        uint256 communitySize;
        bytes32 metadataHash;
        uint256 actualMinted;
        uint256 floorAfterMint;
    }

    struct MintAnalysis {
        uint256 overallScore;
        uint256 priceScore;
        uint256 supplyScore;
        uint256 hypeScore;
        uint256 timingScore;
        bool recommended;
    }

    struct MintAlert {
        uint256 id;
        uint256 mintId;
        address user;
        bool triggered;
        uint256 createdAt;
    }

    // ---------- State ----------
    uint256 public nextMintId;
    uint256 public nextAlertId;

    mapping(uint256 => MintInfo) public mints;
    mapping(uint256 => MintAlert) public mintAlerts;
    mapping(address => uint256[]) public userAlerts;
    mapping(address => uint256[]) public registrantMints;
    mapping(address => bool) public authorizedAnalysts;

    // Scoring weights (BPS)
    uint256 public priceWeight;
    uint256 public supplyWeight;
    uint256 public hypeWeight;
    uint256 public timingWeight;

    // ---------- Events ----------
    /// @notice Emitted when an upcoming mint is registered
    event MintRegistered(uint256 indexed mintId, address indexed collection, uint256 mintDate, uint256 price, uint256 supply);
    /// @notice Emitted when a mint is analyzed
    event MintAnalyzed(uint256 indexed mintId, uint256 overallScore, bool recommended);
    /// @notice Emitted when a mint alert is set
    event MintAlertSet(uint256 indexed alertId, uint256 indexed mintId, address indexed user);
    /// @notice Emitted when a mint alert is triggered
    event MintAlertTriggered(uint256 indexed alertId, uint256 indexed mintId);
    /// @notice Emitted when a mint result is recorded
    event MintResultRecorded(uint256 indexed mintId, MintResult result, uint256 actualMinted, uint256 floorAfterMint);
    /// @notice Emitted when mint status is updated
    event MintStatusUpdated(uint256 indexed mintId, MintStatus newStatus);

    // ---------- Constructor ----------
    constructor() Ownable() ReentrancyGuard() Pausable() {
        nextMintId = 1;
        nextAlertId = 1;
        priceWeight = 2500;
        supplyWeight = 2500;
        hypeWeight = 3000;
        timingWeight = 2000;
    }

    /**
     * @notice Authorize an analyst
     * @param analyst Address to authorize
     */
    function authorizeAnalyst(address analyst) external onlyOwner {
        require(analyst != address(0), "Zero address");
        authorizedAnalysts[analyst] = true;
    }

    /**
     * @notice Register an upcoming mint
     * @param collection The collection contract address
     * @param mintDate Expected mint date timestamp
     * @param price Mint price in wei
     * @param supply Total supply
     * @return mintId The registered mint ID
     */
    function registerUpcomingMint(
        address collection,
        uint256 mintDate,
        uint256 price,
        uint256 supply
    )
        external
        whenNotPaused
        returns (uint256 mintId)
    {
        require(collection != address(0), "Zero address");
        require(mintDate > block.timestamp, "Mint date in the past");
        require(supply > 0, "Zero supply");

        mintId = nextMintId++;
        MintInfo storage m = mints[mintId];
        m.id = mintId;
        m.collection = collection;
        m.mintDate = mintDate;
        m.price = price;
        m.supply = supply;
        m.registrant = msg.sender;
        m.status = MintStatus.Upcoming;
        m.registeredAt = block.timestamp;

        registrantMints[msg.sender].push(mintId);
        emit MintRegistered(mintId, collection, mintDate, price, supply);
    }

    /**
     * @notice Update hype/community data for a mint
     * @param mintId The mint to update
     * @param hypeScore Social hype score (0-100)
     * @param communitySize Community size
     * @param metadataHash IPFS hash of detailed analysis
     */
    function updateMintData(uint256 mintId, uint256 hypeScore, uint256 communitySize, bytes32 metadataHash)
        external
        whenNotPaused
    {
        require(authorizedAnalysts[msg.sender] || msg.sender == owner(), "Not authorized");
        MintInfo storage m = mints[mintId];
        require(m.id != 0, "Mint does not exist");
        require(hypeScore <= 100, "Hype score max 100");

        m.hypeScore = hypeScore;
        m.communitySize = communitySize;
        m.metadataHash = metadataHash;
    }

    /**
     * @notice Analyze a mint and return a score
     * @param mintId The mint to analyze
     * @return analysis Detailed analysis with scores
     */
    function analyzeMint(uint256 mintId) external view returns (MintAnalysis memory analysis) {
        MintInfo storage m = mints[mintId];
        require(m.id != 0, "Mint does not exist");

        // Price score: lower price = higher score (max when free)
        if (m.price == 0) analysis.priceScore = 100;
        else if (m.price <= 0.01 ether) analysis.priceScore = 80;
        else if (m.price <= 0.1 ether) analysis.priceScore = 60;
        else if (m.price <= 1 ether) analysis.priceScore = 40;
        else analysis.priceScore = 20;

        // Supply score: scarce = higher score
        if (m.supply <= 100) analysis.supplyScore = 90;
        else if (m.supply <= 1000) analysis.supplyScore = 70;
        else if (m.supply <= 5000) analysis.supplyScore = 50;
        else if (m.supply <= 10000) analysis.supplyScore = 30;
        else analysis.supplyScore = 15;

        // Hype score: direct from data
        analysis.hypeScore = m.hypeScore;

        // Timing score: mints happening soon get higher urgency score
        if (m.mintDate > block.timestamp) {
            uint256 daysUntil = (m.mintDate - block.timestamp) / 1 days;
            if (daysUntil <= 1) analysis.timingScore = 95;
            else if (daysUntil <= 3) analysis.timingScore = 80;
            else if (daysUntil <= 7) analysis.timingScore = 60;
            else if (daysUntil <= 30) analysis.timingScore = 40;
            else analysis.timingScore = 20;
        }

        // Weighted overall
        analysis.overallScore = (
            analysis.priceScore * priceWeight +
            analysis.supplyScore * supplyWeight +
            analysis.hypeScore * hypeWeight +
            analysis.timingScore * timingWeight
        ) / 10000;

        analysis.recommended = analysis.overallScore >= 60;
    }

    /**
     * @notice Set an alert for a mint
     * @param mintId The mint to watch
     * @return alertId The alert ID
     */
    function setMintAlert(uint256 mintId) external whenNotPaused returns (uint256 alertId) {
        require(mints[mintId].id != 0, "Mint does not exist");
        require(mints[mintId].status == MintStatus.Upcoming, "Not upcoming");

        alertId = nextAlertId++;
        MintAlert storage a = mintAlerts[alertId];
        a.id = alertId;
        a.mintId = mintId;
        a.user = msg.sender;
        a.createdAt = block.timestamp;

        userAlerts[msg.sender].push(alertId);
        emit MintAlertSet(alertId, mintId, msg.sender);
    }

    /**
     * @notice Record the result of a completed mint
     * @param mintId The mint to record
     * @param result The mint outcome
     */
    function recordMintResult(uint256 mintId, MintResult result)
        external
        whenNotPaused
    {
        require(authorizedAnalysts[msg.sender] || msg.sender == owner(), "Not authorized");
        MintInfo storage m = mints[mintId];
        require(m.id != 0, "Mint does not exist");

        m.status = MintStatus.Completed;
        m.result = result;
        emit MintResultRecorded(mintId, result, m.actualMinted, m.floorAfterMint);
    }

    /**
     * @notice Record actual minting data post-mint
     * @param mintId The mint
     * @param actualMinted How many were actually minted
     * @param floorAfterMint Floor price after mint
     */
    function recordMintStats(uint256 mintId, uint256 actualMinted, uint256 floorAfterMint) external {
        require(authorizedAnalysts[msg.sender] || msg.sender == owner(), "Not authorized");
        MintInfo storage m = mints[mintId];
        require(m.id != 0, "Mint does not exist");
        m.actualMinted = actualMinted;
        m.floorAfterMint = floorAfterMint;
    }

    /**
     * @notice Update mint status
     * @param mintId The mint
     * @param status New status
     */
    function updateMintStatus(uint256 mintId, MintStatus status) external {
        require(authorizedAnalysts[msg.sender] || msg.sender == owner() || mints[mintId].registrant == msg.sender, "Not authorized");
        mints[mintId].status = status;
        emit MintStatusUpdated(mintId, status);
    }

    // ---------- View ----------
    function getUserAlerts(address user) external view returns (uint256[] memory) {
        return userAlerts[user];
    }

    function getRegistrantMints(address registrant) external view returns (uint256[] memory) {
        return registrantMints[registrant];
    }

    function setWeights(uint256 _price, uint256 _supply, uint256 _hype, uint256 _timing) external onlyOwner {
        require(_price + _supply + _hype + _timing == 10000, "Weights must sum to 10000");
        priceWeight = _price;
        supplyWeight = _supply;
        hypeWeight = _hype;
        timingWeight = _timing;
    }
}
