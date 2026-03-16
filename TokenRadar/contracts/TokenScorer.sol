// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TokenScorer
 * @author ProbeBuilders
 * @notice Crowd-sourced token risk assessment with auditor staking and slashing
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */
contract TokenScorer {
    // ─── Ownership ───────────────────────────────────────────────────
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "TokenScorer: not owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "TokenScorer: zero address");
        owner = newOwner;
    }

    // ─── Pausable ────────────────────────────────────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "TokenScorer: paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ─── Reentrancy Guard ────────────────────────────────────────────
    uint256 private _status = 1;
    modifier nonReentrant() { require(_status != 2, "TokenScorer: reentrant"); _status = 2; _; _status = 1; }

    // ─── Enums & Structs ─────────────────────────────────────────────
    enum RequestStatus { Pending, Scored, Disputed, Resolved }

    /// @notice Auditor profile with staking
    struct Auditor {
        uint256 stake;
        uint256 reputation;     // 0-1000
        uint256 totalScores;
        uint256 slashCount;
        uint256 joinedAt;
        bool active;
    }

    /// @notice A scoring request for a token
    struct ScoreRequest {
        address requester;
        address tokenAddress;
        RequestStatus status;
        uint256 bounty;          // payment for auditors
        uint256 createdAt;
        uint256 resolvedAt;
        uint256 submissionCount;
    }

    /// @notice An individual auditor's score submission
    struct ScoreSubmission {
        address auditor;
        uint256 requestId;
        uint256 score;           // 0-100 (0 = max risk, 100 = safe)
        bytes32 reportHash;      // IPFS hash of detailed report
        uint256 timestamp;
    }

    /// @notice Aggregated score for a token
    struct TokenScore {
        uint256 averageScore;
        uint256 totalSubmissions;
        uint256 lastUpdated;
        bool hasScore;
    }

    // ─── State ───────────────────────────────────────────────────────
    uint256 public nextRequestId = 1;
    uint256 public nextSubmissionId = 1;
    uint256 public minAuditorStake = 0.05 ether;
    uint256 public minBounty = 0.001 ether;
    uint256 public slashPercentage = 10; // 10% of stake
    uint256 public constant INITIAL_REPUTATION = 100;
    uint256 public constant MAX_REPUTATION = 1000;
    uint256 public constant MIN_SUBMISSIONS_FOR_SCORE = 2;

    mapping(address => Auditor) public auditors;
    mapping(uint256 => ScoreRequest) public requests;
    mapping(uint256 => ScoreSubmission) public scoreSubmissions;
    mapping(uint256 => uint256[]) public requestSubmissions; // requestId => submissionIds
    mapping(address => TokenScore) public tokenScores;
    mapping(uint256 => mapping(address => bool)) public hasSubmitted; // requestId => auditor => submitted
    mapping(address => uint256[]) public auditorSubmissions; // auditor => submissionIds

    // ─── Events ──────────────────────────────────────────────────────
    event AuditorStaked(address indexed auditor, uint256 amount, uint256 totalStake);
    event AuditorUnstaked(address indexed auditor, uint256 amount);
    event AuditorSlashed(address indexed auditor, uint256 slashAmount, string reason);
    event ScoreRequested(uint256 indexed requestId, address indexed requester, address indexed tokenAddress, uint256 bounty);
    event ScoreSubmitted(uint256 indexed submissionId, uint256 indexed requestId, address indexed auditor, uint256 score);
    event ScoreFinalized(uint256 indexed requestId, address indexed tokenAddress, uint256 averageScore);
    event ReputationUpdated(address indexed auditor, uint256 oldRep, uint256 newRep);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
    }

    // ─── Auditor Management ──────────────────────────────────────────

    /// @notice Stake to become an auditor
    function stakeAsAuditor() external payable whenNotPaused {
        require(msg.value >= minAuditorStake, "TokenScorer: insufficient stake");

        Auditor storage auditor = auditors[msg.sender];
        if (!auditor.active) {
            auditor.reputation = INITIAL_REPUTATION;
            auditor.joinedAt = block.timestamp;
            auditor.active = true;
        }
        auditor.stake += msg.value;

        emit AuditorStaked(msg.sender, msg.value, auditor.stake);
    }

    /// @notice Withdraw auditor stake
    /// @param amount Amount to withdraw
    function unstakeAuditor(uint256 amount) external nonReentrant {
        Auditor storage auditor = auditors[msg.sender];
        require(auditor.active, "TokenScorer: not an auditor");
        require(amount > 0 && amount <= auditor.stake, "TokenScorer: invalid amount");

        auditor.stake -= amount;
        if (auditor.stake < minAuditorStake) {
            auditor.active = false;
        }

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "TokenScorer: unstake failed");

        emit AuditorUnstaked(msg.sender, amount);
    }

    // ─── Score Requests ──────────────────────────────────────────────

    /// @notice Request a token risk score
    /// @param tokenAddress The token contract to evaluate
    function requestScore(address tokenAddress) external payable whenNotPaused {
        require(tokenAddress != address(0), "TokenScorer: zero address");
        require(msg.value >= minBounty, "TokenScorer: bounty too low");

        uint256 requestId = nextRequestId++;
        requests[requestId] = ScoreRequest({
            requester: msg.sender,
            tokenAddress: tokenAddress,
            status: RequestStatus.Pending,
            bounty: msg.value,
            createdAt: block.timestamp,
            resolvedAt: 0,
            submissionCount: 0
        });

        emit ScoreRequested(requestId, msg.sender, tokenAddress, msg.value);
    }

    /// @notice Submit a score for a request (auditors only)
    /// @param requestId The scoring request ID
    /// @param score Risk score 0-100 (0 = max risk, 100 = safe)
    /// @param reportHash IPFS hash of the detailed audit report
    function submitScore(uint256 requestId, uint256 score, bytes32 reportHash) external whenNotPaused {
        Auditor storage auditor = auditors[msg.sender];
        require(auditor.active, "TokenScorer: not active auditor");
        require(score <= 100, "TokenScorer: score out of range");
        require(reportHash != bytes32(0), "TokenScorer: empty report hash");

        ScoreRequest storage request = requests[requestId];
        require(request.status == RequestStatus.Pending, "TokenScorer: request not pending");
        require(!hasSubmitted[requestId][msg.sender], "TokenScorer: already submitted");

        uint256 submissionId = nextSubmissionId++;
        scoreSubmissions[submissionId] = ScoreSubmission({
            auditor: msg.sender,
            requestId: requestId,
            score: score,
            reportHash: reportHash,
            timestamp: block.timestamp
        });

        requestSubmissions[requestId].push(submissionId);
        auditorSubmissions[msg.sender].push(submissionId);
        hasSubmitted[requestId][msg.sender] = true;
        request.submissionCount++;
        auditor.totalScores++;

        emit ScoreSubmitted(submissionId, requestId, msg.sender, score);

        // Auto-finalize if enough submissions received
        if (request.submissionCount >= MIN_SUBMISSIONS_FOR_SCORE) {
            _finalizeScore(requestId);
        }
    }

    // ─── Score Finalization ──────────────────────────────────────────

    /// @notice Manually finalize a score (owner, if auto-finalize didn't trigger)
    function finalizeScore(uint256 requestId) external {
        ScoreRequest storage request = requests[requestId];
        require(
            request.status == RequestStatus.Pending,
            "TokenScorer: request not pending"
        );
        require(
            request.submissionCount >= MIN_SUBMISSIONS_FOR_SCORE || msg.sender == owner,
            "TokenScorer: not enough submissions"
        );
        _finalizeScore(requestId);
    }

    function _finalizeScore(uint256 requestId) internal {
        ScoreRequest storage request = requests[requestId];
        uint256[] storage subIds = requestSubmissions[requestId];

        uint256 totalWeightedScore = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < subIds.length; i++) {
            ScoreSubmission storage sub = scoreSubmissions[subIds[i]];
            uint256 weight = auditors[sub.auditor].reputation;
            if (weight == 0) weight = 1;
            totalWeightedScore += sub.score * weight;
            totalWeight += weight;
        }

        uint256 avgScore = totalWeight > 0 ? totalWeightedScore / totalWeight : 0;

        request.status = RequestStatus.Scored;
        request.resolvedAt = block.timestamp;

        tokenScores[request.tokenAddress] = TokenScore({
            averageScore: avgScore,
            totalSubmissions: request.submissionCount,
            lastUpdated: block.timestamp,
            hasScore: true
        });

        // Distribute bounty to auditors equally
        if (request.bounty > 0 && subIds.length > 0) {
            uint256 perAuditor = request.bounty / subIds.length;
            for (uint256 i = 0; i < subIds.length; i++) {
                address auditorAddr = scoreSubmissions[subIds[i]].auditor;
                (bool success, ) = payable(auditorAddr).call{value: perAuditor}("");
                // If individual transfer fails, funds remain in contract
                if (!success) continue;
            }
        }

        emit ScoreFinalized(requestId, request.tokenAddress, avgScore);
    }

    // ─── Slashing ────────────────────────────────────────────────────

    /// @notice Slash an auditor for dishonest scoring (owner only)
    /// @param auditor_ The auditor to slash
    /// @param reason Description of the violation
    function slashAuditor(address auditor_, string calldata reason) external onlyOwner {
        Auditor storage auditor = auditors[auditor_];
        require(auditor.active, "TokenScorer: not active auditor");

        uint256 slashAmount = (auditor.stake * slashPercentage) / 100;
        auditor.stake -= slashAmount;
        auditor.slashCount++;

        // Reduce reputation
        uint256 oldRep = auditor.reputation;
        uint256 repPenalty = 50;
        auditor.reputation = auditor.reputation > repPenalty ? auditor.reputation - repPenalty : 0;

        if (auditor.stake < minAuditorStake) {
            auditor.active = false;
        }

        emit AuditorSlashed(auditor_, slashAmount, reason);
        emit ReputationUpdated(auditor_, oldRep, auditor.reputation);
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get the aggregated score for a token
    function getTokenScore(address tokenAddress)
        external
        view
        returns (uint256 score, uint256 submissions, uint256 lastUpdated, bool hasScore)
    {
        TokenScore storage ts = tokenScores[tokenAddress];
        return (ts.averageScore, ts.totalSubmissions, ts.lastUpdated, ts.hasScore);
    }

    /// @notice Get submission IDs for a request
    function getRequestSubmissions(uint256 requestId) external view returns (uint256[] memory) {
        return requestSubmissions[requestId];
    }

    /// @notice Get auditor info
    function getAuditorInfo(address auditor_)
        external
        view
        returns (uint256 stake, uint256 reputation, uint256 totalScores, uint256 slashCount, bool active)
    {
        Auditor storage a = auditors[auditor_];
        return (a.stake, a.reputation, a.totalScores, a.slashCount, a.active);
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function setMinStake(uint256 newMinStake) external onlyOwner {
        require(newMinStake > 0, "TokenScorer: zero stake");
        minAuditorStake = newMinStake;
    }

    function setMinBounty(uint256 newMinBounty) external onlyOwner {
        minBounty = newMinBounty;
    }

    function setSlashPercentage(uint256 newPercentage) external onlyOwner {
        require(newPercentage <= 50, "TokenScorer: slash too high");
        slashPercentage = newPercentage;
    }

    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = payable(owner).call{value: address(this).balance}("");
        require(success, "TokenScorer: withdraw failed");
    }

    receive() external payable {}
}
