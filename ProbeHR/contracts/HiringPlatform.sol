// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title HiringPlatform
 * @author ProbeChain Labs
 * @notice Decentralized hiring platform with escrow-based job postings,
 *         candidate applications, hiring, completion, and dispute resolution.
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
contract HiringPlatform is Ownable, ReentrancyGuard, Pausable {

    enum JobStatus { Open, Filled, Completed, Disputed, Cancelled }

    struct Job {
        uint256 id;
        address employer;
        string title;
        string description;
        uint256 budget;
        string[] skills;
        JobStatus status;
        address hiredCandidate;
        uint256 applicantCount;
        uint256 createdAt;
        uint256 completedAt;
    }

    struct Application {
        address candidate;
        bytes32 resumeHash;
        uint256 appliedAt;
    }

    uint256 private _nextJobId;
    mapping(uint256 => Job) public jobs;
    mapping(uint256 => Application[]) public jobApplications;
    mapping(uint256 => mapping(address => bool)) public hasApplied;
    mapping(address => uint256[]) public employerJobs;

    /// @notice Platform fee in basis points.
    uint256 public platformFeeBps;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public platformBalance;

    // ---- Events ----------------------------------------------------------
    event JobPosted(uint256 indexed jobId, address indexed employer, string title, uint256 budget);
    event ApplicationSubmitted(uint256 indexed jobId, address indexed candidate, bytes32 resumeHash);
    event CandidateHired(uint256 indexed jobId, address indexed candidate);
    event JobCompleted(uint256 indexed jobId, address indexed candidate, uint256 payout);
    event JobDisputed(uint256 indexed jobId, address indexed disputant);
    event DisputeResolved(uint256 indexed jobId, address indexed recipient, uint256 amount);
    event JobCancelled(uint256 indexed jobId);
    event PlatformFeeUpdated(uint256 newFeeBps);

    constructor(uint256 _platformFeeBps) {
        require(_platformFeeBps <= 1500, "Fee too high");
        platformFeeBps = _platformFeeBps;
        _nextJobId = 1;
    }

    // ---- Core Functions --------------------------------------------------

    /**
     * @notice Post a new job with escrowed budget.
     * @param title       Job title.
     * @param description Job description.
     * @param skills      Required skill tags.
     * @return jobId      The new job identifier.
     */
    function postJob(
        string calldata title,
        string calldata description,
        string[] calldata skills
    ) external payable whenNotPaused returns (uint256 jobId) {
        require(bytes(title).length > 0, "Empty title");
        require(msg.value > 0, "Zero budget");

        jobId = _nextJobId++;
        Job storage j = jobs[jobId];
        j.id = jobId;
        j.employer = msg.sender;
        j.title = title;
        j.description = description;
        j.budget = msg.value;
        j.status = JobStatus.Open;
        j.createdAt = block.timestamp;

        for (uint256 i = 0; i < skills.length; i++) {
            j.skills.push(skills[i]);
        }

        employerJobs[msg.sender].push(jobId);
        emit JobPosted(jobId, msg.sender, title, msg.value);
    }

    /**
     * @notice Apply for an open job.
     * @param jobId      The job to apply for.
     * @param resumeHash IPFS hash of resume/portfolio.
     */
    function applyForJob(uint256 jobId, bytes32 resumeHash) external whenNotPaused {
        Job storage j = jobs[jobId];
        require(j.id != 0, "Job not found");
        require(j.status == JobStatus.Open, "Job not open");
        require(!hasApplied[jobId][msg.sender], "Already applied");
        require(msg.sender != j.employer, "Employer cannot apply");

        hasApplied[jobId][msg.sender] = true;
        jobApplications[jobId].push(Application({
            candidate: msg.sender,
            resumeHash: resumeHash,
            appliedAt: block.timestamp
        }));
        j.applicantCount++;

        emit ApplicationSubmitted(jobId, msg.sender, resumeHash);
    }

    /**
     * @notice Hire a candidate for the job.
     * @param jobId            The job.
     * @param candidateAddress The candidate to hire.
     */
    function hireCandidate(uint256 jobId, address candidateAddress) external whenNotPaused {
        Job storage j = jobs[jobId];
        require(j.id != 0, "Job not found");
        require(msg.sender == j.employer, "Not employer");
        require(j.status == JobStatus.Open, "Job not open");
        require(hasApplied[jobId][candidateAddress], "Candidate not applied");

        j.hiredCandidate = candidateAddress;
        j.status = JobStatus.Filled;

        emit CandidateHired(jobId, candidateAddress);
    }

    /**
     * @notice Mark job as complete and release escrowed funds to hired candidate.
     * @param jobId The job to complete.
     */
    function completeJob(uint256 jobId) external nonReentrant whenNotPaused {
        Job storage j = jobs[jobId];
        require(j.id != 0, "Job not found");
        require(msg.sender == j.employer, "Not employer");
        require(j.status == JobStatus.Filled, "Job not filled");

        j.status = JobStatus.Completed;
        j.completedAt = block.timestamp;

        uint256 fee = (j.budget * platformFeeBps) / BPS_DENOMINATOR;
        uint256 payout = j.budget - fee;
        platformBalance += fee;

        (bool success, ) = payable(j.hiredCandidate).call{value: payout}("");
        require(success, "Payout failed");

        emit JobCompleted(jobId, j.hiredCandidate, payout);
    }

    /**
     * @notice Raise a dispute on a filled job.
     * @param jobId The job to dispute.
     */
    function disputeJob(uint256 jobId) external whenNotPaused {
        Job storage j = jobs[jobId];
        require(j.id != 0, "Job not found");
        require(j.status == JobStatus.Filled, "Job not filled");
        require(
            msg.sender == j.employer || msg.sender == j.hiredCandidate,
            "Not party to job"
        );

        j.status = JobStatus.Disputed;
        emit JobDisputed(jobId, msg.sender);
    }

    /**
     * @notice Owner resolves a dispute, sending funds to the chosen recipient.
     * @param jobId     The disputed job.
     * @param recipient Who receives the escrowed funds.
     */
    function resolveDispute(uint256 jobId, address recipient) external onlyOwner nonReentrant {
        Job storage j = jobs[jobId];
        require(j.status == JobStatus.Disputed, "Not disputed");
        require(
            recipient == j.employer || recipient == j.hiredCandidate,
            "Invalid recipient"
        );

        j.status = JobStatus.Completed;
        j.completedAt = block.timestamp;

        (bool success, ) = payable(recipient).call{value: j.budget}("");
        require(success, "Transfer failed");

        emit DisputeResolved(jobId, recipient, j.budget);
    }

    /**
     * @notice Cancel an open job and refund the employer.
     * @param jobId The job to cancel.
     */
    function cancelJob(uint256 jobId) external nonReentrant whenNotPaused {
        Job storage j = jobs[jobId];
        require(j.id != 0, "Job not found");
        require(msg.sender == j.employer, "Not employer");
        require(j.status == JobStatus.Open, "Cannot cancel");

        j.status = JobStatus.Cancelled;

        (bool success, ) = payable(j.employer).call{value: j.budget}("");
        require(success, "Refund failed");

        emit JobCancelled(jobId);
    }

    // ---- Views -----------------------------------------------------------

    function getJob(uint256 jobId) external view returns (
        uint256 id, address employer, string memory title, string memory description,
        uint256 budget, JobStatus status, address hiredCandidate,
        uint256 applicantCount, uint256 createdAt
    ) {
        Job storage j = jobs[jobId];
        require(j.id != 0, "Not found");
        return (j.id, j.employer, j.title, j.description, j.budget,
                j.status, j.hiredCandidate, j.applicantCount, j.createdAt);
    }

    function getJobSkills(uint256 jobId) external view returns (string[] memory) {
        return jobs[jobId].skills;
    }

    function getApplications(uint256 jobId) external view returns (Application[] memory) {
        return jobApplications[jobId];
    }

    function getEmployerJobIds(address employer) external view returns (uint256[] memory) {
        return employerJobs[employer];
    }

    function totalJobs() external view returns (uint256) {
        return _nextJobId - 1;
    }

    // ---- Admin -----------------------------------------------------------

    function setPlatformFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= 1500, "Fee too high");
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
    }

    receive() external payable {}
}
