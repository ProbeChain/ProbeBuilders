// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title RPGQuest
 * @author ProbeBuilders
 * @notice On-chain RPG quest system with characters, XP, levels, and quest prerequisites
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */
contract RPGQuest {
    // ─── Ownership ───────────────────────────────────────────────────
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "RPGQuest: caller is not the owner");
        _;
    }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "RPGQuest: zero address");
        owner = newOwner;
    }

    // ─── Pausable ────────────────────────────────────────────────────
    bool public paused;
    modifier whenNotPaused() {
        require(!paused, "RPGQuest: paused");
        _;
    }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ─── Reentrancy Guard ────────────────────────────────────────────
    uint256 private _status = 1;
    modifier nonReentrant() {
        require(_status != 2, "RPGQuest: reentrant call");
        _status = 2;
        _;
        _status = 1;
    }

    // ─── Enums ───────────────────────────────────────────────────────
    enum CharClass { Warrior, Mage, Ranger, Healer }
    enum QuestStatus { Open, InProgress, Completed, Failed }

    // ─── Structs ─────────────────────────────────────────────────────
    /// @notice Represents a player character
    struct Character {
        string name;
        CharClass class_;
        uint256 xp;
        uint256 level;
        uint256 strength;
        uint256 intelligence;
        uint256 agility;
        uint256 createdAt;
        uint256 questsCompleted;
    }

    /// @notice Represents a quest definition
    struct Quest {
        string name;
        string description;
        uint8 difficulty;          // 1-10
        uint256 xpReward;
        uint256 tokenReward;       // native token reward in wei
        uint256 minLevel;          // minimum character level
        uint256 prerequisiteQuestId; // 0 = none
        uint256 maxCompletions;
        uint256 totalCompletions;
        bool active;
    }

    /// @notice Tracks a player's progress on a specific quest
    struct QuestProgress {
        QuestStatus status;
        uint256 startedAt;
        uint256 completedAt;
        bytes32 proofHash;
    }

    // ─── State ───────────────────────────────────────────────────────
    uint256 public nextCharacterId = 1;
    uint256 public nextQuestId = 1;
    uint256 public constant XP_PER_LEVEL = 100;
    uint256 public constant MAX_LEVEL = 100;

    mapping(uint256 => Character) public characters;
    mapping(address => uint256) public playerCharacter; // one character per address
    mapping(uint256 => Quest) public quests;
    mapping(uint256 => mapping(uint256 => QuestProgress)) public questProgress; // charId => questId => progress
    mapping(uint256 => mapping(uint256 => bool)) public questCompletedBy; // charId => questId => completed

    // ─── Events ──────────────────────────────────────────────────────
    event CharacterCreated(uint256 indexed characterId, address indexed player, string name, CharClass class_);
    event QuestCreated(uint256 indexed questId, string name, uint8 difficulty, uint256 xpReward);
    event QuestAccepted(uint256 indexed characterId, uint256 indexed questId, uint256 timestamp);
    event QuestCompleted(uint256 indexed characterId, uint256 indexed questId, bytes32 proofHash, uint256 xpEarned);
    event RewardClaimed(uint256 indexed characterId, uint256 indexed questId, uint256 amount);
    event LevelUp(uint256 indexed characterId, uint256 newLevel);
    event QuestDeactivated(uint256 indexed questId);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor() payable {
        owner = msg.sender;
    }

    // ─── Character Management ────────────────────────────────────────

    /// @notice Create a new character (one per address)
    /// @param name The character's display name
    /// @param class_ The character class (0=Warrior,1=Mage,2=Ranger,3=Healer)
    function createCharacter(string calldata name, CharClass class_) external whenNotPaused {
        require(bytes(name).length > 0 && bytes(name).length <= 32, "RPGQuest: invalid name length");
        require(playerCharacter[msg.sender] == 0, "RPGQuest: already has character");

        uint256 charId = nextCharacterId++;
        uint256 str; uint256 intel; uint256 agi;
        if (class_ == CharClass.Warrior)  { str = 15; intel = 5;  agi = 10; }
        else if (class_ == CharClass.Mage)    { str = 5;  intel = 15; agi = 10; }
        else if (class_ == CharClass.Ranger)  { str = 10; intel = 5;  agi = 15; }
        else                                  { str = 5;  intel = 10; agi = 10; }

        characters[charId] = Character({
            name: name,
            class_: class_,
            xp: 0,
            level: 1,
            strength: str,
            intelligence: intel,
            agility: agi,
            createdAt: block.timestamp,
            questsCompleted: 0
        });
        playerCharacter[msg.sender] = charId;

        emit CharacterCreated(charId, msg.sender, name, class_);
    }

    // ─── Quest Management (Owner) ───────────────────────────────────

    /// @notice Create a new quest (owner only)
    function createQuest(
        string calldata name,
        string calldata description,
        uint8 difficulty,
        uint256 xpReward,
        uint256 tokenReward,
        uint256 minLevel,
        uint256 prerequisiteQuestId,
        uint256 maxCompletions
    ) external onlyOwner {
        require(difficulty >= 1 && difficulty <= 10, "RPGQuest: invalid difficulty");
        require(xpReward > 0, "RPGQuest: zero xp reward");
        require(maxCompletions > 0, "RPGQuest: zero max completions");
        if (prerequisiteQuestId > 0) {
            require(prerequisiteQuestId < nextQuestId, "RPGQuest: prerequisite does not exist");
        }

        uint256 questId = nextQuestId++;
        quests[questId] = Quest({
            name: name,
            description: description,
            difficulty: difficulty,
            xpReward: xpReward,
            tokenReward: tokenReward,
            minLevel: minLevel,
            prerequisiteQuestId: prerequisiteQuestId,
            maxCompletions: maxCompletions,
            totalCompletions: 0,
            active: true
        });

        emit QuestCreated(questId, name, difficulty, xpReward);
    }

    /// @notice Deactivate a quest
    function deactivateQuest(uint256 questId) external onlyOwner {
        require(quests[questId].active, "RPGQuest: quest not active");
        quests[questId].active = false;
        emit QuestDeactivated(questId);
    }

    // ─── Quest Gameplay ──────────────────────────────────────────────

    /// @notice Accept a quest
    /// @param questId The quest to accept
    function acceptQuest(uint256 questId) external whenNotPaused {
        uint256 charId = playerCharacter[msg.sender];
        require(charId != 0, "RPGQuest: no character");
        Quest storage quest = quests[questId];
        require(quest.active, "RPGQuest: quest not active");
        require(quest.totalCompletions < quest.maxCompletions, "RPGQuest: quest fully completed");
        require(characters[charId].level >= quest.minLevel, "RPGQuest: level too low");
        require(
            questProgress[charId][questId].status != QuestStatus.InProgress,
            "RPGQuest: quest already in progress"
        );
        require(!questCompletedBy[charId][questId], "RPGQuest: quest already completed by character");

        if (quest.prerequisiteQuestId > 0) {
            require(questCompletedBy[charId][quest.prerequisiteQuestId], "RPGQuest: prerequisite not met");
        }

        questProgress[charId][questId] = QuestProgress({
            status: QuestStatus.InProgress,
            startedAt: block.timestamp,
            completedAt: 0,
            proofHash: bytes32(0)
        });

        emit QuestAccepted(charId, questId, block.timestamp);
    }

    /// @notice Complete a quest with proof
    /// @param questId The quest to complete
    /// @param proofHash Hash of the off-chain proof of completion
    function completeQuest(uint256 questId, bytes32 proofHash) external whenNotPaused {
        uint256 charId = playerCharacter[msg.sender];
        require(charId != 0, "RPGQuest: no character");
        require(proofHash != bytes32(0), "RPGQuest: empty proof");

        QuestProgress storage progress = questProgress[charId][questId];
        require(progress.status == QuestStatus.InProgress, "RPGQuest: quest not in progress");

        Quest storage quest = quests[questId];

        progress.status = QuestStatus.Completed;
        progress.completedAt = block.timestamp;
        progress.proofHash = proofHash;

        quest.totalCompletions++;
        questCompletedBy[charId][questId] = true;

        // Grant XP and check for level up
        Character storage character = characters[charId];
        character.xp += quest.xpReward;
        character.questsCompleted++;

        uint256 newLevel = (character.xp / XP_PER_LEVEL) + 1;
        if (newLevel > MAX_LEVEL) newLevel = MAX_LEVEL;
        if (newLevel > character.level) {
            character.level = newLevel;
            // Stat boost on level up
            character.strength += quest.difficulty;
            character.intelligence += quest.difficulty;
            character.agility += quest.difficulty;
            emit LevelUp(charId, newLevel);
        }

        emit QuestCompleted(charId, questId, proofHash, quest.xpReward);
    }

    /// @notice Claim native token reward for a completed quest
    /// @param questId The quest to claim reward for
    function claimReward(uint256 questId) external nonReentrant whenNotPaused {
        uint256 charId = playerCharacter[msg.sender];
        require(charId != 0, "RPGQuest: no character");

        QuestProgress storage progress = questProgress[charId][questId];
        require(progress.status == QuestStatus.Completed, "RPGQuest: quest not completed");

        Quest storage quest = quests[questId];
        uint256 reward = quest.tokenReward;
        require(reward > 0, "RPGQuest: no token reward");
        require(address(this).balance >= reward, "RPGQuest: insufficient contract balance");

        // Mark as claimed by setting status to a terminal state
        // Re-use Failed status to indicate "reward claimed" to prevent double-claim
        progress.status = QuestStatus.Failed; // repurposed as "Claimed"

        (bool success, ) = payable(msg.sender).call{value: reward}("");
        require(success, "RPGQuest: transfer failed");

        emit RewardClaimed(charId, questId, reward);
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get full character info
    function getCharacter(uint256 charId)
        external
        view
        returns (
            string memory name,
            CharClass class_,
            uint256 xp,
            uint256 level,
            uint256 strength,
            uint256 intelligence,
            uint256 agility,
            uint256 questsCompleted
        )
    {
        Character storage c = characters[charId];
        return (c.name, c.class_, c.xp, c.level, c.strength, c.intelligence, c.agility, c.questsCompleted);
    }

    /// @notice Get quest info
    function getQuest(uint256 questId)
        external
        view
        returns (
            string memory name,
            uint8 difficulty,
            uint256 xpReward,
            uint256 tokenReward,
            uint256 minLevel,
            uint256 totalCompletions,
            bool active
        )
    {
        Quest storage q = quests[questId];
        return (q.name, q.difficulty, q.xpReward, q.tokenReward, q.minLevel, q.totalCompletions, q.active);
    }

    /// @notice Get quest progress for a character
    function getQuestProgress(uint256 charId, uint256 questId)
        external
        view
        returns (QuestStatus status, uint256 startedAt, uint256 completedAt, bytes32 proofHash)
    {
        QuestProgress storage p = questProgress[charId][questId];
        return (p.status, p.startedAt, p.completedAt, p.proofHash);
    }

    /// @notice Fund the contract for quest rewards
    receive() external payable {}

    /// @notice Withdraw remaining funds (owner only)
    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = payable(owner).call{value: address(this).balance}("");
        require(success, "RPGQuest: withdraw failed");
    }
}
