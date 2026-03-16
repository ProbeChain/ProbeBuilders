// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title LootDistributor
 * @author ProbeChain Builders
 * @notice Contribution-weighted loot distribution for raid groups
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
// LootDistributor
// ──────────────────────────────────────────────────────────────
contract LootDistributor is Ownable, ReentrancyGuard, Pausable {

    // ── Structs ──────────────────────────────────────────────
    struct Contribution {
        uint256 dps;
        uint256 healing;
        uint256 tanking;
    }

    struct Raid {
        uint256 bossId;
        address raidLeader;
        address[] participants;
        uint256 totalContribution;
        uint256 lootPool;         // ETH pool for this raid
        uint256[] itemIds;
        bool lootDistributed;
        bool finalized;
        uint256 createdAt;
    }

    struct LootShare {
        uint256 ethShare;
        uint256[] itemIndices;    // indices into Raid.itemIds
        bool claimed;
    }

    // ── State ────────────────────────────────────────────────
    uint256 public raidCounter;
    uint256 public dpsWeight = 40;
    uint256 public healingWeight = 30;
    uint256 public tankingWeight = 30;

    mapping(uint256 => Raid) public raids;
    mapping(uint256 => mapping(address => bool)) public isParticipant;
    mapping(uint256 => mapping(address => Contribution)) public contributions;
    mapping(uint256 => mapping(address => uint256)) public contributionScores;
    mapping(uint256 => mapping(address => LootShare)) public lootShares;

    // ── Events ───────────────────────────────────────────────
    event RaidCreated(uint256 indexed raidId, uint256 bossId, address indexed leader, uint256 participantCount);
    event ContributionRecorded(uint256 indexed raidId, address indexed participant, uint256 dps, uint256 healing, uint256 tanking);
    event LootDistributed(uint256 indexed raidId, uint256 lootPool, uint256 itemCount);
    event LootClaimed(uint256 indexed raidId, address indexed participant, uint256 ethAmount);
    event WeightsUpdated(uint256 dps, uint256 healing, uint256 tanking);
    event RaidFunded(uint256 indexed raidId, address indexed funder, uint256 amount);

    // ── Constructor ──────────────────────────────────────────
    constructor() {}

    // ── Core Functions ───────────────────────────────────────

    /**
     * @notice Create a new raid with participants
     * @param participants Array of participant addresses
     * @param bossId The boss identifier
     * @return raidId The new raid ID
     */
    function createRaid(address[] calldata participants, uint256 bossId)
        external
        whenNotPaused
        returns (uint256 raidId)
    {
        require(participants.length >= 2, "LootDistributor: need at least 2");
        require(participants.length <= 40, "LootDistributor: max 40 participants");

        raidId = ++raidCounter;
        Raid storage r = raids[raidId];
        r.bossId = bossId;
        r.raidLeader = msg.sender;
        r.createdAt = block.timestamp;

        for (uint256 i = 0; i < participants.length; i++) {
            require(participants[i] != address(0), "LootDistributor: zero address");
            require(!isParticipant[raidId][participants[i]], "LootDistributor: duplicate");
            r.participants.push(participants[i]);
            isParticipant[raidId][participants[i]] = true;
        }

        emit RaidCreated(raidId, bossId, msg.sender, participants.length);
    }

    /**
     * @notice Fund a raid's loot pool
     * @param raidId The raid to fund
     */
    function fundRaid(uint256 raidId) external payable whenNotPaused {
        Raid storage r = raids[raidId];
        require(r.raidLeader != address(0), "LootDistributor: raid does not exist");
        require(!r.lootDistributed, "LootDistributor: already distributed");
        r.lootPool += msg.value;
        emit RaidFunded(raidId, msg.sender, msg.value);
    }

    /**
     * @notice Record a participant's contribution to a raid
     * @param raidId The raid
     * @param participant The contributor
     * @param dps DPS contribution score
     * @param healing Healing contribution score
     * @param tanking Tanking contribution score
     */
    function recordContribution(
        uint256 raidId,
        address participant,
        uint256 dps,
        uint256 healing,
        uint256 tanking
    ) external whenNotPaused {
        Raid storage r = raids[raidId];
        require(msg.sender == r.raidLeader || msg.sender == owner(), "LootDistributor: not authorized");
        require(isParticipant[raidId][participant], "LootDistributor: not participant");
        require(!r.lootDistributed, "LootDistributor: already distributed");

        // Overwrite previous contribution
        Contribution storage old = contributions[raidId][participant];
        uint256 oldScore = contributionScores[raidId][participant];
        r.totalContribution -= oldScore;

        old.dps = dps;
        old.healing = healing;
        old.tanking = tanking;

        uint256 score = (dps * dpsWeight + healing * healingWeight + tanking * tankingWeight) / 100;
        contributionScores[raidId][participant] = score;
        r.totalContribution += score;

        emit ContributionRecorded(raidId, participant, dps, healing, tanking);
    }

    /**
     * @notice Distribute loot among participants based on contributions
     * @param raidId The raid
     * @param itemIds Array of item identifiers dropped
     */
    function distributeLoot(uint256 raidId, uint256[] calldata itemIds)
        external
        whenNotPaused
    {
        Raid storage r = raids[raidId];
        require(msg.sender == r.raidLeader || msg.sender == owner(), "LootDistributor: not authorized");
        require(!r.lootDistributed, "LootDistributor: already distributed");
        require(r.totalContribution > 0, "LootDistributor: no contributions");

        r.itemIds = itemIds;
        r.lootDistributed = true;

        // Calculate each participant's ETH share
        for (uint256 i = 0; i < r.participants.length; i++) {
            address p = r.participants[i];
            uint256 score = contributionScores[raidId][p];
            if (score > 0) {
                uint256 ethShare = (r.lootPool * score) / r.totalContribution;
                lootShares[raidId][p].ethShare = ethShare;
            }
        }

        // Distribute items round-robin by contribution rank (simplified)
        if (itemIds.length > 0) {
            uint256 itemIdx = 0;
            for (uint256 i = 0; i < r.participants.length && itemIdx < itemIds.length; i++) {
                address p = r.participants[i];
                if (contributionScores[raidId][p] > 0) {
                    lootShares[raidId][p].itemIndices.push(itemIdx);
                    itemIdx++;
                }
            }
        }

        emit LootDistributed(raidId, r.lootPool, itemIds.length);
    }

    /**
     * @notice Claim your loot share from a raid
     * @param raidId The raid to claim from
     */
    function claimShare(uint256 raidId) external nonReentrant {
        Raid storage r = raids[raidId];
        require(r.lootDistributed, "LootDistributor: not distributed");
        require(isParticipant[raidId][msg.sender], "LootDistributor: not participant");

        LootShare storage share = lootShares[raidId][msg.sender];
        require(!share.claimed, "LootDistributor: already claimed");
        require(share.ethShare > 0, "LootDistributor: no share");

        share.claimed = true;
        uint256 amount = share.ethShare;

        (bool sent,) = msg.sender.call{value: amount}("");
        require(sent, "LootDistributor: transfer failed");

        emit LootClaimed(raidId, msg.sender, amount);
    }

    // ── Admin ────────────────────────────────────────────────

    /**
     * @notice Update contribution weights (must sum to 100)
     */
    function setWeights(uint256 _dps, uint256 _healing, uint256 _tanking) external onlyOwner {
        require(_dps + _healing + _tanking == 100, "LootDistributor: weights must sum to 100");
        dpsWeight = _dps;
        healingWeight = _healing;
        tankingWeight = _tanking;
        emit WeightsUpdated(_dps, _healing, _tanking);
    }

    // ── View Helpers ─────────────────────────────────────────

    function getParticipants(uint256 raidId) external view returns (address[] memory) {
        return raids[raidId].participants;
    }

    function getItemIds(uint256 raidId) external view returns (uint256[] memory) {
        return raids[raidId].itemIds;
    }

    function getLootShareItems(uint256 raidId, address participant) external view returns (uint256[] memory) {
        return lootShares[raidId][participant].itemIndices;
    }
}
