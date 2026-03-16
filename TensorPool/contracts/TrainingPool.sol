// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TrainingPool
 * @author ProbeChain
 * @notice Decentralized ML training cluster on ProbeChain Rydberg Testnet
 * @dev Create training jobs, join pools with GPUs, submit and verify results, claim rewards
 */
contract TrainingPool {
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
    enum JobStatus { Open, InProgress, Completed, Cancelled }

    struct TrainingJob {
        address creator;
        bytes32 modelHash;
        bytes32 datasetHash;
        uint256 epochs;
        uint256 budget;
        JobStatus status;
        uint256 totalGPUs;
        bytes32 finalWeightsHash;
        uint256 bestLossScore;
        address bestContributor;
        uint256 createdAt;
    }

    struct Contributor {
        address contributor;
        uint256 gpuCount;
        bytes32 weightsHash;
        uint256 lossScore;
        bool submitted;
        bool rewarded;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => TrainingJob) public jobs;
    mapping(uint256 => mapping(address => Contributor)) public contributors;
    mapping(uint256 => address[]) private _jobContributors;
    mapping(address => bool) public verifiers;
    uint256 public nextJobId;
    uint256 public platformFee = 200; // 2%
    uint256 public constant FEE_DENOMINATOR = 10000;

    // ─── Events ─────────────────────────────────────────────────────────
    event JobCreated(uint256 indexed jobId, address indexed creator, bytes32 modelHash, uint256 budget);
    event PoolJoined(uint256 indexed jobId, address indexed contributor, uint256 gpuCount);
    event ResultSubmitted(uint256 indexed jobId, address indexed contributor, bytes32 weightsHash, uint256 lossScore);
    event ResultVerified(uint256 indexed jobId, bytes32 finalWeightsHash, address indexed bestContributor);
    event RewardClaimed(uint256 indexed jobId, address indexed contributor, uint256 amount);
    event VerifierUpdated(address indexed verifier, bool status);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Admin ──────────────────────────────────────────────────────────
    function setVerifier(address verifier, bool status) external onlyOwner {
        verifiers[verifier] = status;
        emit VerifierUpdated(verifier, status);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Create a new training job
     * @param modelHash Hash of the model architecture
     * @param datasetHash Hash of the training dataset
     * @param epochs Number of training epochs
     */
    function createTrainingJob(
        bytes32 modelHash,
        bytes32 datasetHash,
        uint256 epochs
    ) external payable whenNotPaused returns (uint256) {
        require(modelHash != bytes32(0), "Empty model hash");
        require(datasetHash != bytes32(0), "Empty dataset hash");
        require(epochs > 0, "Zero epochs");
        require(msg.value > 0, "Zero budget");

        uint256 id = nextJobId++;
        jobs[id] = TrainingJob({
            creator: msg.sender,
            modelHash: modelHash,
            datasetHash: datasetHash,
            epochs: epochs,
            budget: msg.value,
            status: JobStatus.Open,
            totalGPUs: 0,
            finalWeightsHash: bytes32(0),
            bestLossScore: type(uint256).max,
            bestContributor: address(0),
            createdAt: block.timestamp
        });

        emit JobCreated(id, msg.sender, modelHash, msg.value);
        return id;
    }

    /**
     * @notice Join a training pool with GPUs
     * @param jobId The job to join
     * @param gpuCount Number of GPUs to contribute
     */
    function joinPool(uint256 jobId, uint256 gpuCount) external whenNotPaused {
        TrainingJob storage j = jobs[jobId];
        require(j.status == JobStatus.Open, "Job not open");
        require(gpuCount > 0, "Zero GPUs");
        require(contributors[jobId][msg.sender].gpuCount == 0, "Already joined");

        contributors[jobId][msg.sender] = Contributor({
            contributor: msg.sender,
            gpuCount: gpuCount,
            weightsHash: bytes32(0),
            lossScore: 0,
            submitted: false,
            rewarded: false
        });

        _jobContributors[jobId].push(msg.sender);
        j.totalGPUs += gpuCount;
        j.status = JobStatus.InProgress;

        emit PoolJoined(jobId, msg.sender, gpuCount);
    }

    /**
     * @notice Submit training result
     * @param jobId The training job
     * @param weightsHash Hash of trained weights
     * @param lossScore Loss score (lower is better)
     */
    function submitResult(
        uint256 jobId,
        bytes32 weightsHash,
        uint256 lossScore
    ) external whenNotPaused {
        TrainingJob storage j = jobs[jobId];
        require(j.status == JobStatus.InProgress, "Job not in progress");
        Contributor storage c = contributors[jobId][msg.sender];
        require(c.gpuCount > 0, "Not contributor");
        require(!c.submitted, "Already submitted");

        c.weightsHash = weightsHash;
        c.lossScore = lossScore;
        c.submitted = true;

        if (lossScore < j.bestLossScore) {
            j.bestLossScore = lossScore;
            j.bestContributor = msg.sender;
            j.finalWeightsHash = weightsHash;
        }

        emit ResultSubmitted(jobId, msg.sender, weightsHash, lossScore);
    }

    /**
     * @notice Verify result and complete job (verifier or creator)
     * @param jobId The training job to verify
     */
    function verifyResult(uint256 jobId) external whenNotPaused {
        require(verifiers[msg.sender] || msg.sender == jobs[jobId].creator, "Not authorized");
        TrainingJob storage j = jobs[jobId];
        require(j.status == JobStatus.InProgress, "Job not in progress");
        require(j.bestContributor != address(0), "No results");

        j.status = JobStatus.Completed;
        emit ResultVerified(jobId, j.finalWeightsHash, j.bestContributor);
    }

    /**
     * @notice Claim reward for completed job
     * @param jobId The completed job
     */
    function claimReward(uint256 jobId) external whenNotPaused nonReentrant {
        TrainingJob storage j = jobs[jobId];
        require(j.status == JobStatus.Completed, "Job not completed");
        Contributor storage c = contributors[jobId][msg.sender];
        require(c.gpuCount > 0, "Not contributor");
        require(c.submitted, "Not submitted");
        require(!c.rewarded, "Already rewarded");

        c.rewarded = true;
        uint256 fee = (j.budget * platformFee) / FEE_DENOMINATOR;
        uint256 distributable = j.budget - fee;
        uint256 reward = (distributable * c.gpuCount) / j.totalGPUs;

        // Best contributor gets a 20% bonus from fee portion
        if (msg.sender == j.bestContributor) {
            reward += fee / 5;
        }

        payable(msg.sender).transfer(reward);
        emit RewardClaimed(jobId, msg.sender, reward);
    }

    /**
     * @notice Get all contributor addresses for a job
     */
    function getJobContributors(uint256 jobId) external view returns (address[] memory) {
        return _jobContributors[jobId];
    }

    /**
     * @notice Cancel an open job (creator only)
     */
    function cancelJob(uint256 jobId) external nonReentrant {
        TrainingJob storage j = jobs[jobId];
        require(msg.sender == j.creator, "Not creator");
        require(j.status == JobStatus.Open, "Not open");
        j.status = JobStatus.Cancelled;
        payable(msg.sender).transfer(j.budget);
    }
}
