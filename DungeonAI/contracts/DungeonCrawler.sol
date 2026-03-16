// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DungeonCrawler
 * @author ProbeChain Team
 * @notice On-chain dungeon crawler game with pseudo-random room encounters on ProbeChain
 * @dev Players enter dungeons, explore rooms with action choices, and claim loot rewards
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender); _; }
    function owner() public view virtual returns (address) { return _owner; }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner); _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardReentrantCall();
        _status = _ENTERED; _; _status = _NOT_ENTERED;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    error ExpectedPause();
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    modifier whenPaused() { if (!_paused) revert ExpectedPause(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

contract DungeonCrawler is Ownable, ReentrancyGuard, Pausable {
    enum Difficulty { Easy, Medium, Hard, Legendary }
    enum RoomType { Empty, Monster, Treasure, Trap, Boss }
    enum ActionChoice { Fight, Flee, Search, Sneak }
    enum RunStatus { Active, Completed, Failed }

    /// @notice Dungeon configuration
    struct Dungeon {
        uint256 id;
        Difficulty difficulty;
        uint256 roomCount;
        uint256 rewardPool;
        address creator;
        uint256 entryFee;
        uint256 createdAt;
        bool active;
    }

    /// @notice Player run through a dungeon
    struct DungeonRun {
        address player;
        uint256 dungeonId;
        uint256 currentRoom;
        uint256 health;
        uint256 score;
        uint256 lootEarned;
        RunStatus status;
        uint256 startedAt;
    }

    /// @notice Room encounter result
    struct RoomResult {
        RoomType roomType;
        ActionChoice action;
        bool success;
        uint256 healthChange;
        uint256 scoreGained;
        uint256 lootFound;
    }

    mapping(uint256 => Dungeon) private _dungeons;
    mapping(uint256 => mapping(address => DungeonRun)) private _runs;
    mapping(uint256 => mapping(address => mapping(uint256 => RoomResult))) private _roomResults;

    uint256 private _nextDungeonId = 1;
    uint256 public totalDungeons;
    uint256 public totalRuns;
    uint256 public minEntryFee = 0.001 ether;

    /// @notice Emitted when dungeon is created
    event DungeonCreated(uint256 indexed dungeonId, Difficulty difficulty, uint256 rooms, uint256 rewardPool);
    /// @notice Emitted when player enters dungeon
    event DungeonEntered(uint256 indexed dungeonId, address indexed player);
    /// @notice Emitted when a room is explored
    event RoomExplored(uint256 indexed dungeonId, address indexed player, uint256 roomId, RoomType roomType, bool success);
    /// @notice Emitted when loot is claimed
    event LootClaimed(uint256 indexed dungeonId, address indexed player, uint256 amount);
    /// @notice Emitted when player dies
    event PlayerDefeated(uint256 indexed dungeonId, address indexed player, uint256 room);

    error DungeonNotFound(uint256 dungeonId);
    error DungeonNotActive(uint256 dungeonId);
    error AlreadyInDungeon(uint256 dungeonId);
    error NotInDungeon(uint256 dungeonId);
    error RunNotActive(uint256 dungeonId);
    error InvalidRoom(uint256 roomId);
    error RunNotCompleted(uint256 dungeonId);
    error NoLootToClaim();
    error InsufficientFee(uint256 sent, uint256 required);
    error InvalidRoomCount();

    /**
     * @notice Create a new dungeon
     * @param difficulty The dungeon difficulty level
     * @param rooms Number of rooms (3-20)
     * @param rewards Additional reward amount added to entry fees
     * @return dungeonId The created dungeon ID
     */
    function createDungeon(
        Difficulty difficulty,
        uint256 rooms,
        uint256 rewards
    ) external payable whenNotPaused returns (uint256 dungeonId) {
        if (rooms < 3 || rooms > 20) revert InvalidRoomCount();

        uint256 diffMultiplier = uint256(difficulty) + 1;
        uint256 entryFee = minEntryFee * diffMultiplier;

        dungeonId = _nextDungeonId++;
        _dungeons[dungeonId] = Dungeon({
            id: dungeonId,
            difficulty: difficulty,
            roomCount: rooms,
            rewardPool: msg.value + rewards,
            creator: msg.sender,
            entryFee: entryFee,
            createdAt: block.timestamp,
            active: true
        });

        totalDungeons++;
        emit DungeonCreated(dungeonId, difficulty, rooms, msg.value);
    }

    /**
     * @notice Enter a dungeon
     * @param dungeonId The dungeon to enter
     */
    function enterDungeon(uint256 dungeonId) external payable whenNotPaused {
        Dungeon storage dungeon = _dungeons[dungeonId];
        if (dungeon.id == 0) revert DungeonNotFound(dungeonId);
        if (!dungeon.active) revert DungeonNotActive(dungeonId);
        if (_runs[dungeonId][msg.sender].status == RunStatus.Active) revert AlreadyInDungeon(dungeonId);
        if (msg.value < dungeon.entryFee) revert InsufficientFee(msg.value, dungeon.entryFee);

        uint256 startHealth = 100 + (4 - uint256(dungeon.difficulty)) * 25;

        _runs[dungeonId][msg.sender] = DungeonRun({
            player: msg.sender,
            dungeonId: dungeonId,
            currentRoom: 0,
            health: startHealth,
            score: 0,
            lootEarned: 0,
            status: RunStatus.Active,
            startedAt: block.timestamp
        });

        dungeon.rewardPool += msg.value;
        totalRuns++;

        emit DungeonEntered(dungeonId, msg.sender);
    }

    /**
     * @notice Explore the next room in a dungeon
     * @param dungeonId The dungeon being explored
     * @param roomId The room index to explore (must be currentRoom + 1)
     * @param actionChoice The action to take in the room
     * @return result The room encounter result
     */
    function exploreRoom(
        uint256 dungeonId,
        uint256 roomId,
        ActionChoice actionChoice
    ) external whenNotPaused returns (RoomResult memory result) {
        Dungeon storage dungeon = _dungeons[dungeonId];
        if (dungeon.id == 0) revert DungeonNotFound(dungeonId);

        DungeonRun storage run = _runs[dungeonId][msg.sender];
        if (run.status != RunStatus.Active) revert RunNotActive(dungeonId);
        if (roomId != run.currentRoom + 1) revert InvalidRoom(roomId);
        if (roomId > dungeon.roomCount) revert InvalidRoom(roomId);

        // Generate pseudo-random room type
        uint256 rand = uint256(keccak256(abi.encodePacked(
            dungeonId, roomId, msg.sender, block.timestamp, block.prevrandao
        )));
        RoomType roomType;
        if (roomId == dungeon.roomCount) {
            roomType = RoomType.Boss;
        } else {
            roomType = RoomType(rand % 4); // Empty, Monster, Treasure, Trap
        }

        // Resolve action
        uint256 actionRand = uint256(keccak256(abi.encodePacked(rand, uint256(actionChoice))));
        uint256 diffMod = uint256(dungeon.difficulty) + 1;
        bool success;
        uint256 healthChange;
        uint256 scoreGained;
        uint256 lootFound;

        if (roomType == RoomType.Empty) {
            success = true;
            healthChange = 5; // Heal
            scoreGained = 10;
        } else if (roomType == RoomType.Monster || roomType == RoomType.Boss) {
            success = (actionChoice == ActionChoice.Fight && actionRand % 100 > diffMod * 15)
                || (actionChoice == ActionChoice.Flee && actionRand % 100 > 40)
                || (actionChoice == ActionChoice.Sneak && actionRand % 100 > 50);

            if (success) {
                scoreGained = roomType == RoomType.Boss ? 100 * diffMod : 30 * diffMod;
                lootFound = roomType == RoomType.Boss ? dungeon.entryFee * 3 : dungeon.entryFee / 2;
            } else {
                healthChange = roomType == RoomType.Boss ? 50 * diffMod : 20 * diffMod;
            }
        } else if (roomType == RoomType.Treasure) {
            success = actionChoice == ActionChoice.Search || actionRand % 100 > 30;
            if (success) {
                lootFound = dungeon.entryFee;
                scoreGained = 20;
            }
        } else {
            // Trap
            success = actionChoice == ActionChoice.Sneak || actionRand % 100 > 60;
            if (!success) {
                healthChange = 15 * diffMod;
            }
            scoreGained = 5;
        }

        // Apply effects
        if (healthChange > 0 && roomType != RoomType.Empty) {
            run.health = run.health > healthChange ? run.health - healthChange : 0;
        } else if (roomType == RoomType.Empty) {
            run.health += healthChange;
        }

        run.score += scoreGained;
        run.lootEarned += lootFound;
        run.currentRoom = roomId;

        result = RoomResult({
            roomType: roomType,
            action: actionChoice,
            success: success,
            healthChange: healthChange,
            scoreGained: scoreGained,
            lootFound: lootFound
        });
        _roomResults[dungeonId][msg.sender][roomId] = result;

        // Check death
        if (run.health == 0) {
            run.status = RunStatus.Failed;
            emit PlayerDefeated(dungeonId, msg.sender, roomId);
            return result;
        }

        // Check completion
        if (roomId == dungeon.roomCount) {
            run.status = RunStatus.Completed;
        }

        emit RoomExplored(dungeonId, msg.sender, roomId, roomType, success);
    }

    /**
     * @notice Claim loot from a completed dungeon run
     * @param dungeonId The dungeon to claim from
     */
    function claimLoot(uint256 dungeonId) external nonReentrant whenNotPaused {
        DungeonRun storage run = _runs[dungeonId][msg.sender];
        if (run.player == address(0)) revert NotInDungeon(dungeonId);
        if (run.status != RunStatus.Completed) revert RunNotCompleted(dungeonId);
        if (run.lootEarned == 0) revert NoLootToClaim();

        uint256 loot = run.lootEarned;
        Dungeon storage dungeon = _dungeons[dungeonId];
        if (loot > dungeon.rewardPool) loot = dungeon.rewardPool;

        run.lootEarned = 0;
        dungeon.rewardPool -= loot;

        (bool success, ) = msg.sender.call{value: loot}("");
        require(success, "Loot transfer failed");

        emit LootClaimed(dungeonId, msg.sender, loot);
    }

    /// @notice Get dungeon info
    function getDungeon(uint256 dungeonId) external view returns (Dungeon memory) {
        if (_dungeons[dungeonId].id == 0) revert DungeonNotFound(dungeonId);
        return _dungeons[dungeonId];
    }

    /// @notice Get player run
    function getRun(uint256 dungeonId, address player) external view returns (DungeonRun memory) {
        return _runs[dungeonId][player];
    }

    /// @notice Get room result
    function getRoomResult(uint256 dungeonId, address player, uint256 roomId) external view returns (RoomResult memory) {
        return _roomResults[dungeonId][player][roomId];
    }

    /// @notice Set minimum entry fee
    function setMinEntryFee(uint256 fee) external onlyOwner { minEntryFee = fee; }

    /// @notice Deactivate a dungeon
    function deactivateDungeon(uint256 dungeonId) external onlyOwner {
        _dungeons[dungeonId].active = false;
    }

    receive() external payable {}
}
