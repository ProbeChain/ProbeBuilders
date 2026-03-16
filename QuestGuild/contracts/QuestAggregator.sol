// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title QuestAggregator
 * @author ProbeChain Builders
 * @notice Cross-game quest aggregator with completion tracking and reward claims
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London)
 */

// ──────────────────────────────────────────────────────────────
// Inline Ownable
// ──────────────────────────────────────────────────────────────
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: not owner");
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ──────────────────────────────────────────────────────────────
// Inline ReentrancyGuard
// ──────────────────────────────────────────────────────────────
abstract contract ReentrancyGuard {
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    constructor() { _status = _NOT_ENTERED; }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// ──────────────────────────────────────────────────────────────
// Inline Pausable
// ──────────────────────────────────────────────────────────────
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }

    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
}

// ──────────────────────────────────────────────────────────────
// QuestAggregator
// ──────────────────────────────────────────────────────────────
contract QuestAggregator is Ownable, ReentrancyGuard, Pausable {

    // ── Structs ──────────────────────────────────────────────
    struct QuestSource {
        address sourceContract;
        string gameName;
        bool active;
        uint256 questCount;
        uint256 registeredAt;
    }

    struct Quest {
        uint256 sourceId;
        string title;
        string descriptionHash;
        uint256 rewardAmount;
        uint256 expiry;
        bool active;
    }

    struct Completion {
        uint256 questId;
        address user;
        uint256 completedAt;
        bool rewardClaimed;
    }

    // ── State ────────────────────────────────────────────────
    uint256 public sourceCounter;
    uint256 public questCounter;
    uint256 public completionCounter;

    mapping(uint256 => QuestSource) public questSources;
    mapping(address => uint256) public sourceContractToId;
    mapping(uint256 => Quest) public quests;
    mapping(uint256 => Completion) public completions;

    /// @dev user => questId => completionId (0 = not completed)
    mapping(address => mapping(uint256 => uint256)) public userQuestCompletion;
    /// @dev user => list of completion IDs
    mapping(address => uint256[]) public userCompletions;
    /// @dev sourceId => list of quest IDs
    mapping(uint256 => uint256[]) public sourceQuests;

    // ── Events ───────────────────────────────────────────────
    event QuestSourceRegistered(uint256 indexed sourceId, address indexed sourceContract, string gameName);
    event QuestSourceToggled(uint256 indexed sourceId, bool active);
    event QuestPublished(uint256 indexed questId, uint256 indexed sourceId, string title, uint256 rewardAmount);
    event QuestCompleted(uint256 indexed completionId, address indexed user, uint256 indexed questId);
    event RewardClaimed(uint256 indexed completionId, address indexed user, uint256 amount);
    event FundsDeposited(address indexed depositor, uint256 amount);

    // ── Constructor ──────────────────────────────────────────
    constructor() {}

    // ── Receive ──────────────────────────────────────────────
    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }

    // ── Source Management ────────────────────────────────────

    /**
     * @notice Register a new quest source (game contract)
     * @param sourceContract Address of the game contract
     * @param gameName Human-readable name
     * @return sourceId The new source ID
     */
    function registerQuestSource(address sourceContract, string calldata gameName)
        external
        onlyOwner
        returns (uint256 sourceId)
    {
        require(sourceContract != address(0), "QuestAggregator: zero address");
        require(sourceContractToId[sourceContract] == 0, "QuestAggregator: already registered");

        sourceId = ++sourceCounter;
        questSources[sourceId] = QuestSource({
            sourceContract: sourceContract,
            gameName: gameName,
            active: true,
            questCount: 0,
            registeredAt: block.timestamp
        });
        sourceContractToId[sourceContract] = sourceId;

        emit QuestSourceRegistered(sourceId, sourceContract, gameName);
    }

    /**
     * @notice Toggle a quest source active/inactive
     * @param sourceId The source to toggle
     */
    function toggleQuestSource(uint256 sourceId) external onlyOwner {
        require(questSources[sourceId].sourceContract != address(0), "QuestAggregator: unknown source");
        questSources[sourceId].active = !questSources[sourceId].active;
        emit QuestSourceToggled(sourceId, questSources[sourceId].active);
    }

    // ── Quest Publishing ─────────────────────────────────────

    /**
     * @notice Publish a quest from a registered source
     * @param sourceId The quest source
     * @param title Quest title
     * @param descriptionHash IPFS hash of quest description
     * @param rewardAmount Wei reward for completion
     * @param expiry Timestamp when quest expires
     * @return questId The new quest ID
     */
    function publishQuest(
        uint256 sourceId,
        string calldata title,
        string calldata descriptionHash,
        uint256 rewardAmount,
        uint256 expiry
    ) external whenNotPaused returns (uint256 questId) {
        QuestSource storage src = questSources[sourceId];
        require(src.sourceContract != address(0), "QuestAggregator: unknown source");
        require(src.active, "QuestAggregator: source inactive");
        require(
            msg.sender == owner() || msg.sender == src.sourceContract,
            "QuestAggregator: unauthorized"
        );
        require(expiry > block.timestamp, "QuestAggregator: expiry in past");

        questId = ++questCounter;
        quests[questId] = Quest({
            sourceId: sourceId,
            title: title,
            descriptionHash: descriptionHash,
            rewardAmount: rewardAmount,
            expiry: expiry,
            active: true
        });
        src.questCount++;
        sourceQuests[sourceId].push(questId);

        emit QuestPublished(questId, sourceId, title, rewardAmount);
    }

    // ── Quest Aggregation ────────────────────────────────────

    /**
     * @notice Get all available (active, non-expired) quest IDs for a user
     * @param user The user address
     * @return questIds Array of available quest IDs
     */
    function aggregateQuests(address user) external view returns (uint256[] memory questIds) {
        uint256 count;
        // First pass: count available
        for (uint256 i = 1; i <= questCounter; i++) {
            Quest storage q = quests[i];
            if (q.active && q.expiry > block.timestamp && userQuestCompletion[user][i] == 0) {
                count++;
            }
        }
        // Second pass: populate
        questIds = new uint256[](count);
        uint256 idx;
        for (uint256 i = 1; i <= questCounter; i++) {
            Quest storage q = quests[i];
            if (q.active && q.expiry > block.timestamp && userQuestCompletion[user][i] == 0) {
                questIds[idx++] = i;
            }
        }
    }

    // ── Completion Tracking ──────────────────────────────────

    /**
     * @notice Track that a user completed a quest
     * @param user The user who completed the quest
     * @param questId The quest completed
     * @return completionId The completion record ID
     */
    function trackCompletion(address user, uint256 questId)
        external
        whenNotPaused
        returns (uint256 completionId)
    {
        Quest storage q = quests[questId];
        require(q.active, "QuestAggregator: quest inactive");
        require(q.expiry > block.timestamp, "QuestAggregator: quest expired");

        QuestSource storage src = questSources[q.sourceId];
        require(
            msg.sender == owner() || msg.sender == src.sourceContract,
            "QuestAggregator: unauthorized"
        );
        require(userQuestCompletion[user][questId] == 0, "QuestAggregator: already completed");

        completionId = ++completionCounter;
        completions[completionId] = Completion({
            questId: questId,
            user: user,
            completedAt: block.timestamp,
            rewardClaimed: false
        });
        userQuestCompletion[user][questId] = completionId;
        userCompletions[user].push(completionId);

        emit QuestCompleted(completionId, user, questId);
    }

    // ── Reward Claiming ──────────────────────────────────────

    /**
     * @notice Claim aggregate rewards for all unclaimed completions
     * @return totalReward Total amount claimed
     */
    function claimAggregateRewards() external nonReentrant whenNotPaused returns (uint256 totalReward) {
        uint256[] storage compIds = userCompletions[msg.sender];
        require(compIds.length > 0, "QuestAggregator: no completions");

        for (uint256 i = 0; i < compIds.length; i++) {
            Completion storage c = completions[compIds[i]];
            if (!c.rewardClaimed) {
                Quest storage q = quests[c.questId];
                c.rewardClaimed = true;
                totalReward += q.rewardAmount;
            }
        }

        require(totalReward > 0, "QuestAggregator: nothing to claim");
        require(address(this).balance >= totalReward, "QuestAggregator: insufficient funds");

        (bool sent,) = msg.sender.call{value: totalReward}("");
        require(sent, "QuestAggregator: transfer failed");

        emit RewardClaimed(0, msg.sender, totalReward);
    }

    // ── View Helpers ─────────────────────────────────────────

    function getUserCompletions(address user) external view returns (uint256[] memory) {
        return userCompletions[user];
    }

    function getSourceQuests(uint256 sourceId) external view returns (uint256[] memory) {
        return sourceQuests[sourceId];
    }
}
