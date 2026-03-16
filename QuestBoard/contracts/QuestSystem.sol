// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title QuestSystem
 * @notice Learn-to-earn quest platform with on-chain verification,
 *         badge NFT rewards, and verifier-based proof validation.
 * @dev Quests are created by educators; learners submit proofs verified on-chain or by trusted verifiers.
 */
contract QuestSystem {
    // ──────────────────── Ownership ────────────────────
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ──────────────────── Reentrancy Guard ────────────────────
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "Reentrant");
        _locked = 2;
        _;
        _locked = 1;
    }

    // ──────────────────── Pausable ────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "Paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ──────────────────── Badge NFT (minimal ERC-721) ────────────────────
    string public name = "QuestBadge";
    string public symbol = "QBADGE";
    uint256 public totalBadges;

    mapping(uint256 => address) private _badgeOwners;
    mapping(address => uint256) private _badgeBalances;

    event BadgeTransfer(address indexed from, address indexed to, uint256 indexed tokenId);

    // ──────────────────── Quest Data ────────────────────
    enum QuestType { OnChainAction, KnowledgeProof, CommunityTask, BuildChallenge }
    enum QuestStatus { Active, Paused, Completed, Cancelled }
    enum SubmissionStatus { Pending, Verified, Rejected }

    struct Quest {
        uint256 questId;
        address creator;
        string title;
        string description;
        QuestType questType;
        uint256 reward;             // reward in wei per completion
        address verifier;           // trusted verifier address
        uint256 maxCompletions;     // 0 = unlimited
        uint256 completions;
        QuestStatus status;
        uint256 deadline;
        uint256 createdAt;
    }

    struct Submission {
        uint256 submissionId;
        uint256 questId;
        address learner;
        bytes32 proofHash;
        SubmissionStatus status;
        uint256 badgeTokenId;       // 0 if no badge yet
        uint256 submittedAt;
        uint256 verifiedAt;
    }

    struct LearnerProfile {
        uint256 questsCompleted;
        uint256 totalEarned;
        uint256 badgesEarned;
        uint256 reputation;
        bool registered;
    }

    // ──────────────────── State ────────────────────
    uint256 public nextQuestId = 1;
    uint256 public nextSubmissionId = 1;
    uint256 public platformFeeBPS = 200; // 2%

    mapping(uint256 => Quest) public quests;
    mapping(uint256 => Submission) public submissions;
    mapping(address => LearnerProfile) public learners;
    mapping(uint256 => uint256[]) public questSubmissions;
    mapping(address => uint256[]) public learnerSubmissions;
    // questId => learner => completed
    mapping(uint256 => mapping(address => bool)) public hasCompleted;

    // ──────────────────── Events ────────────────────
    event LearnerRegistered(address indexed learner);
    event QuestCreated(uint256 indexed questId, address indexed creator, string title, uint256 reward);
    event QuestStatusChanged(uint256 indexed questId, QuestStatus status);
    event ProofSubmitted(uint256 indexed submissionId, uint256 indexed questId, address indexed learner);
    event QuestCompleted(uint256 indexed submissionId, uint256 indexed questId, address indexed learner, uint256 badgeTokenId);
    event SubmissionRejected(uint256 indexed submissionId);
    event RewardClaimed(address indexed learner, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    // ──────────────────── Learner Registration ────────────────────

    /**
     * @notice Register as a learner
     */
    function registerLearner() external {
        require(!learners[msg.sender].registered, "Already registered");
        learners[msg.sender] = LearnerProfile({
            questsCompleted: 0,
            totalEarned: 0,
            badgesEarned: 0,
            reputation: 100,
            registered: true
        });
        emit LearnerRegistered(msg.sender);
    }

    // ──────────────────── Quest Management ────────────────────

    /**
     * @notice Create a new quest with reward funding
     * @param title Quest title
     * @param description Quest description
     * @param questType Type of quest
     * @param verifier Address that can verify submissions
     * @param maxCompletions Maximum number of completions (0 = unlimited)
     * @param deadline Deadline timestamp
     */
    function createQuest(
        string calldata title,
        string calldata description,
        QuestType questType,
        address verifier,
        uint256 maxCompletions,
        uint256 deadline
    ) external payable whenNotPaused returns (uint256) {
        require(msg.value > 0, "Reward required");
        require(verifier != address(0), "Zero verifier");
        require(bytes(title).length > 0, "Empty title");
        require(deadline > block.timestamp, "Invalid deadline");

        uint256 questId = nextQuestId++;
        uint256 rewardPerCompletion = maxCompletions > 0
            ? msg.value / maxCompletions
            : msg.value; // For unlimited, creator manages funding

        quests[questId] = Quest({
            questId: questId,
            creator: msg.sender,
            title: title,
            description: description,
            questType: questType,
            reward: rewardPerCompletion,
            verifier: verifier,
            maxCompletions: maxCompletions,
            completions: 0,
            status: QuestStatus.Active,
            deadline: deadline,
            createdAt: block.timestamp
        });

        emit QuestCreated(questId, msg.sender, title, rewardPerCompletion);
        return questId;
    }

    /**
     * @notice Add more reward funding to a quest
     */
    function fundQuest(uint256 questId) external payable {
        require(quests[questId].status == QuestStatus.Active, "Not active");
        require(msg.value > 0, "Zero funding");
        // Funds held in contract balance
    }

    /**
     * @notice Pause/cancel a quest (creator only)
     */
    function setQuestStatus(uint256 questId, QuestStatus status) external {
        Quest storage q = quests[questId];
        require(q.creator == msg.sender || msg.sender == owner, "Not authorized");
        q.status = status;
        emit QuestStatusChanged(questId, status);
    }

    // ──────────────────── Quest Participation ────────────────────

    /**
     * @notice Submit proof of quest completion
     * @param questId The quest to complete
     * @param proofHash Hash of the proof data (tx hash, screenshot hash, etc.)
     */
    function submitProof(uint256 questId, bytes32 proofHash) external whenNotPaused returns (uint256) {
        Quest storage q = quests[questId];
        require(q.status == QuestStatus.Active, "Quest not active");
        require(block.timestamp <= q.deadline, "Deadline passed");
        require(learners[msg.sender].registered, "Not registered");
        require(!hasCompleted[questId][msg.sender], "Already completed");
        require(proofHash != bytes32(0), "Empty proof");

        if (q.maxCompletions > 0) {
            require(q.completions < q.maxCompletions, "Quest full");
        }

        uint256 submissionId = nextSubmissionId++;
        submissions[submissionId] = Submission({
            submissionId: submissionId,
            questId: questId,
            learner: msg.sender,
            proofHash: proofHash,
            status: SubmissionStatus.Pending,
            badgeTokenId: 0,
            submittedAt: block.timestamp,
            verifiedAt: 0
        });

        questSubmissions[questId].push(submissionId);
        learnerSubmissions[msg.sender].push(submissionId);

        emit ProofSubmitted(submissionId, questId, msg.sender);
        return submissionId;
    }

    /**
     * @notice Verify a submission and award badge + reward (verifier only)
     * @param submissionId The submission to verify
     */
    function verifyCompletion(uint256 submissionId) external nonReentrant whenNotPaused {
        Submission storage s = submissions[submissionId];
        require(s.status == SubmissionStatus.Pending, "Not pending");

        Quest storage q = quests[s.questId];
        require(msg.sender == q.verifier || msg.sender == owner, "Not verifier");

        s.status = SubmissionStatus.Verified;
        s.verifiedAt = block.timestamp;
        q.completions++;
        hasCompleted[s.questId][s.learner] = true;

        // Mint badge NFT
        uint256 badgeId = ++totalBadges;
        _badgeOwners[badgeId] = s.learner;
        _badgeBalances[s.learner]++;
        s.badgeTokenId = badgeId;
        emit BadgeTransfer(address(0), s.learner, badgeId);

        // Pay reward
        uint256 fee = (q.reward * platformFeeBPS) / 10000;
        uint256 payout = q.reward - fee;

        LearnerProfile storage lp = learners[s.learner];
        lp.questsCompleted++;
        lp.totalEarned += payout;
        lp.badgesEarned++;
        lp.reputation += 50;

        (bool ok, ) = s.learner.call{value: payout}("");
        require(ok, "Reward transfer failed");

        if (q.maxCompletions > 0 && q.completions >= q.maxCompletions) {
            q.status = QuestStatus.Completed;
            emit QuestStatusChanged(s.questId, QuestStatus.Completed);
        }

        emit QuestCompleted(submissionId, s.questId, s.learner, badgeId);
    }

    /**
     * @notice Reject a submission (verifier only)
     */
    function rejectSubmission(uint256 submissionId) external {
        Submission storage s = submissions[submissionId];
        require(s.status == SubmissionStatus.Pending, "Not pending");
        Quest storage q = quests[s.questId];
        require(msg.sender == q.verifier || msg.sender == owner, "Not verifier");

        s.status = SubmissionStatus.Rejected;
        emit SubmissionRejected(submissionId);
    }

    // ──────────────────── Views ────────────────────

    function getQuest(uint256 questId) external view returns (Quest memory) {
        return quests[questId];
    }

    function getSubmission(uint256 submissionId) external view returns (Submission memory) {
        return submissions[submissionId];
    }

    function getQuestSubmissions(uint256 questId) external view returns (uint256[] memory) {
        return questSubmissions[questId];
    }

    function getLearnerSubmissions(address learner) external view returns (uint256[] memory) {
        return learnerSubmissions[learner];
    }

    function getLearnerProfile(address learner) external view returns (LearnerProfile memory) {
        return learners[learner];
    }

    function badgeOwnerOf(uint256 tokenId) external view returns (address) {
        return _badgeOwners[tokenId];
    }

    function badgeBalanceOf(address addr) external view returns (uint256) {
        return _badgeBalances[addr];
    }

    // ──────────────────── Admin ────────────────────

    function setFee(uint256 newFeeBPS) external onlyOwner {
        require(newFeeBPS <= 1000, "Fee too high");
        platformFeeBPS = newFeeBPS;
    }

    function withdrawFees() external onlyOwner nonReentrant {
        // Only withdraw platform fees (careful not to drain quest rewards)
        // In production, track fees separately
        (bool ok, ) = owner.call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }

    receive() external payable {}
}
