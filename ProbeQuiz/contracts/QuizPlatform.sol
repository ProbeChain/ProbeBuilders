// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title QuizPlatform
 * @author ProbeChain Team
 * @notice Quiz-to-earn platform with on-chain answer verification
 * @dev Quiz creators fund rewards, participants submit answers and claim rewards
 */
contract QuizPlatform {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "QuizPlatform: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "QuizPlatform: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _guardStatus = 1;
    modifier nonReentrant() {
        require(_guardStatus == 1, "QuizPlatform: reentrant call");
        _guardStatus = 2;
        _;
        _guardStatus = 1;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "QuizPlatform: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Structs ────────────────────────────────────────────────────────
    struct Quiz {
        uint256 id;
        address creator;
        uint256 questionCount;
        uint256 rewardPerCorrect;
        uint256 maxAttempts;
        uint256 totalAttempts;
        uint256 balance;
        uint256 createdAt;
        bool active;
    }

    struct Attempt {
        address participant;
        uint256 quizId;
        uint256 correctCount;
        uint256 reward;
        bool claimed;
        uint256 attemptedAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public quizCount;
    uint256 public attemptCount;

    mapping(uint256 => Quiz) public quizzes;
    mapping(uint256 => bytes32[]) public quizQuestions;
    mapping(uint256 => bytes32[]) public quizAnswers;
    mapping(uint256 => Attempt) public attempts;
    mapping(uint256 => mapping(address => uint256)) public userAttemptCount;
    mapping(uint256 => mapping(address => uint256)) public lastAttemptId;
    mapping(address => uint256[]) public userAttempts;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a new quiz is created
    event QuizCreated(uint256 indexed quizId, address indexed creator, uint256 questionCount, uint256 rewardPerCorrect);
    /// @notice Emitted when answers are submitted
    event AnswersSubmitted(uint256 indexed attemptId, uint256 indexed quizId, address indexed participant, uint256 correctCount);
    /// @notice Emitted when rewards are claimed
    event RewardClaimed(uint256 indexed attemptId, address indexed participant, uint256 amount);
    /// @notice Emitted when a quiz is funded
    event QuizFunded(uint256 indexed quizId, uint256 amount);
    /// @notice Emitted when a quiz is deactivated
    event QuizDeactivated(uint256 indexed quizId);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Create a new quiz with questions and hashed correct answers
     * @param questions Array of question hashes (IPFS or keccak256)
     * @param correctAnswers Array of keccak256-hashed correct answers
     * @param rewardPerCorrect Reward per correct answer in wei
     * @param maxAttempts Maximum attempts per participant
     */
    function createQuiz(
        bytes32[] calldata questions,
        bytes32[] calldata correctAnswers,
        uint256 rewardPerCorrect,
        uint256 maxAttempts
    ) external payable whenNotPaused {
        require(questions.length > 0 && questions.length <= 50, "QuizPlatform: invalid question count");
        require(questions.length == correctAnswers.length, "QuizPlatform: length mismatch");
        require(rewardPerCorrect > 0, "QuizPlatform: zero reward");
        require(maxAttempts > 0, "QuizPlatform: zero attempts");
        require(msg.value >= rewardPerCorrect * questions.length, "QuizPlatform: insufficient funding");

        quizCount++;
        quizzes[quizCount] = Quiz({
            id: quizCount,
            creator: msg.sender,
            questionCount: questions.length,
            rewardPerCorrect: rewardPerCorrect,
            maxAttempts: maxAttempts,
            totalAttempts: 0,
            balance: msg.value,
            createdAt: block.timestamp,
            active: true
        });

        for (uint256 i = 0; i < questions.length; i++) {
            quizQuestions[quizCount].push(questions[i]);
            quizAnswers[quizCount].push(correctAnswers[i]);
        }

        emit QuizCreated(quizCount, msg.sender, questions.length, rewardPerCorrect);
    }

    /**
     * @notice Submit answers for a quiz
     * @param quizId Quiz to answer
     * @param answers Array of keccak256-hashed answers
     */
    function submitAnswers(
        uint256 quizId,
        bytes32[] calldata answers
    ) external whenNotPaused {
        Quiz storage quiz = quizzes[quizId];
        require(quiz.active, "QuizPlatform: quiz not active");
        require(answers.length == quiz.questionCount, "QuizPlatform: wrong answer count");
        require(
            userAttemptCount[quizId][msg.sender] < quiz.maxAttempts,
            "QuizPlatform: max attempts reached"
        );

        uint256 correctCount = 0;
        bytes32[] storage correct = quizAnswers[quizId];
        for (uint256 i = 0; i < answers.length; i++) {
            if (answers[i] == correct[i]) {
                correctCount++;
            }
        }

        uint256 reward = correctCount * quiz.rewardPerCorrect;
        if (reward > quiz.balance) {
            reward = quiz.balance;
        }

        attemptCount++;
        attempts[attemptCount] = Attempt({
            participant: msg.sender,
            quizId: quizId,
            correctCount: correctCount,
            reward: reward,
            claimed: false,
            attemptedAt: block.timestamp
        });

        userAttemptCount[quizId][msg.sender]++;
        lastAttemptId[quizId][msg.sender] = attemptCount;
        userAttempts[msg.sender].push(attemptCount);
        quiz.totalAttempts++;

        emit AnswersSubmitted(attemptCount, quizId, msg.sender, correctCount);
    }

    /**
     * @notice Claim reward for a quiz attempt
     * @param attemptId Attempt to claim reward for
     */
    function claimReward(uint256 attemptId) external nonReentrant whenNotPaused {
        Attempt storage attempt = attempts[attemptId];
        require(attempt.participant == msg.sender, "QuizPlatform: not participant");
        require(!attempt.claimed, "QuizPlatform: already claimed");
        require(attempt.reward > 0, "QuizPlatform: no reward");

        Quiz storage quiz = quizzes[attempt.quizId];
        require(quiz.balance >= attempt.reward, "QuizPlatform: insufficient balance");

        attempt.claimed = true;
        quiz.balance -= attempt.reward;

        (bool success, ) = payable(msg.sender).call{value: attempt.reward}("");
        require(success, "QuizPlatform: payment failed");

        emit RewardClaimed(attemptId, msg.sender, attempt.reward);
    }

    /**
     * @notice Fund an existing quiz with more rewards
     * @param quizId Quiz to fund
     */
    function fundQuiz(uint256 quizId) external payable {
        require(msg.value > 0, "QuizPlatform: zero amount");
        quizzes[quizId].balance += msg.value;
        emit QuizFunded(quizId, msg.value);
    }

    /**
     * @notice Deactivate a quiz and withdraw remaining balance
     * @param quizId Quiz to deactivate
     */
    function deactivateQuiz(uint256 quizId) external nonReentrant {
        Quiz storage quiz = quizzes[quizId];
        require(msg.sender == quiz.creator, "QuizPlatform: not creator");
        require(quiz.active, "QuizPlatform: already inactive");

        quiz.active = false;
        uint256 remaining = quiz.balance;
        quiz.balance = 0;

        if (remaining > 0) {
            (bool success, ) = payable(msg.sender).call{value: remaining}("");
            require(success, "QuizPlatform: withdrawal failed");
        }

        emit QuizDeactivated(quizId);
    }

    /**
     * @notice Get quiz questions
     * @param quizId Quiz ID
     * @return questions Array of question hashes
     */
    function getQuestions(uint256 quizId) external view returns (bytes32[] memory questions) {
        return quizQuestions[quizId];
    }

    /**
     * @notice Get user's attempt count for a quiz
     * @param quizId Quiz ID
     * @param user User address
     * @return count Number of attempts
     */
    function getUserAttempts(uint256 quizId, address user) external view returns (uint256 count) {
        return userAttemptCount[quizId][user];
    }
}
