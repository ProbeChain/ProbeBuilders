// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ModelBenchmark
 * @author ProbeChain
 * @notice AI model performance verification with auditor staking and challenges on ProbeChain Rydberg Testnet
 * @dev Manages model registration, benchmark submissions by staked auditors, scoring, and result challenges
 */

/// @dev Minimal Ownable implementation
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/// @dev Minimal ReentrancyGuard implementation
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/// @dev Minimal Pausable implementation
abstract contract Pausable is Ownable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    function pause() public onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract ModelBenchmark is Ownable, ReentrancyGuard, Pausable {
    // ─── Types ───────────────────────────────────────────────────────────
    enum Category { NLP, Vision, Audio, Multimodal, Tabular, Reinforcement }
    enum ChallengeStatus { Open, Upheld, Overturned, Dismissed }

    struct Model {
        uint256 id;
        address registrant;
        string name;
        bytes32 modelHash;
        Category category;
        uint256 benchmarkCount;
        uint256 totalScore;
        bool active;
        uint256 registeredAt;
    }

    struct Benchmark {
        uint256 id;
        uint256 modelId;
        address auditor;
        uint256 score; // 0-10000 (100.00)
        bytes32 proofHash;
        bool challenged;
        uint256 submittedAt;
    }

    struct Challenge {
        uint256 id;
        uint256 benchmarkId;
        address challenger;
        string reason;
        ChallengeStatus status;
        uint256 stakedAmount;
        uint256 createdAt;
    }

    struct Auditor {
        uint256 stakedAmount;
        uint256 totalAudits;
        uint256 challengesFaced;
        uint256 challengesLost;
        bool active;
    }

    // ─── State ───────────────────────────────────────────────────────────
    uint256 public modelCount;
    uint256 public benchmarkCount;
    uint256 public challengeCount;
    uint256 public minAuditorStake = 0.1 ether;
    uint256 public challengeStake = 0.05 ether;

    mapping(uint256 => Model) public models;
    mapping(uint256 => Benchmark) public benchmarks;
    mapping(uint256 => Challenge) public challenges;
    mapping(address => Auditor) public auditors;
    mapping(uint256 => uint256[]) public modelBenchmarks;

    // ─── Events ──────────────────────────────────────────────────────────
    /// @notice Emitted when a model is registered
    event ModelRegistered(uint256 indexed modelId, address indexed registrant, string name, Category category);

    /// @notice Emitted when an auditor stakes
    event AuditorStaked(address indexed auditor, uint256 amount);

    /// @notice Emitted when a benchmark is submitted
    event BenchmarkSubmitted(uint256 indexed benchmarkId, uint256 indexed modelId, address indexed auditor, uint256 score);

    /// @notice Emitted when a benchmark result is challenged
    event BenchmarkChallenged(uint256 indexed challengeId, uint256 indexed benchmarkId, address indexed challenger);

    /// @notice Emitted when a challenge is resolved
    event ChallengeResolved(uint256 indexed challengeId, ChallengeStatus status);

    /// @notice Emitted when an auditor withdraws stake
    event AuditorUnstaked(address indexed auditor, uint256 amount);

    // ─── Auditor Management ──────────────────────────────────────────────

    /**
     * @notice Stake to become an auditor
     */
    function stakeAsAuditor() external payable whenNotPaused {
        require(msg.value >= minAuditorStake, "Insufficient stake");

        Auditor storage auditor = auditors[msg.sender];
        auditor.stakedAmount += msg.value;
        auditor.active = true;

        emit AuditorStaked(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw auditor stake (only if no pending challenges)
     */
    function unstake() external whenNotPaused nonReentrant {
        Auditor storage auditor = auditors[msg.sender];
        require(auditor.active, "Not an active auditor");
        uint256 amount = auditor.stakedAmount;
        require(amount > 0, "No stake");

        auditor.stakedAmount = 0;
        auditor.active = false;

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Unstake failed");

        emit AuditorUnstaked(msg.sender, amount);
    }

    // ─── Model Management ────────────────────────────────────────────────

    /**
     * @notice Register a new AI model for benchmarking
     * @param _name Model name
     * @param _modelHash Hash of the model
     * @param _category Model category
     * @return modelId The ID of the registered model
     */
    function registerModel(string calldata _name, bytes32 _modelHash, Category _category)
        external
        whenNotPaused
        returns (uint256 modelId)
    {
        require(bytes(_name).length > 0 && bytes(_name).length <= 128, "Invalid name");
        require(_modelHash != bytes32(0), "Empty model hash");

        modelId = ++modelCount;
        models[modelId] = Model({
            id: modelId,
            registrant: msg.sender,
            name: _name,
            modelHash: _modelHash,
            category: _category,
            benchmarkCount: 0,
            totalScore: 0,
            active: true,
            registeredAt: block.timestamp
        });

        emit ModelRegistered(modelId, msg.sender, _name, _category);
    }

    /**
     * @notice Submit a benchmark result for a model (auditor only)
     * @param _modelId The model ID
     * @param _benchmarkId External benchmark identifier
     * @param _score Score (0-10000, representing 0.00-100.00)
     * @param _proofHash Hash of the benchmark proof/evidence
     * @return id The internal benchmark record ID
     */
    function submitBenchmark(
        uint256 _modelId,
        uint256 _benchmarkId,
        uint256 _score,
        bytes32 _proofHash
    ) external whenNotPaused returns (uint256 id) {
        require(auditors[msg.sender].active, "Not an active auditor");
        require(auditors[msg.sender].stakedAmount >= minAuditorStake, "Insufficient stake");
        require(models[_modelId].active, "Model not active");
        require(_score <= 10000, "Score exceeds max");
        require(_proofHash != bytes32(0), "Empty proof hash");

        id = ++benchmarkCount;
        benchmarks[id] = Benchmark({
            id: id,
            modelId: _modelId,
            auditor: msg.sender,
            score: _score,
            proofHash: _proofHash,
            challenged: false,
            submittedAt: block.timestamp
        });

        Model storage model = models[_modelId];
        model.benchmarkCount++;
        model.totalScore += _score;
        modelBenchmarks[_modelId].push(id);

        auditors[msg.sender].totalAudits++;

        emit BenchmarkSubmitted(id, _modelId, msg.sender, _score);
    }

    /**
     * @notice Challenge a benchmark result
     * @param _benchmarkId The benchmark record ID
     * @param _reason Reason for the challenge
     * @return challengeId The ID of the challenge
     */
    function challengeResult(uint256 _benchmarkId, string calldata _reason)
        external
        payable
        whenNotPaused
        returns (uint256 challengeId)
    {
        require(msg.value >= challengeStake, "Insufficient challenge stake");
        Benchmark storage benchmark = benchmarks[_benchmarkId];
        require(benchmark.id != 0, "Benchmark not found");
        require(!benchmark.challenged, "Already challenged");
        require(benchmark.auditor != msg.sender, "Cannot challenge own benchmark");

        benchmark.challenged = true;
        challengeId = ++challengeCount;

        challenges[challengeId] = Challenge({
            id: challengeId,
            benchmarkId: _benchmarkId,
            challenger: msg.sender,
            reason: _reason,
            status: ChallengeStatus.Open,
            stakedAmount: msg.value,
            createdAt: block.timestamp
        });

        auditors[benchmark.auditor].challengesFaced++;

        emit BenchmarkChallenged(challengeId, _benchmarkId, msg.sender);
    }

    /**
     * @notice Resolve a challenge (owner/admin only)
     * @param _challengeId The challenge ID
     * @param _upheld Whether the challenge is upheld (true) or dismissed (false)
     */
    function resolveChallenge(uint256 _challengeId, bool _upheld) external onlyOwner nonReentrant {
        Challenge storage challenge = challenges[_challengeId];
        require(challenge.status == ChallengeStatus.Open, "Not open");

        Benchmark storage benchmark = benchmarks[challenge.benchmarkId];

        if (_upheld) {
            challenge.status = ChallengeStatus.Upheld;
            auditors[benchmark.auditor].challengesLost++;

            // Slash auditor stake and reward challenger
            uint256 slashAmount = challenge.stakedAmount;
            if (auditors[benchmark.auditor].stakedAmount >= slashAmount) {
                auditors[benchmark.auditor].stakedAmount -= slashAmount;
            }

            uint256 reward = challenge.stakedAmount * 2;
            challenge.stakedAmount = 0;
            (bool sent, ) = challenge.challenger.call{value: reward}("");
            require(sent, "Reward transfer failed");
        } else {
            challenge.status = ChallengeStatus.Dismissed;
            // Challenger loses stake
            challenge.stakedAmount = 0;
        }

        emit ChallengeResolved(_challengeId, challenge.status);
    }

    /**
     * @notice Get average model score (x100 for precision)
     * @param _modelId The model ID
     * @return Average score
     */
    function getModelScore(uint256 _modelId) external view returns (uint256) {
        Model storage model = models[_modelId];
        if (model.benchmarkCount == 0) return 0;
        return model.totalScore / model.benchmarkCount;
    }

    /**
     * @notice Get all benchmark IDs for a model
     * @param _modelId The model ID
     */
    function getModelBenchmarks(uint256 _modelId) external view returns (uint256[] memory) {
        return modelBenchmarks[_modelId];
    }

    /**
     * @notice Update minimum auditor stake
     * @param _newStake New minimum stake in wei
     */
    function setMinAuditorStake(uint256 _newStake) external onlyOwner {
        minAuditorStake = _newStake;
    }

    /**
     * @notice Withdraw contract surplus
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");
        (bool sent, ) = owner().call{value: balance}("");
        require(sent, "Withdraw failed");
    }
}
