// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title AuditRegistry
 * @notice Decentralized smart contract audit registry with reputation, severity levels, and dispute resolution
 * @dev Requesters post bounties, auditors submit findings, community validates
 */
contract AuditRegistry {
    // ──────────────────── Ownership ────────────────────
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ──────────────────── Reentrancy Guard ────────────────────
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "Reentrant");
        _locked = 2;
        _;
        _locked = 1;
    }

    // ──────────────────── Pausable ────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "Paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ──────────────────── Enums ────────────────────
    enum Severity { Info, Low, Medium, High, Critical }
    enum RequestStatus { Open, UnderReview, Completed, Disputed, Cancelled }
    enum AuditStatus { Submitted, Approved, Rejected, Disputed }

    // ──────────────────── Data Structures ────────────────────
    struct Auditor {
        address addr;
        uint256 reputation;       // 0-10000
        uint256 auditsCompleted;
        uint256 auditsRejected;
        uint256 totalEarned;
        uint256 stakeAmount;
        bool registered;
    }

    struct AuditRequest {
        uint256 requestId;
        address requester;
        address contractAddress;   // The contract to audit
        uint256 reward;
        RequestStatus status;
        string description;
        uint256 createdAt;
        uint256 deadline;
    }

    struct AuditReport {
        uint256 reportId;
        uint256 requestId;
        address auditor;
        bytes32 reportHash;        // IPFS hash of full report
        Severity highestSeverity;
        uint256 findingsCount;
        AuditStatus status;
        uint256 submittedAt;
    }

    // ──────────────────── State ────────────────────
    uint256 public nextRequestId = 1;
    uint256 public nextReportId = 1;
    uint256 public minStake = 0.05 ether;
    uint256 public platformFeeBPS = 500; // 5%

    mapping(address => Auditor) public auditors;
    mapping(uint256 => AuditRequest) public requests;
    mapping(uint256 => AuditReport) public reports;
    mapping(uint256 => uint256[]) public requestReports; // requestId => reportIds
    mapping(address => uint256[]) public auditorReports;
    mapping(address => uint256) public pendingWithdrawals;

    // ──────────────────── Events ────────────────────
    event AuditorRegistered(address indexed auditor, uint256 stake);
    event AuditRequested(uint256 indexed requestId, address indexed requester, address contractAddress, uint256 reward);
    event AuditSubmitted(uint256 indexed reportId, uint256 indexed requestId, address indexed auditor, Severity severity);
    event AuditApproved(uint256 indexed reportId, uint256 indexed requestId);
    event AuditRejected(uint256 indexed reportId, uint256 indexed requestId);
    event AuditDisputed(uint256 indexed reportId, address indexed disputer);
    event RequestCancelled(uint256 indexed requestId);
    event ReputationUpdated(address indexed auditor, uint256 newReputation);
    event Withdrawn(address indexed addr, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    // ──────────────────── Auditor Registration ────────────────────

    /**
     * @notice Register as an auditor by staking PROBE
     */
    function registerAuditor() external payable whenNotPaused {
        require(!auditors[msg.sender].registered, "Already registered");
        require(msg.value >= minStake, "Stake too low");

        auditors[msg.sender] = Auditor({
            addr: msg.sender,
            reputation: 5000,
            auditsCompleted: 0,
            auditsRejected: 0,
            totalEarned: 0,
            stakeAmount: msg.value,
            registered: true
        });

        emit AuditorRegistered(msg.sender, msg.value);
    }

    /**
     * @notice Add more stake to increase reputation weight
     */
    function addStake() external payable {
        require(auditors[msg.sender].registered, "Not registered");
        auditors[msg.sender].stakeAmount += msg.value;
    }

    // ──────────────────── Audit Requests ────────────────────

    /**
     * @notice Request an audit for a smart contract
     * @param contractAddress The contract to be audited
     * @param description Brief description of the contract
     * @param deadline Deadline timestamp for submissions
     */
    function requestAudit(
        address contractAddress,
        string calldata description,
        uint256 deadline
    ) external payable whenNotPaused returns (uint256) {
        require(contractAddress != address(0), "Zero address");
        require(msg.value > 0, "Reward required");
        require(deadline > block.timestamp, "Deadline passed");
        require(bytes(description).length > 0, "Empty description");

        uint256 requestId = nextRequestId++;
        requests[requestId] = AuditRequest({
            requestId: requestId,
            requester: msg.sender,
            contractAddress: contractAddress,
            reward: msg.value,
            status: RequestStatus.Open,
            description: description,
            createdAt: block.timestamp,
            deadline: deadline
        });

        emit AuditRequested(requestId, msg.sender, contractAddress, msg.value);
        return requestId;
    }

    /**
     * @notice Cancel an open audit request (requester only, if no submissions)
     */
    function cancelRequest(uint256 requestId) external nonReentrant {
        AuditRequest storage r = requests[requestId];
        require(r.requester == msg.sender, "Not requester");
        require(r.status == RequestStatus.Open, "Not open");
        require(requestReports[requestId].length == 0, "Has submissions");

        r.status = RequestStatus.Cancelled;
        pendingWithdrawals[msg.sender] += r.reward;
        emit RequestCancelled(requestId);
    }

    // ──────────────────── Audit Submission ────────────────────

    /**
     * @notice Submit an audit report
     * @param requestId The request being fulfilled
     * @param reportHash IPFS hash of the full audit report
     * @param highestSeverity Highest severity finding
     * @param findingsCount Total number of findings
     */
    function submitAudit(
        uint256 requestId,
        bytes32 reportHash,
        Severity highestSeverity,
        uint256 findingsCount
    ) external whenNotPaused returns (uint256) {
        AuditRequest storage r = requests[requestId];
        require(r.status == RequestStatus.Open, "Not open");
        require(block.timestamp <= r.deadline, "Deadline passed");
        require(auditors[msg.sender].registered, "Not registered auditor");

        uint256 reportId = nextReportId++;
        reports[reportId] = AuditReport({
            reportId: reportId,
            requestId: requestId,
            auditor: msg.sender,
            reportHash: reportHash,
            highestSeverity: highestSeverity,
            findingsCount: findingsCount,
            status: AuditStatus.Submitted,
            submittedAt: block.timestamp
        });

        requestReports[requestId].push(reportId);
        auditorReports[msg.sender].push(reportId);
        r.status = RequestStatus.UnderReview;

        emit AuditSubmitted(reportId, requestId, msg.sender, highestSeverity);
        return reportId;
    }

    // ──────────────────── Approval / Rejection ────────────────────

    /**
     * @notice Approve an audit report and release reward (requester only)
     */
    function approveAudit(uint256 reportId) external nonReentrant {
        AuditReport storage rpt = reports[reportId];
        require(rpt.status == AuditStatus.Submitted, "Not submitted");

        AuditRequest storage req = requests[rpt.requestId];
        require(req.requester == msg.sender, "Not requester");

        rpt.status = AuditStatus.Approved;
        req.status = RequestStatus.Completed;

        // Pay auditor
        uint256 fee = (req.reward * platformFeeBPS) / 10000;
        uint256 payout = req.reward - fee;
        pendingWithdrawals[rpt.auditor] += payout;
        pendingWithdrawals[owner] += fee;

        // Update auditor reputation
        Auditor storage a = auditors[rpt.auditor];
        a.auditsCompleted++;
        a.totalEarned += payout;
        uint256 bonus = _severityBonus(rpt.highestSeverity);
        a.reputation = a.reputation + bonus > 10000 ? 10000 : a.reputation + bonus;

        emit AuditApproved(reportId, rpt.requestId);
        emit ReputationUpdated(rpt.auditor, a.reputation);
    }

    /**
     * @notice Reject an audit report (requester only)
     */
    function rejectAudit(uint256 reportId) external {
        AuditReport storage rpt = reports[reportId];
        require(rpt.status == AuditStatus.Submitted, "Not submitted");

        AuditRequest storage req = requests[rpt.requestId];
        require(req.requester == msg.sender, "Not requester");

        rpt.status = AuditStatus.Rejected;
        req.status = RequestStatus.Open; // Reopen for other auditors

        Auditor storage a = auditors[rpt.auditor];
        a.auditsRejected++;
        a.reputation = a.reputation > 200 ? a.reputation - 200 : 0;

        emit AuditRejected(reportId, rpt.requestId);
        emit ReputationUpdated(rpt.auditor, a.reputation);
    }

    /**
     * @notice Dispute an audit decision (auditor only)
     */
    function disputeAudit(uint256 reportId) external {
        AuditReport storage rpt = reports[reportId];
        require(rpt.auditor == msg.sender, "Not auditor");
        require(rpt.status == AuditStatus.Rejected, "Not rejected");

        rpt.status = AuditStatus.Disputed;
        emit AuditDisputed(reportId, msg.sender);
    }

    /**
     * @notice Resolve a dispute (owner only)
     * @param reportId The disputed report
     * @param auditorWins True if the auditor's report was valid
     */
    function resolveDispute(uint256 reportId, bool auditorWins) external onlyOwner nonReentrant {
        AuditReport storage rpt = reports[reportId];
        require(rpt.status == AuditStatus.Disputed, "Not disputed");

        AuditRequest storage req = requests[rpt.requestId];
        Auditor storage a = auditors[rpt.auditor];

        if (auditorWins) {
            rpt.status = AuditStatus.Approved;
            req.status = RequestStatus.Completed;
            uint256 fee = (req.reward * platformFeeBPS) / 10000;
            uint256 payout = req.reward - fee;
            pendingWithdrawals[rpt.auditor] += payout;
            pendingWithdrawals[owner] += fee;
            a.auditsCompleted++;
            a.auditsRejected = a.auditsRejected > 0 ? a.auditsRejected - 1 : 0;
            a.reputation = a.reputation + 300 > 10000 ? 10000 : a.reputation + 300;
        } else {
            rpt.status = AuditStatus.Rejected;
            req.status = RequestStatus.Open;
            a.reputation = a.reputation > 500 ? a.reputation - 500 : 0;
        }
    }

    // ──────────────────── Withdrawals ────────────────────

    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        pendingWithdrawals[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    // ──────────────────── Internal ────────────────────

    function _severityBonus(Severity s) internal pure returns (uint256) {
        if (s == Severity.Critical) return 500;
        if (s == Severity.High) return 300;
        if (s == Severity.Medium) return 200;
        if (s == Severity.Low) return 100;
        return 50; // Info
    }

    // ──────────────────── Views ────────────────────

    function getRequest(uint256 requestId) external view returns (AuditRequest memory) {
        return requests[requestId];
    }

    function getReport(uint256 reportId) external view returns (AuditReport memory) {
        return reports[reportId];
    }

    function getRequestReports(uint256 requestId) external view returns (uint256[] memory) {
        return requestReports[requestId];
    }

    function getAuditorReports(address auditor) external view returns (uint256[] memory) {
        return auditorReports[auditor];
    }

    function setMinStake(uint256 newMin) external onlyOwner {
        minStake = newMin;
    }

    function setFee(uint256 newFeeBPS) external onlyOwner {
        require(newFeeBPS <= 1000, "Fee too high");
        platformFeeBPS = newFeeBPS;
    }

    receive() external payable {}
}
