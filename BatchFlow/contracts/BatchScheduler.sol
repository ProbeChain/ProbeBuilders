// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title BatchScheduler
 * @author ProbeChain
 * @notice Decentralized batch job scheduler on ProbeChain Rydberg Testnet
 * @dev Create batch jobs, claim work, submit results, finalize with payment distribution
 */
contract BatchScheduler {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() { require(msg.sender == _owner, "Not owner"); _; }
    event OwnershipTransferred(address indexed prev, address indexed next_);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _locked = 1;
    modifier nonReentrant() { require(_locked == 1, "Reentrant"); _locked = 2; _; _locked = 1; }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "Paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums & Structs ────────────────────────────────────────────────
    enum BatchStatus { Open, InProgress, Completed, Cancelled, Expired }
    enum JobItemStatus { Unclaimed, Claimed, Submitted, Verified }

    struct Batch {
        address creator;
        uint256 jobCount;
        uint256 priority; // 1=low, 2=medium, 3=high
        uint256 deadline;
        uint256 budget;
        uint256 completedJobs;
        BatchStatus status;
        uint256 createdAt;
    }

    struct JobItem {
        bytes32 jobHash;
        address worker;
        bytes32 resultHash;
        JobItemStatus status;
        uint256 claimedAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => Batch) public batches;
    mapping(uint256 => mapping(uint256 => JobItem)) public batchJobs;
    mapping(address => uint256) public pendingWithdrawals;
    mapping(address => uint256) public workerReputation;
    uint256 public nextBatchId;
    uint256 public platformFee = 200; // 2%
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public jobClaimTimeout = 30 minutes;

    // ─── Events ─────────────────────────────────────────────────────────
    event BatchCreated(uint256 indexed batchId, address indexed creator, uint256 jobCount, uint256 priority, uint256 budget);
    event JobClaimed(uint256 indexed batchId, uint256 indexed jobIndex, address indexed worker);
    event JobResultSubmitted(uint256 indexed batchId, uint256 indexed jobIndex, bytes32 resultHash);
    event BatchFinalized(uint256 indexed batchId, uint256 completedJobs, uint256 totalJobs);
    event BatchCancelled(uint256 indexed batchId);
    event ReputationUpdated(address indexed worker, uint256 newReputation);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Create a batch of jobs
     * @param jobHashes Array of job data hashes
     * @param priority Priority level (1-3)
     * @param deadline Timestamp deadline
     */
    function createBatch(
        bytes32[] calldata jobHashes,
        uint256 priority,
        uint256 deadline
    ) external payable whenNotPaused returns (uint256) {
        require(jobHashes.length > 0, "Empty jobs");
        require(jobHashes.length <= 100, "Too many jobs");
        require(priority >= 1 && priority <= 3, "Priority 1-3");
        require(deadline > block.timestamp, "Past deadline");
        require(msg.value > 0, "Zero budget");

        uint256 id = nextBatchId++;
        batches[id] = Batch({
            creator: msg.sender,
            jobCount: jobHashes.length,
            priority: priority,
            deadline: deadline,
            budget: msg.value,
            completedJobs: 0,
            status: BatchStatus.Open,
            createdAt: block.timestamp
        });

        for (uint256 i = 0; i < jobHashes.length; i++) {
            batchJobs[id][i] = JobItem({
                jobHash: jobHashes[i],
                worker: address(0),
                resultHash: bytes32(0),
                status: JobItemStatus.Unclaimed,
                claimedAt: 0
            });
        }

        emit BatchCreated(id, msg.sender, jobHashes.length, priority, msg.value);
        return id;
    }

    /**
     * @notice Claim a job from a batch
     * @param batchId The batch containing the job
     * @param jobIndex Index of the job to claim
     */
    function claimJob(uint256 batchId, uint256 jobIndex) external whenNotPaused {
        Batch storage b = batches[batchId];
        require(b.status == BatchStatus.Open || b.status == BatchStatus.InProgress, "Batch not active");
        require(block.timestamp < b.deadline, "Deadline passed");
        require(jobIndex < b.jobCount, "Invalid index");

        JobItem storage j = batchJobs[batchId][jobIndex];
        require(j.status == JobItemStatus.Unclaimed ||
            (j.status == JobItemStatus.Claimed && block.timestamp > j.claimedAt + jobClaimTimeout),
            "Job not available"
        );

        j.worker = msg.sender;
        j.status = JobItemStatus.Claimed;
        j.claimedAt = block.timestamp;

        if (b.status == BatchStatus.Open) {
            b.status = BatchStatus.InProgress;
        }

        emit JobClaimed(batchId, jobIndex, msg.sender);
    }

    /**
     * @notice Submit result for a claimed job
     * @param batchId The batch
     * @param jobIndex The job index
     * @param resultHash Hash of the result
     */
    function submitJobResult(
        uint256 batchId,
        uint256 jobIndex,
        bytes32 resultHash
    ) external whenNotPaused {
        Batch storage b = batches[batchId];
        require(b.status == BatchStatus.InProgress, "Batch not in progress");
        require(jobIndex < b.jobCount, "Invalid index");

        JobItem storage j = batchJobs[batchId][jobIndex];
        require(j.status == JobItemStatus.Claimed, "Not claimed");
        require(msg.sender == j.worker, "Not worker");
        require(resultHash != bytes32(0), "Empty result");

        j.resultHash = resultHash;
        j.status = JobItemStatus.Submitted;
        b.completedJobs++;

        workerReputation[msg.sender]++;
        emit JobResultSubmitted(batchId, jobIndex, resultHash);
        emit ReputationUpdated(msg.sender, workerReputation[msg.sender]);
    }

    /**
     * @notice Finalize a batch and distribute payments
     * @param batchId The batch to finalize
     */
    function finalizeBatch(uint256 batchId) external whenNotPaused nonReentrant {
        Batch storage b = batches[batchId];
        require(
            msg.sender == b.creator || msg.sender == _owner ||
            block.timestamp >= b.deadline,
            "Not authorized"
        );
        require(b.status == BatchStatus.InProgress || b.status == BatchStatus.Open, "Not active");

        b.status = BatchStatus.Completed;
        uint256 completed = b.completedJobs;

        if (completed == 0) {
            pendingWithdrawals[b.creator] += b.budget;
            emit BatchFinalized(batchId, 0, b.jobCount);
            return;
        }

        uint256 fee = (b.budget * platformFee) / FEE_DENOMINATOR;
        pendingWithdrawals[_owner] += fee;
        uint256 distributable = b.budget - fee;
        uint256 perJob = distributable / completed;

        for (uint256 i = 0; i < b.jobCount; i++) {
            JobItem storage j = batchJobs[batchId][i];
            if (j.status == JobItemStatus.Submitted) {
                j.status = JobItemStatus.Verified;
                pendingWithdrawals[j.worker] += perJob;
            }
        }

        // Return remainder to creator
        uint256 distributed = perJob * completed;
        uint256 remainder = distributable - distributed;
        if (remainder > 0) {
            pendingWithdrawals[b.creator] += remainder;
        }

        emit BatchFinalized(batchId, completed, b.jobCount);
    }

    /**
     * @notice Cancel an open batch
     * @param batchId The batch to cancel
     */
    function cancelBatch(uint256 batchId) external nonReentrant {
        Batch storage b = batches[batchId];
        require(msg.sender == b.creator, "Not creator");
        require(b.status == BatchStatus.Open, "Not open");

        b.status = BatchStatus.Cancelled;
        payable(msg.sender).transfer(b.budget);
        emit BatchCancelled(batchId);
    }

    /**
     * @notice Withdraw pending balance
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Get job details
     */
    function getJobDetails(uint256 batchId, uint256 jobIndex) external view returns (
        bytes32 jobHash, address worker, bytes32 resultHash, JobItemStatus status
    ) {
        JobItem storage j = batchJobs[batchId][jobIndex];
        return (j.jobHash, j.worker, j.resultHash, j.status);
    }
}
