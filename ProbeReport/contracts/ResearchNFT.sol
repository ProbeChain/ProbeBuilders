// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ResearchNFT
 * @author ProbeChain Rydberg Testnet
 * @notice ERC-721 NFTs for research reports with publishing, purchasing, citation tracking, and impact metrics
 * @dev Each published report is an NFT with paywall access, citation graph, and impact scoring
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

// ---------- Minimal ERC-721 ----------
abstract contract ERC721 {
    string public name;
    string public symbol;

    mapping(uint256 => address) internal _owners;
    mapping(address => uint256) internal _balances;
    mapping(uint256 => address) internal _tokenApprovals;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function balanceOf(address o) public view returns (uint256) { return _balances[o]; }
    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "ERC721: nonexistent token");
        return o;
    }

    function approve(address to, uint256 tokenId) public {
        address o = ownerOf(tokenId);
        require(msg.sender == o || _operatorApprovals[o][msg.sender], "Not authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(o, to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not authorized");
        _transfer(from, to, tokenId);
    }

    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "Mint to zero");
        require(_owners[tokenId] == address(0), "Already minted");
        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "Not owner");
        require(to != address(0), "Transfer to zero");
        _tokenApprovals[tokenId] = address(0);
        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address o = ownerOf(tokenId);
        return (spender == o || _tokenApprovals[tokenId] == spender || _operatorApprovals[o][spender]);
    }
}

contract ResearchNFT is ERC721, Ownable, ReentrancyGuard, Pausable {
    // ---------- Structs ----------
    struct Report {
        uint256 id;
        address author;
        string title;
        bytes32 abstractHash;
        bytes32 fullReportHash;
        uint256 price;
        uint256 publishedAt;
        uint256 totalSales;
        uint256 totalRevenue;
        uint256 citationCount;
    }

    struct Citation {
        uint256 citingReportId;
        uint256 citedReportId;
        uint256 timestamp;
    }

    // ---------- State ----------
    uint256 public nextReportId;
    uint256 public platformFeeBPS;

    mapping(uint256 => Report) public reports;
    mapping(uint256 => Citation[]) public reportCitations;
    mapping(uint256 => mapping(address => bool)) public hasPurchased;
    mapping(address => uint256) public authorEarnings;
    mapping(address => uint256[]) public authorReports;
    mapping(uint256 => uint256[]) public citedBy;

    // ---------- Events ----------
    /// @notice Emitted when a report is published
    event ReportPublished(uint256 indexed reportId, address indexed author, string title, uint256 price);
    /// @notice Emitted when a report is purchased
    event ReportPurchased(uint256 indexed reportId, address indexed buyer, uint256 price);
    /// @notice Emitted when a report is cited
    event ReportCited(uint256 indexed citingReportId, uint256 indexed citedReportId, address indexed citer);
    /// @notice Emitted when an author claims earnings
    event EarningsClaimed(address indexed author, uint256 amount);

    // ---------- Constructor ----------
    constructor(uint256 _feeBPS)
        ERC721("ProbeResearchNFT", "PRNFT")
        Ownable() ReentrancyGuard() Pausable()
    {
        require(_feeBPS <= 1000, "Fee too high");
        platformFeeBPS = _feeBPS;
        nextReportId = 1;
    }

    /**
     * @notice Publish a research report as an NFT
     * @param title Report title
     * @param abstractHash IPFS hash of the abstract
     * @param fullReportHash IPFS hash of the full report
     * @param price Purchase price in wei
     * @return reportId The published report ID
     */
    function publishReport(
        string calldata title,
        bytes32 abstractHash,
        bytes32 fullReportHash,
        uint256 price
    )
        external
        whenNotPaused
        returns (uint256 reportId)
    {
        require(bytes(title).length > 0 && bytes(title).length <= 256, "Invalid title length");
        require(abstractHash != bytes32(0), "Empty abstract hash");
        require(fullReportHash != bytes32(0), "Empty report hash");

        reportId = nextReportId++;
        Report storage r = reports[reportId];
        r.id = reportId;
        r.author = msg.sender;
        r.title = title;
        r.abstractHash = abstractHash;
        r.fullReportHash = fullReportHash;
        r.price = price;
        r.publishedAt = block.timestamp;

        _mint(msg.sender, reportId);
        authorReports[msg.sender].push(reportId);

        emit ReportPublished(reportId, msg.sender, title, price);
    }

    /**
     * @notice Purchase access to a research report
     * @param reportId The report to purchase
     */
    function purchaseReport(uint256 reportId) external payable nonReentrant whenNotPaused {
        Report storage r = reports[reportId];
        require(r.id != 0, "Report does not exist");
        require(!hasPurchased[reportId][msg.sender], "Already purchased");
        require(msg.sender != r.author, "Author cannot purchase own report");
        require(msg.value >= r.price, "Insufficient payment");

        hasPurchased[reportId][msg.sender] = true;
        r.totalSales++;
        r.totalRevenue += msg.value;

        uint256 fee = (msg.value * platformFeeBPS) / 10000;
        authorEarnings[r.author] += msg.value - fee;

        emit ReportPurchased(reportId, msg.sender, msg.value);
    }

    /**
     * @notice Cite another report from your published report
     * @param citingReportId Your report that contains the citation
     * @param citedReportId The report being cited
     */
    function citeReport(uint256 citingReportId, uint256 citedReportId) external whenNotPaused {
        Report storage citing = reports[citingReportId];
        Report storage cited = reports[citedReportId];
        require(citing.id != 0, "Citing report does not exist");
        require(cited.id != 0, "Cited report does not exist");
        require(citing.author == msg.sender, "Not the author of citing report");
        require(citingReportId != citedReportId, "Cannot self-cite");

        reportCitations[citingReportId].push(Citation({
            citingReportId: citingReportId,
            citedReportId: citedReportId,
            timestamp: block.timestamp
        }));

        cited.citationCount++;
        citedBy[citedReportId].push(citingReportId);

        emit ReportCited(citingReportId, citedReportId, msg.sender);
    }

    /**
     * @notice Get research impact score for a report
     * @param reportId The report to evaluate
     * @return impactScore Combined metric (citations * 100 + sales * 10 + revenue/1e15)
     */
    function getResearchImpact(uint256 reportId) external view returns (uint256 impactScore) {
        Report storage r = reports[reportId];
        require(r.id != 0, "Report does not exist");
        impactScore = (r.citationCount * 100) + (r.totalSales * 10) + (r.totalRevenue / 1e15);
    }

    /**
     * @notice Author claims accumulated earnings
     */
    function claimEarnings() external nonReentrant {
        uint256 amount = authorEarnings[msg.sender];
        require(amount > 0, "No earnings");
        authorEarnings[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        emit EarningsClaimed(msg.sender, amount);
    }

    // ---------- View ----------
    function getAuthorReports(address author) external view returns (uint256[] memory) {
        return authorReports[author];
    }

    function getCitedBy(uint256 reportId) external view returns (uint256[] memory) {
        return citedBy[reportId];
    }

    function getReportCitations(uint256 reportId) external view returns (Citation[] memory) {
        return reportCitations[reportId];
    }

    /// @notice Update platform fee
    function setPlatformFee(uint256 _feeBPS) external onlyOwner {
        require(_feeBPS <= 1000, "Fee too high");
        platformFeeBPS = _feeBPS;
    }

    /// @notice Withdraw platform fees
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "No fees");
        (bool ok, ) = owner().call{value: bal}("");
        require(ok, "Withdraw failed");
    }
}
