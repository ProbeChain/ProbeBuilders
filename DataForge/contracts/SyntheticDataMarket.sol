// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SyntheticDataMarket
 * @author ProbeChain
 * @notice Synthetic data marketplace with request, submission, validation, and payment lifecycle
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

contract SyntheticDataMarket is Ownable, ReentrancyGuard, Pausable {
    // --- Types ---
    enum RequestStatus { Open, Submitted, Validated, Paid, Rejected, Expired, Cancelled }

    struct DataRequest {
        uint256 id;
        address requester;
        string spec;
        uint256 budget;
        uint256 deadline;
        address generator;
        bytes32 dataHash;
        bytes32 statsHash;
        uint8 validationScore;
        RequestStatus status;
        uint256 createdAt;
    }

    // --- State ---
    uint256 public nextRequestId;
    uint256 public constant MIN_VALIDATION_SCORE = 70;
    uint256 public constant PLATFORM_FEE_BPS = 300; // 3%
    uint256 public constant VALIDATOR_REWARD_BPS = 500; // 5%

    mapping(uint256 => DataRequest) public requests;
    mapping(address => bool) public authorizedValidators;
    mapping(address => uint256) public generatorCompletions;
    mapping(address => uint256) public generatorEarnings;
    mapping(address => uint256) public validatorRewards;
    uint256 public platformFees;

    // --- Events ---
    event DataRequested(uint256 indexed requestId, address indexed requester, string spec, uint256 budget, uint256 deadline);
    event SynthDataSubmitted(uint256 indexed requestId, address indexed generator, bytes32 dataHash, bytes32 statsHash);
    event DataValidated(uint256 indexed requestId, address indexed validator, uint8 score);
    event PaymentClaimed(uint256 indexed requestId, address indexed generator, uint256 amount);
    event RequestCancelled(uint256 indexed requestId);
    event RequestExpired(uint256 indexed requestId);
    event ValidatorAuthorized(address indexed validator);
    event ValidatorRevoked(address indexed validator);
    event ValidatorRewardClaimed(address indexed validator, uint256 amount);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // --- Errors ---
    error RequestNotFound();
    error InvalidRequestStatus();
    error InsufficientBudget();
    error DeadlinePassed();
    error DeadlineNotPassed();
    error NotRequester();
    error NotGenerator();
    error NotValidator();
    error ValidationScoreTooLow();
    error NothingToClaim();
    error NothingToWithdraw();
    error InvalidDeadline();

    // --- Validator Management ---

    /// @notice Authorize a validator
    function authorizeValidator(address validator) external onlyOwner {
        authorizedValidators[validator] = true;
        emit ValidatorAuthorized(validator);
    }

    /// @notice Revoke a validator
    function revokeValidator(address validator) external onlyOwner {
        authorizedValidators[validator] = false;
        emit ValidatorRevoked(validator);
    }

    // --- Request Lifecycle ---

    /// @notice Request synthetic data generation
    /// @param spec Specification of the desired synthetic data
    /// @param budget Total budget for the request
    /// @param deadline Deadline timestamp for submission
    /// @return requestId The ID of the created request
    function requestSynthData(
        string calldata spec,
        uint256 budget,
        uint256 deadline
    ) external payable whenNotPaused returns (uint256 requestId) {
        if (msg.value < budget || budget == 0) revert InsufficientBudget();
        if (deadline <= block.timestamp) revert InvalidDeadline();

        requestId = nextRequestId++;
        requests[requestId] = DataRequest({
            id: requestId,
            requester: msg.sender,
            spec: spec,
            budget: budget,
            deadline: deadline,
            generator: address(0),
            dataHash: bytes32(0),
            statsHash: bytes32(0),
            validationScore: 0,
            status: RequestStatus.Open,
            createdAt: block.timestamp
        });

        emit DataRequested(requestId, msg.sender, spec, budget, deadline);
    }

    /// @notice Submit synthetic data for a request
    /// @param requestId The request to fulfill
    /// @param dataHash Hash of the generated synthetic data
    /// @param statsHash Hash of the statistical validation report
    function submitSynthData(
        uint256 requestId,
        bytes32 dataHash,
        bytes32 statsHash
    ) external whenNotPaused {
        DataRequest storage req = requests[requestId];
        if (req.requester == address(0)) revert RequestNotFound();
        if (req.status != RequestStatus.Open) revert InvalidRequestStatus();
        if (block.timestamp > req.deadline) revert DeadlinePassed();

        req.generator = msg.sender;
        req.dataHash = dataHash;
        req.statsHash = statsHash;
        req.status = RequestStatus.Submitted;

        emit SynthDataSubmitted(requestId, msg.sender, dataHash, statsHash);
    }

    /// @notice Validate submitted synthetic data
    /// @param requestId The request to validate
    /// @param score Quality score (0-100)
    function validateData(uint256 requestId, uint8 score) external whenNotPaused {
        if (!authorizedValidators[msg.sender]) revert NotValidator();

        DataRequest storage req = requests[requestId];
        if (req.status != RequestStatus.Submitted) revert InvalidRequestStatus();

        req.validationScore = score;

        if (score >= MIN_VALIDATION_SCORE) {
            req.status = RequestStatus.Validated;

            // Calculate validator reward
            uint256 valReward = (req.budget * VALIDATOR_REWARD_BPS) / 10000;
            validatorRewards[msg.sender] += valReward;
        } else {
            req.status = RequestStatus.Rejected;
        }

        emit DataValidated(requestId, msg.sender, score);
    }

    /// @notice Claim payment for validated synthetic data
    /// @param requestId The request to claim payment for
    function claimPayment(uint256 requestId) external nonReentrant whenNotPaused {
        DataRequest storage req = requests[requestId];
        if (req.generator != msg.sender) revert NotGenerator();
        if (req.status != RequestStatus.Validated) revert InvalidRequestStatus();

        req.status = RequestStatus.Paid;

        uint256 fee = (req.budget * PLATFORM_FEE_BPS) / 10000;
        uint256 valReward = (req.budget * VALIDATOR_REWARD_BPS) / 10000;
        uint256 payment = req.budget - fee - valReward;

        platformFees += fee;
        generatorCompletions[msg.sender]++;
        generatorEarnings[msg.sender] += payment;

        payable(msg.sender).transfer(payment);
        emit PaymentClaimed(requestId, msg.sender, payment);
    }

    /// @notice Cancel an open request
    function cancelRequest(uint256 requestId) external nonReentrant {
        DataRequest storage req = requests[requestId];
        if (req.requester != msg.sender) revert NotRequester();
        if (req.status != RequestStatus.Open) revert InvalidRequestStatus();

        req.status = RequestStatus.Cancelled;
        payable(msg.sender).transfer(req.budget);
        emit RequestCancelled(requestId);
    }

    /// @notice Expire and refund a request past deadline with no submission
    function expireRequest(uint256 requestId) external nonReentrant {
        DataRequest storage req = requests[requestId];
        if (req.status != RequestStatus.Open) revert InvalidRequestStatus();
        if (block.timestamp <= req.deadline) revert DeadlineNotPassed();

        req.status = RequestStatus.Expired;
        payable(req.requester).transfer(req.budget);
        emit RequestExpired(requestId);
    }

    /// @notice Claim validator rewards
    function claimValidatorReward() external nonReentrant {
        uint256 amount = validatorRewards[msg.sender];
        if (amount == 0) revert NothingToClaim();
        validatorRewards[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit ValidatorRewardClaimed(msg.sender, amount);
    }

    /// @notice Withdraw platform fees
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = platformFees;
        if (amount == 0) revert NothingToWithdraw();
        platformFees = 0;
        payable(owner()).transfer(amount);
        emit FeesWithdrawn(owner(), amount);
    }
}
