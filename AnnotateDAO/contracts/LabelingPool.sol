// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title LabelingPool
 * @author ProbeChain
 * @notice Data labeling pool with task creation, label submission, validation, and consensus rewards
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

contract LabelingPool is Ownable, ReentrancyGuard, Pausable {
    // --- Types ---
    enum TaskStatus { Open, Full, Validated, Closed }

    struct LabelTask {
        uint256 id;
        address creator;
        bytes32 dataHash;
        string instructions;
        uint256 labelCount;
        uint256 rewardPerLabel;
        uint256 totalBudget;
        uint256 submittedLabels;
        uint256 validatedLabels;
        TaskStatus status;
        uint256 createdAt;
    }

    struct Label {
        uint256 id;
        uint256 taskId;
        address labeler;
        bytes32 labelHash;
        bool validated;
        bool correct;
        bool rewardClaimed;
        uint256 submittedAt;
    }

    // --- State ---
    uint256 public nextTaskId;
    uint256 public nextLabelId;
    uint256 public constant PLATFORM_FEE_BPS = 200; // 2%
    uint256 public constant VALIDATOR_REWARD_BPS = 300; // 3%

    mapping(uint256 => LabelTask) public tasks;
    mapping(uint256 => Label) public labels;
    mapping(uint256 => uint256[]) private _taskLabels;
    mapping(uint256 => mapping(address => bool)) public hasLabeled;
    mapping(address => bool) public authorizedValidators;
    mapping(address => uint256) public labelerCorrectCount;
    mapping(address => uint256) public labelerTotalCount;
    mapping(address => uint256) public pendingRewards;
    uint256 public platformFees;

    // --- Events ---
    event TaskCreated(uint256 indexed taskId, address indexed creator, bytes32 dataHash, uint256 labelCount, uint256 rewardPerLabel);
    event LabelSubmitted(uint256 indexed labelId, uint256 indexed taskId, address indexed labeler, bytes32 labelHash);
    event LabelValidated(uint256 indexed labelId, uint256 indexed taskId, address indexed validator, bool correct);
    event LabelRewardClaimed(uint256 indexed labelId, address indexed labeler, uint256 amount);
    event TaskClosed(uint256 indexed taskId);
    event ValidatorAuthorized(address indexed validator);
    event ValidatorRevoked(address indexed validator);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // --- Errors ---
    error TaskNotFound();
    error TaskNotOpen();
    error TaskFull();
    error AlreadyLabeled();
    error LabelNotFound();
    error LabelAlreadyValidated();
    error NotValidator();
    error NotLabeler();
    error NotTaskCreator();
    error RewardAlreadyClaimed();
    error LabelNotCorrect();
    error LabelNotValidated();
    error InsufficientBudget();
    error NothingToClaim();
    error NothingToWithdraw();

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

    // --- Task Management ---

    /// @notice Create a new labeling task
    /// @param dataHash Hash of the data to be labeled
    /// @param instructions Labeling instructions
    /// @param labelCount Number of labels required
    /// @param rewardPerLabel Reward per correct label in wei
    /// @return taskId The ID of the created task
    function createLabelTask(
        bytes32 dataHash,
        string calldata instructions,
        uint256 labelCount,
        uint256 rewardPerLabel
    ) external payable whenNotPaused returns (uint256 taskId) {
        uint256 totalBudget = labelCount * rewardPerLabel;
        uint256 fee = (totalBudget * PLATFORM_FEE_BPS) / 10000;
        uint256 valReward = (totalBudget * VALIDATOR_REWARD_BPS) / 10000;
        uint256 totalRequired = totalBudget + fee + valReward;

        if (msg.value < totalRequired) revert InsufficientBudget();

        taskId = nextTaskId++;
        tasks[taskId] = LabelTask({
            id: taskId,
            creator: msg.sender,
            dataHash: dataHash,
            instructions: instructions,
            labelCount: labelCount,
            rewardPerLabel: rewardPerLabel,
            totalBudget: msg.value,
            submittedLabels: 0,
            validatedLabels: 0,
            status: TaskStatus.Open,
            createdAt: block.timestamp
        });

        platformFees += fee;
        emit TaskCreated(taskId, msg.sender, dataHash, labelCount, rewardPerLabel);
    }

    /// @notice Submit a label for a task
    /// @param taskId The task to label
    /// @param labelHash Hash of the label data
    /// @return labelId The ID of the submitted label
    function submitLabel(
        uint256 taskId,
        bytes32 labelHash
    ) external whenNotPaused returns (uint256 labelId) {
        LabelTask storage task = tasks[taskId];
        if (task.creator == address(0)) revert TaskNotFound();
        if (task.status != TaskStatus.Open) revert TaskNotOpen();
        if (task.submittedLabels >= task.labelCount) revert TaskFull();
        if (hasLabeled[taskId][msg.sender]) revert AlreadyLabeled();

        labelId = nextLabelId++;
        labels[labelId] = Label({
            id: labelId,
            taskId: taskId,
            labeler: msg.sender,
            labelHash: labelHash,
            validated: false,
            correct: false,
            rewardClaimed: false,
            submittedAt: block.timestamp
        });

        hasLabeled[taskId][msg.sender] = true;
        task.submittedLabels++;
        _taskLabels[taskId].push(labelId);
        labelerTotalCount[msg.sender]++;

        if (task.submittedLabels >= task.labelCount) {
            task.status = TaskStatus.Full;
        }

        emit LabelSubmitted(labelId, taskId, msg.sender, labelHash);
    }

    /// @notice Validate a submitted label
    /// @param taskId The task the label belongs to
    /// @param labelId The label to validate
    /// @param correct Whether the label is correct
    function validateLabel(
        uint256 taskId,
        uint256 labelId,
        bool correct
    ) external whenNotPaused {
        if (!authorizedValidators[msg.sender]) revert NotValidator();

        Label storage label = labels[labelId];
        if (label.labeler == address(0)) revert LabelNotFound();
        if (label.taskId != taskId) revert LabelNotFound();
        if (label.validated) revert LabelAlreadyValidated();

        label.validated = true;
        label.correct = correct;

        LabelTask storage task = tasks[taskId];
        task.validatedLabels++;

        if (correct) {
            labelerCorrectCount[label.labeler]++;
            pendingRewards[label.labeler] += task.rewardPerLabel;
        }

        // Add validator reward
        uint256 valReward = (task.rewardPerLabel * VALIDATOR_REWARD_BPS) / 10000;
        pendingRewards[msg.sender] += valReward;

        // Check if all labels validated
        if (task.validatedLabels >= task.submittedLabels && task.status == TaskStatus.Full) {
            task.status = TaskStatus.Validated;
        }

        emit LabelValidated(labelId, taskId, msg.sender, correct);
    }

    /// @notice Claim accumulated labeling rewards
    function claimLabelReward() external nonReentrant {
        uint256 amount = pendingRewards[msg.sender];
        if (amount == 0) revert NothingToClaim();
        pendingRewards[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit LabelRewardClaimed(0, msg.sender, amount);
    }

    /// @notice Close a task and refund unused budget
    function closeTask(uint256 taskId) external nonReentrant {
        LabelTask storage task = tasks[taskId];
        if (task.creator != msg.sender) revert NotTaskCreator();
        if (task.status == TaskStatus.Closed) revert TaskNotOpen();

        task.status = TaskStatus.Closed;

        // Calculate used budget
        uint256 usedRewards = task.validatedLabels * task.rewardPerLabel;
        uint256 fee = (task.labelCount * task.rewardPerLabel * PLATFORM_FEE_BPS) / 10000;
        uint256 usedTotal = usedRewards + fee;

        if (task.totalBudget > usedTotal) {
            payable(msg.sender).transfer(task.totalBudget - usedTotal);
        }

        emit TaskClosed(taskId);
    }

    /// @notice Get labels for a task
    function getTaskLabels(uint256 taskId) external view returns (uint256[] memory) {
        return _taskLabels[taskId];
    }

    /// @notice Get labeler accuracy (correct / total * 100)
    function getLabelerAccuracy(address labeler) external view returns (uint256) {
        if (labelerTotalCount[labeler] == 0) return 0;
        return (labelerCorrectCount[labeler] * 100) / labelerTotalCount[labeler];
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
