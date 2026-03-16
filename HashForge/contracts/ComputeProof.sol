// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ComputeProof
 * @author ProbeChain
 * @notice Optimistic compute verification on ProbeChain Rydberg Testnet
 * @dev Submit compute jobs, verify results, challenge with counter-proofs, resolve disputes
 */
contract ComputeProof {
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
    enum JobStatus { Submitted, Verified, Challenged, Resolved, Finalized }

    struct ComputeJob {
        address submitter;
        bytes32 computeHash;
        bytes32 expectedResultHash;
        bytes32 actualResultHash;
        bytes32 proofData;
        address verifier;
        JobStatus status;
        uint256 stake;
        uint256 challengeDeadline;
        address challenger;
        bytes32 counterProof;
        uint256 submittedAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => ComputeJob) public jobs;
    mapping(address => uint256) public pendingWithdrawals;
    mapping(address => bool) public arbiters;
    uint256 public nextJobId;
    uint256 public challengePeriod = 1 hours;
    uint256 public minStake = 0.01 ether;

    // ─── Events ─────────────────────────────────────────────────────────
    event JobSubmitted(uint256 indexed jobId, address indexed submitter, bytes32 computeHash);
    event ComputationVerified(uint256 indexed jobId, address indexed verifier, bytes32 resultHash);
    event ResultChallenged(uint256 indexed jobId, address indexed challenger, bytes32 counterProof);
    event ChallengeResolved(uint256 indexed jobId, bool challengerWon, address winner);
    event JobFinalized(uint256 indexed jobId);
    event ArbiterUpdated(address indexed arbiter, bool status);
    event StakeSlashed(uint256 indexed jobId, address indexed slashed, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Admin ──────────────────────────────────────────────────────────
    function setArbiter(address arbiter, bool status) external onlyOwner {
        arbiters[arbiter] = status;
        emit ArbiterUpdated(arbiter, status);
    }

    function setChallengePeriod(uint256 period) external onlyOwner {
        require(period >= 10 minutes && period <= 7 days, "Invalid period");
        challengePeriod = period;
    }

    function setMinStake(uint256 stake) external onlyOwner {
        minStake = stake;
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Submit a compute job for verification
     * @param computeHash Hash of the computation to perform
     * @param expectedResultHash Expected hash of the correct result
     */
    function submitJob(
        bytes32 computeHash,
        bytes32 expectedResultHash
    ) external payable whenNotPaused returns (uint256) {
        require(computeHash != bytes32(0), "Empty compute hash");
        require(expectedResultHash != bytes32(0), "Empty result hash");
        require(msg.value >= minStake, "Below min stake");

        uint256 id = nextJobId++;
        jobs[id] = ComputeJob({
            submitter: msg.sender,
            computeHash: computeHash,
            expectedResultHash: expectedResultHash,
            actualResultHash: bytes32(0),
            proofData: bytes32(0),
            verifier: address(0),
            status: JobStatus.Submitted,
            stake: msg.value,
            challengeDeadline: 0,
            challenger: address(0),
            counterProof: bytes32(0),
            submittedAt: block.timestamp
        });

        emit JobSubmitted(id, msg.sender, computeHash);
        return id;
    }

    /**
     * @notice Verify a computation (optimistic verification)
     * @param jobId The job to verify
     * @param resultHash Hash of the computed result
     * @param proofData Proof of correct computation
     */
    function verifyComputation(
        uint256 jobId,
        bytes32 resultHash,
        bytes32 proofData
    ) external payable whenNotPaused {
        ComputeJob storage j = jobs[jobId];
        require(j.status == JobStatus.Submitted, "Not submitted");
        require(resultHash != bytes32(0), "Empty result");
        require(msg.value >= minStake, "Below min stake");

        j.actualResultHash = resultHash;
        j.proofData = proofData;
        j.verifier = msg.sender;
        j.status = JobStatus.Verified;
        j.stake += msg.value;
        j.challengeDeadline = block.timestamp + challengePeriod;

        emit ComputationVerified(jobId, msg.sender, resultHash);
    }

    /**
     * @notice Challenge a verified result
     * @param jobId The job to challenge
     * @param counterProof Counter-proof showing incorrect result
     */
    function challengeResult(
        uint256 jobId,
        bytes32 counterProof
    ) external payable whenNotPaused {
        ComputeJob storage j = jobs[jobId];
        require(j.status == JobStatus.Verified, "Not verified");
        require(block.timestamp < j.challengeDeadline, "Challenge period over");
        require(msg.sender != j.verifier, "Verifier cannot challenge");
        require(counterProof != bytes32(0), "Empty counter-proof");
        require(msg.value >= minStake, "Below min stake");

        j.challenger = msg.sender;
        j.counterProof = counterProof;
        j.status = JobStatus.Challenged;
        j.stake += msg.value;

        emit ResultChallenged(jobId, msg.sender, counterProof);
    }

    /**
     * @notice Resolve a challenge (arbiter only)
     * @param jobId The challenged job
     * @param challengerWon True if challenger's proof is correct
     */
    function resolveChallenge(uint256 jobId, bool challengerWon) external whenNotPaused nonReentrant {
        require(arbiters[msg.sender] || msg.sender == _owner, "Not arbiter");
        ComputeJob storage j = jobs[jobId];
        require(j.status == JobStatus.Challenged, "Not challenged");

        j.status = JobStatus.Resolved;
        address winner;

        if (challengerWon) {
            winner = j.challenger;
            pendingWithdrawals[j.challenger] += j.stake;
            emit StakeSlashed(jobId, j.verifier, j.stake);
        } else {
            winner = j.verifier;
            pendingWithdrawals[j.verifier] += j.stake;
            emit StakeSlashed(jobId, j.challenger, j.stake);
        }

        emit ChallengeResolved(jobId, challengerWon, winner);
    }

    /**
     * @notice Finalize a job after challenge period (no challenge raised)
     * @param jobId The job to finalize
     */
    function finalizeJob(uint256 jobId) external whenNotPaused nonReentrant {
        ComputeJob storage j = jobs[jobId];
        require(j.status == JobStatus.Verified, "Not verified");
        require(block.timestamp >= j.challengeDeadline, "Challenge period active");

        j.status = JobStatus.Finalized;
        // Return stakes to both parties
        uint256 verifierStake = j.stake / 2;
        uint256 submitterStake = j.stake - verifierStake;
        pendingWithdrawals[j.verifier] += verifierStake;
        pendingWithdrawals[j.submitter] += submitterStake;

        emit JobFinalized(jobId);
    }

    /**
     * @notice Withdraw pending balance
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }
}
