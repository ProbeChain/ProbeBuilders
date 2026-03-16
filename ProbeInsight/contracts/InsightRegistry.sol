// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title InsightRegistry
 * @author ProbeChain Labs
 * @notice Enterprise analytics registry — publish, purchase, and rate reports
 *         with author reputation and revenue sharing.
 * @dev Designed for ProbeChain Rydberg Testnet (Chain ID 8004, EVM London).
 */

// ---------------------------------------------------------------------------
// Inline: Ownable
// ---------------------------------------------------------------------------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ---------------------------------------------------------------------------
// Inline: ReentrancyGuard
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Inline: Pausable
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Main Contract
// ---------------------------------------------------------------------------
contract InsightRegistry is Ownable, ReentrancyGuard, Pausable {
    /// @notice Platform fee in basis points (e.g., 500 = 5%).
    uint256 public platformFeeBps;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    struct Report {
        uint256 id;
        address author;
        string title;
        bytes32 dataHash;
        string category;
        uint256 price;
        uint256 totalRating;
        uint256 ratingCount;
        uint256 purchaseCount;
        uint256 revenue;
        uint256 createdAt;
        bool active;
    }

    struct AuthorProfile {
        uint256 totalReports;
        uint256 totalRevenue;
        uint256 totalRating;
        uint256 totalRatingCount;
    }

    uint256 private _nextReportId;
    mapping(uint256 => Report) public reports;
    mapping(address => AuthorProfile) public authors;
    mapping(address => uint256[]) public authorReportIds;
    mapping(uint256 => mapping(address => bool)) public hasPurchased;
    mapping(uint256 => mapping(address => bool)) public hasRated;

    uint256 public platformBalance;

    // ---- Events ----------------------------------------------------------
    event ReportPublished(uint256 indexed reportId, address indexed author, string title, string category, uint256 price);
    event ReportPurchased(uint256 indexed reportId, address indexed buyer, uint256 price);
    event ReportRated(uint256 indexed reportId, address indexed rater, uint8 rating);
    event ReportDeactivated(uint256 indexed reportId);
    event PlatformFeeUpdated(uint256 newFeeBps);
    event PlatformWithdrawal(address indexed to, uint256 amount);

    constructor(uint256 _platformFeeBps) {
        require(_platformFeeBps <= 2000, "Fee too high"); // max 20%
        platformFeeBps = _platformFeeBps;
        _nextReportId = 1;
    }

    // ---- Core Functions --------------------------------------------------

    /**
     * @notice Publish a new analytics report.
     * @param title    Report title.
     * @param dataHash IPFS / content hash of the report data.
     * @param category Report category (e.g., "DeFi", "NFT", "Security").
     * @param price    Price in wei to purchase access.
     * @return reportId The new report identifier.
     */
    function publishReport(
        string calldata title,
        bytes32 dataHash,
        string calldata category,
        uint256 price
    ) external whenNotPaused returns (uint256 reportId) {
        require(bytes(title).length > 0, "Empty title");
        require(dataHash != bytes32(0), "Empty hash");
        require(price > 0, "Zero price");

        reportId = _nextReportId++;
        reports[reportId] = Report({
            id: reportId,
            author: msg.sender,
            title: title,
            dataHash: dataHash,
            category: category,
            price: price,
            totalRating: 0,
            ratingCount: 0,
            purchaseCount: 0,
            revenue: 0,
            createdAt: block.timestamp,
            active: true
        });

        authors[msg.sender].totalReports++;
        authorReportIds[msg.sender].push(reportId);

        emit ReportPublished(reportId, msg.sender, title, category, price);
    }

    /**
     * @notice Purchase access to a report.
     * @param reportId The report to purchase.
     */
    function purchaseReport(uint256 reportId) external payable nonReentrant whenNotPaused {
        Report storage r = reports[reportId];
        require(r.id != 0 && r.active, "Report not available");
        require(!hasPurchased[reportId][msg.sender], "Already purchased");
        require(msg.sender != r.author, "Author cannot purchase own report");
        require(msg.value == r.price, "Incorrect payment");

        hasPurchased[reportId][msg.sender] = true;
        r.purchaseCount++;

        // Revenue split
        uint256 fee = (msg.value * platformFeeBps) / BPS_DENOMINATOR;
        uint256 authorShare = msg.value - fee;

        platformBalance += fee;
        r.revenue += authorShare;
        authors[r.author].totalRevenue += authorShare;

        (bool success, ) = payable(r.author).call{value: authorShare}("");
        require(success, "Author payment failed");

        emit ReportPurchased(reportId, msg.sender, msg.value);
    }

    /**
     * @notice Rate a purchased report (1-5 stars).
     * @param reportId The report to rate.
     * @param rating   Rating value (1 to 5).
     */
    function rateReport(uint256 reportId, uint8 rating) external whenNotPaused {
        require(rating >= 1 && rating <= 5, "Rating must be 1-5");
        require(hasPurchased[reportId][msg.sender], "Must purchase first");
        require(!hasRated[reportId][msg.sender], "Already rated");

        Report storage r = reports[reportId];
        hasRated[reportId][msg.sender] = true;
        r.totalRating += rating;
        r.ratingCount++;

        authors[r.author].totalRating += rating;
        authors[r.author].totalRatingCount++;

        emit ReportRated(reportId, msg.sender, rating);
    }

    /// @notice Author deactivates their report.
    function deactivateReport(uint256 reportId) external {
        Report storage r = reports[reportId];
        require(r.author == msg.sender, "Not author");
        require(r.active, "Already inactive");
        r.active = false;
        emit ReportDeactivated(reportId);
    }

    // ---- Views -----------------------------------------------------------

    /// @notice Get a report by ID.
    function getReport(uint256 reportId) external view returns (Report memory) {
        require(reports[reportId].id != 0, "Not found");
        return reports[reportId];
    }

    /// @notice Get average rating for a report (multiplied by 100 for precision).
    function getAverageRating(uint256 reportId) external view returns (uint256) {
        Report memory r = reports[reportId];
        if (r.ratingCount == 0) return 0;
        return (r.totalRating * 100) / r.ratingCount;
    }

    /// @notice Get top reports by purchase count (simple: returns IDs of first `limit` reports).
    function getTopReports(uint256 limit) external view returns (uint256[] memory) {
        uint256 total = _nextReportId - 1;
        if (limit > total) limit = total;
        uint256[] memory ids = new uint256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            ids[i] = i + 1;
        }
        return ids;
    }

    function getAuthorReportIds(address author) external view returns (uint256[] memory) {
        return authorReportIds[author];
    }

    function totalReports() external view returns (uint256) {
        return _nextReportId - 1;
    }

    // ---- Admin -----------------------------------------------------------

    function setPlatformFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 2000, "Fee too high");
        platformFeeBps = _feeBps;
        emit PlatformFeeUpdated(_feeBps);
    }

    function withdrawPlatformFees(address to) external onlyOwner nonReentrant {
        require(to != address(0), "Zero address");
        uint256 amount = platformBalance;
        require(amount > 0, "No fees");
        platformBalance = 0;
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Withdraw failed");
        emit PlatformWithdrawal(to, amount);
    }

    receive() external payable {}
}
