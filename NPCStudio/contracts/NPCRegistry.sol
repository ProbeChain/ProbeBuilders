// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title NPCRegistry
 * @author ProbeChain Builders
 * @notice NPC behavior registry and marketplace for game developers
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London)
 */

// ──────────────────────────────────────────────────────────────
// Inline Ownable
// ──────────────────────────────────────────────────────────────
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed prev, address indexed next_);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address n) external onlyOwner {
        require(n != address(0), "Ownable: zero");
        emit OwnershipTransferred(_owner, n); _owner = n;
    }
}

// ──────────────────────────────────────────────────────────────
// Inline ReentrancyGuard
// ──────────────────────────────────────────────────────────────
abstract contract ReentrancyGuard {
    uint256 private _s = 1;
    modifier nonReentrant() { require(_s == 1, "ReentrancyGuard: reentrant"); _s = 2; _; _s = 1; }
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
// NPCRegistry
// ──────────────────────────────────────────────────────────────
contract NPCRegistry is Ownable, ReentrancyGuard, Pausable {

    // ── Enums ────────────────────────────────────────────────
    enum Personality { Friendly, Aggressive, Neutral, Mysterious, Comedic, Wise, Fearful }

    // ── Structs ──────────────────────────────────────────────
    struct NPC {
        string name;
        bytes32 behaviorHash;       // IPFS hash of behavior script/AI model
        Personality personality;
        uint256 gameId;
        address creator;
        uint256 interactionFee;     // Fee per interaction in wei
        uint256 totalInteractions;
        uint256 totalRatings;
        uint256 ratingSum;          // Sum of all ratings (1-5)
        uint256 totalEarnings;
        bool active;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Interaction {
        uint256 npcId;
        address user;
        uint256 paidAmount;
        uint256 timestamp;
    }

    struct Rating {
        uint256 npcId;
        address rater;
        uint8 score;                // 1-5
        uint256 timestamp;
    }

    // ── State ────────────────────────────────────────────────
    uint256 public npcCounter;
    uint256 public interactionCounter;
    uint256 public ratingCounter;
    uint256 public platformFeePercent = 10;

    mapping(uint256 => NPC) public npcs;
    mapping(uint256 => Interaction) public interactions;
    mapping(uint256 => Rating) public ratings;

    /// @dev gameId => list of NPC IDs
    mapping(uint256 => uint256[]) public gameNPCs;
    /// @dev creator => list of NPC IDs
    mapping(address => uint256[]) public creatorNPCs;
    /// @dev npcId => user => has interacted
    mapping(uint256 => mapping(address => bool)) public hasInteracted;
    /// @dev npcId => user => has rated
    mapping(uint256 => mapping(address => bool)) public hasRated;

    // ── Events ───────────────────────────────────────────────
    event NPCRegistered(uint256 indexed npcId, string name, bytes32 behaviorHash, Personality personality, uint256 gameId, address indexed creator);
    event BehaviorUpdated(uint256 indexed npcId, bytes32 oldHash, bytes32 newHash);
    event NPCInteraction(uint256 indexed interactionId, uint256 indexed npcId, address indexed user, uint256 amount);
    event NPCRated(uint256 indexed ratingId, uint256 indexed npcId, address indexed rater, uint8 score);
    event NPCToggled(uint256 indexed npcId, bool active);
    event InteractionFeeUpdated(uint256 indexed npcId, uint256 oldFee, uint256 newFee);
    event EarningsWithdrawn(uint256 indexed npcId, address indexed creator, uint256 amount);

    // ── Constructor ──────────────────────────────────────────
    constructor() {}

    // ── Core Functions ───────────────────────────────────────

    /**
     * @notice Register a new NPC with behavior data
     * @param name NPC name
     * @param behaviorHash IPFS hash of behavior script
     * @param personality NPC personality type
     * @param gameId Game this NPC belongs to
     * @param interactionFee Fee per interaction in wei
     * @return npcId The new NPC ID
     */
    function registerNPC(
        string calldata name,
        bytes32 behaviorHash,
        Personality personality,
        uint256 gameId,
        uint256 interactionFee
    ) external whenNotPaused returns (uint256 npcId) {
        require(bytes(name).length > 0, "NPCRegistry: empty name");
        require(behaviorHash != bytes32(0), "NPCRegistry: empty behavior hash");
        require(gameId > 0, "NPCRegistry: invalid game ID");

        npcId = ++npcCounter;
        npcs[npcId] = NPC({
            name: name,
            behaviorHash: behaviorHash,
            personality: personality,
            gameId: gameId,
            creator: msg.sender,
            interactionFee: interactionFee,
            totalInteractions: 0,
            totalRatings: 0,
            ratingSum: 0,
            totalEarnings: 0,
            active: true,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        gameNPCs[gameId].push(npcId);
        creatorNPCs[msg.sender].push(npcId);

        emit NPCRegistered(npcId, name, behaviorHash, personality, gameId, msg.sender);
    }

    /**
     * @notice Update an NPC's behavior
     * @param npcId The NPC to update
     * @param newBehaviorHash New IPFS behavior hash
     */
    function updateBehavior(uint256 npcId, bytes32 newBehaviorHash) external whenNotPaused {
        NPC storage npc = npcs[npcId];
        require(npc.creator == msg.sender, "NPCRegistry: not creator");
        require(newBehaviorHash != bytes32(0), "NPCRegistry: empty hash");
        require(npc.active, "NPCRegistry: NPC inactive");

        bytes32 oldHash = npc.behaviorHash;
        npc.behaviorHash = newBehaviorHash;
        npc.updatedAt = block.timestamp;

        emit BehaviorUpdated(npcId, oldHash, newBehaviorHash);
    }

    /**
     * @notice Interact with an NPC (pay interaction fee)
     * @param npcId The NPC to interact with
     * @return interactionId The interaction record ID
     */
    function interactWithNPC(uint256 npcId)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 interactionId)
    {
        NPC storage npc = npcs[npcId];
        require(npc.active, "NPCRegistry: NPC inactive");
        require(msg.value >= npc.interactionFee, "NPCRegistry: insufficient fee");

        interactionId = ++interactionCounter;
        interactions[interactionId] = Interaction({
            npcId: npcId,
            user: msg.sender,
            paidAmount: msg.value,
            timestamp: block.timestamp
        });

        npc.totalInteractions++;
        npc.totalEarnings += msg.value;
        hasInteracted[npcId][msg.sender] = true;

        emit NPCInteraction(interactionId, npcId, msg.sender, msg.value);
    }

    /**
     * @notice Rate an NPC you have interacted with
     * @param npcId The NPC to rate
     * @param score Rating from 1 to 5
     * @return ratingId The rating record ID
     */
    function rateNPC(uint256 npcId, uint8 score) external whenNotPaused returns (uint256 ratingId) {
        require(score >= 1 && score <= 5, "NPCRegistry: score must be 1-5");
        require(hasInteracted[npcId][msg.sender], "NPCRegistry: must interact first");
        require(!hasRated[npcId][msg.sender], "NPCRegistry: already rated");

        ratingId = ++ratingCounter;
        ratings[ratingId] = Rating({
            npcId: npcId,
            rater: msg.sender,
            score: score,
            timestamp: block.timestamp
        });

        NPC storage npc = npcs[npcId];
        npc.totalRatings++;
        npc.ratingSum += score;
        hasRated[npcId][msg.sender] = true;

        emit NPCRated(ratingId, npcId, msg.sender, score);
    }

    /**
     * @notice Withdraw earnings from an NPC
     * @param npcId The NPC to withdraw from
     */
    function withdrawEarnings(uint256 npcId) external nonReentrant {
        NPC storage npc = npcs[npcId];
        require(npc.creator == msg.sender, "NPCRegistry: not creator");

        uint256 earnings = npc.totalEarnings;
        require(earnings > 0, "NPCRegistry: no earnings");

        uint256 fee = (earnings * platformFeePercent) / 100;
        uint256 payout = earnings - fee;
        npc.totalEarnings = 0;

        (bool sent,) = msg.sender.call{value: payout}("");
        require(sent, "NPCRegistry: payout failed");

        if (fee > 0) {
            (bool feeSent,) = owner().call{value: fee}("");
            require(feeSent, "NPCRegistry: fee transfer failed");
        }

        emit EarningsWithdrawn(npcId, msg.sender, payout);
    }

    // ── NPC Management ───────────────────────────────────────

    function toggleNPC(uint256 npcId) external {
        NPC storage npc = npcs[npcId];
        require(npc.creator == msg.sender || msg.sender == owner(), "NPCRegistry: not authorized");
        npc.active = !npc.active;
        emit NPCToggled(npcId, npc.active);
    }

    function setInteractionFee(uint256 npcId, uint256 newFee) external {
        NPC storage npc = npcs[npcId];
        require(npc.creator == msg.sender, "NPCRegistry: not creator");
        emit InteractionFeeUpdated(npcId, npc.interactionFee, newFee);
        npc.interactionFee = newFee;
    }

    // ── Admin ────────────────────────────────────────────────

    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 25, "NPCRegistry: fee too high");
        platformFeePercent = _fee;
    }

    // ── View Helpers ─────────────────────────────────────────

    function getGameNPCs(uint256 gameId) external view returns (uint256[] memory) {
        return gameNPCs[gameId];
    }

    function getCreatorNPCs(address creator) external view returns (uint256[] memory) {
        return creatorNPCs[creator];
    }

    /**
     * @notice Get the average rating of an NPC (scaled by 100 for precision)
     * @param npcId The NPC ID
     * @return avgRating Average rating * 100 (e.g., 450 = 4.50)
     * @return count Number of ratings
     */
    function getAverageRating(uint256 npcId) external view returns (uint256 avgRating, uint256 count) {
        NPC storage npc = npcs[npcId];
        count = npc.totalRatings;
        if (count == 0) return (0, 0);
        avgRating = (npc.ratingSum * 100) / count;
    }
}
