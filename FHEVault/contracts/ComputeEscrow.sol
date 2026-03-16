// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ComputeEscrow
 * @author ProbeChain
 * @notice Encrypted computation escrow with worker staking and dispute resolution
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London)
 */

// --- Inline Ownable ---
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorized(address account);
    error OwnableInvalidOwner(address owner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorized(msg.sender);
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(newOwner);
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// --- Inline ReentrancyGuard ---
abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardReentrantCall();
        _status = 2;
        _;
        _status = 1;
    }
}

// --- Inline Pausable ---
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();

    modifier whenNotPaused() {
        if (_paused) revert ContractPaused();
        _;
    }

    function paused() public view returns (bool) { return _paused; }

    function pause() external onlyOwner {
        if (_paused) revert ContractPaused();
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        if (!_paused) revert ContractNotPaused();
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract ComputeEscrow is Ownable, ReentrancyGuard, Pausable {
    // --- Types ---
    enum JobStatus { Open, Accepted, ResultSubmitted, Approved, Disputed, Resolved, Cancelled }

    struct Job {
        uint256 id;
        address requester;
        bytes32 inputHash;
        string computeSpec;
        uint256 reward;
        address worker;
        bytes32 resultHash;
        bytes32 proofHash;
        JobStatus status;
        uint256 createdAt;
        uint256 deadline;
    }

    // --- State ---
    uint256 public nextJobId;
    uint256 public constant MIN_WORKER_STAKE = 0.1 ether;
    uint256 public constant JOB_TIMEOUT = 7 days;
    uint256 public constant DISPUTE_FEE_BPS = 500; // 5%

    mapping(uint256 => Job) public jobs;
    mapping(address => uint256) public workerStakes;
    mapping(address => uint256) public workerCompletedJobs;
    mapping(address => uint256) public workerDisputeCount;

    // --- Events ---
    event JobCreated(uint256 indexed jobId, address indexed requester, bytes32 inputHash, uint256 reward);
    event JobAccepted(uint256 indexed jobId, address indexed worker);
    event ResultSubmitted(uint256 indexed jobId, bytes32 resultHash, bytes32 proofHash);
    event ResultApproved(uint256 indexed jobId, address indexed requester);
    event ResultDisputed(uint256 indexed jobId, address indexed requester);
    event DisputeResolved(uint256 indexed jobId, bool workerFavored);
    event JobCancelled(uint256 indexed jobId);
    event WorkerStaked(address indexed worker, uint256 amount);
    event WorkerUnstaked(address indexed worker, uint256 amount);

    // --- Errors ---
    error JobNotFound();
    error InvalidJobStatus();
    error InsufficientReward();
    error InsufficientStake();
    error NotRequester();
    error NotWorker();
    error NotOwnerOrRequester();
    error JobExpired();
    error WorkerHasActiveJobs();

    // --- Worker Staking ---

    /// @notice Stake tokens to become a compute worker
    function stakeAsWorker() external payable whenNotPaused {
        if (msg.value < MIN_WORKER_STAKE) revert InsufficientStake();
        workerStakes[msg.sender] += msg.value;
        emit WorkerStaked(msg.sender, msg.value);
    }

    /// @notice Unstake tokens
    function unstakeWorker(uint256 amount) external nonReentrant {
        if (workerStakes[msg.sender] < amount) revert InsufficientStake();
        workerStakes[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit WorkerUnstaked(msg.sender, amount);
    }

    // --- Job Lifecycle ---

    /// @notice Create a new computation job
    /// @param inputHash Hash of the encrypted input data
    /// @param computeSpec Specification of the computation to perform
    /// @return jobId The ID of the created job
    function createJob(
        bytes32 inputHash,
        string calldata computeSpec,
        uint256 reward
    ) external payable whenNotPaused returns (uint256 jobId) {
        if (msg.value < reward || reward == 0) revert InsufficientReward();

        jobId = nextJobId++;
        jobs[jobId] = Job({
            id: jobId,
            requester: msg.sender,
            inputHash: inputHash,
            computeSpec: computeSpec,
            reward: reward,
            worker: address(0),
            resultHash: bytes32(0),
            proofHash: bytes32(0),
            status: JobStatus.Open,
            createdAt: block.timestamp,
            deadline: block.timestamp + JOB_TIMEOUT
        });

        emit JobCreated(jobId, msg.sender, inputHash, reward);
    }

    /// @notice Accept an open computation job
    /// @param jobId The job to accept
    function acceptJob(uint256 jobId) external whenNotPaused {
        Job storage job = jobs[jobId];
        if (job.requester == address(0)) revert JobNotFound();
        if (job.status != JobStatus.Open) revert InvalidJobStatus();
        if (workerStakes[msg.sender] < MIN_WORKER_STAKE) revert InsufficientStake();
        if (block.timestamp > job.deadline) revert JobExpired();

        job.worker = msg.sender;
        job.status = JobStatus.Accepted;
        emit JobAccepted(jobId, msg.sender);
    }

    /// @notice Submit computation result
    /// @param jobId The job to submit result for
    /// @param resultHash Hash of the encrypted result
    /// @param proofHash Hash of the computation proof
    function submitResult(uint256 jobId, bytes32 resultHash, bytes32 proofHash) external whenNotPaused {
        Job storage job = jobs[jobId];
        if (job.worker != msg.sender) revert NotWorker();
        if (job.status != JobStatus.Accepted) revert InvalidJobStatus();

        job.resultHash = resultHash;
        job.proofHash = proofHash;
        job.status = JobStatus.ResultSubmitted;

        emit ResultSubmitted(jobId, resultHash, proofHash);
    }

    /// @notice Approve the submitted result and release payment
    /// @param jobId The job to approve
    function approveResult(uint256 jobId) external nonReentrant whenNotPaused {
        Job storage job = jobs[jobId];
        if (job.requester != msg.sender) revert NotRequester();
        if (job.status != JobStatus.ResultSubmitted) revert InvalidJobStatus();

        job.status = JobStatus.Approved;
        workerCompletedJobs[job.worker]++;
        payable(job.worker).transfer(job.reward);

        emit ResultApproved(jobId, msg.sender);
    }

    /// @notice Dispute the submitted result
    /// @param jobId The job to dispute
    function disputeResult(uint256 jobId) external whenNotPaused {
        Job storage job = jobs[jobId];
        if (job.requester != msg.sender) revert NotRequester();
        if (job.status != JobStatus.ResultSubmitted) revert InvalidJobStatus();

        job.status = JobStatus.Disputed;
        emit ResultDisputed(jobId, msg.sender);
    }

    /// @notice Resolve a dispute (owner only)
    /// @param jobId The disputed job
    /// @param workerFavored Whether the worker should receive payment
    function resolveDispute(uint256 jobId, bool workerFavored) external onlyOwner nonReentrant {
        Job storage job = jobs[jobId];
        if (job.status != JobStatus.Disputed) revert InvalidJobStatus();

        job.status = JobStatus.Resolved;

        if (workerFavored) {
            uint256 fee = (job.reward * DISPUTE_FEE_BPS) / 10000;
            payable(job.worker).transfer(job.reward - fee);
            payable(owner()).transfer(fee);
            workerCompletedJobs[job.worker]++;
        } else {
            payable(job.requester).transfer(job.reward);
            workerDisputeCount[job.worker]++;
            // Slash portion of worker stake
            uint256 slash = workerStakes[job.worker] / 10;
            if (slash > 0) {
                workerStakes[job.worker] -= slash;
                payable(owner()).transfer(slash);
            }
        }

        emit DisputeResolved(jobId, workerFavored);
    }

    /// @notice Cancel an open job
    /// @param jobId The job to cancel
    function cancelJob(uint256 jobId) external nonReentrant {
        Job storage job = jobs[jobId];
        if (job.requester != msg.sender) revert NotRequester();
        if (job.status != JobStatus.Open) revert InvalidJobStatus();

        job.status = JobStatus.Cancelled;
        payable(msg.sender).transfer(job.reward);
        emit JobCancelled(jobId);
    }

    /// @notice Get worker reputation score (completed / (completed + disputes) * 100)
    function getWorkerReputation(address worker) external view returns (uint256) {
        uint256 total = workerCompletedJobs[worker] + workerDisputeCount[worker];
        if (total == 0) return 0;
        return (workerCompletedJobs[worker] * 100) / total;
    }
}
