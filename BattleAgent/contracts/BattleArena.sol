// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title BattleArena
 * @notice AI Agent PvP arena with ELO rating, wager escrow, and match history
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */
contract BattleArena {
    // ──────────────────── Ownership ────────────────────
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
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
    modifier whenNotPaused() {
        require(!paused, "Paused");
        _;
    }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ──────────────────── Data Structures ────────────────────
    struct Fighter {
        uint256 agentId;
        address owner;
        uint16 attack;
        uint16 defense;
        uint16 speed;
        uint256 eloRating;
        uint256 wins;
        uint256 losses;
        bool registered;
    }

    enum MatchStatus { Pending, Active, Resolved, Cancelled }

    struct Match {
        uint256 matchId;
        uint256 challengerId;
        uint256 defenderId;
        uint256 wager;
        address challengerOwner;
        address defenderOwner;
        MatchStatus status;
        uint256 winnerId;
        uint256 createdAt;
        uint256 resolvedAt;
    }

    // ──────────────────── State ────────────────────
    uint256 public nextFighterId = 1;
    uint256 public nextMatchId = 1;
    uint256 public constant BASE_ELO = 1200;
    uint256 public constant K_FACTOR = 32;
    uint256 public platformFeeBPS = 250; // 2.5%

    mapping(uint256 => Fighter) public fighters;
    mapping(address => uint256[]) public ownerFighters;
    mapping(uint256 => Match) public matches;
    mapping(address => uint256) public pendingWithdrawals;

    // ──────────────────── Events ────────────────────
    event FighterRegistered(uint256 indexed fighterId, uint256 agentId, address indexed owner);
    event MatchCreated(uint256 indexed matchId, uint256 challengerId, uint256 defenderId, uint256 wager);
    event MatchResolved(uint256 indexed matchId, uint256 winnerId, uint256 newWinnerElo, uint256 newLoserElo);
    event MatchCancelled(uint256 indexed matchId);
    event RewardsClaimed(address indexed player, uint256 amount);
    event FeeUpdated(uint256 newFeeBPS);

    // ──────────────────── Constructor ────────────────────
    constructor() {
        owner = msg.sender;
    }

    // ──────────────────── Fighter Management ────────────────────

    /**
     * @notice Register a new AI fighter agent
     * @param agentId External AI agent identifier
     * @param attack Attack stat (1-100)
     * @param defense Defense stat (1-100)
     * @param speed Speed stat (1-100)
     */
    function registerFighter(
        uint256 agentId,
        uint16 attack,
        uint16 defense,
        uint16 speed
    ) external whenNotPaused returns (uint256) {
        require(attack >= 1 && attack <= 100, "Invalid attack");
        require(defense >= 1 && defense <= 100, "Invalid defense");
        require(speed >= 1 && speed <= 100, "Invalid speed");
        require(attack + defense + speed <= 200, "Stats too high");

        uint256 fighterId = nextFighterId++;
        fighters[fighterId] = Fighter({
            agentId: agentId,
            owner: msg.sender,
            attack: attack,
            defense: defense,
            speed: speed,
            eloRating: BASE_ELO,
            wins: 0,
            losses: 0,
            registered: true
        });
        ownerFighters[msg.sender].push(fighterId);

        emit FighterRegistered(fighterId, agentId, msg.sender);
        return fighterId;
    }

    /**
     * @notice Get all fighter IDs owned by an address
     */
    function getOwnedFighters(address _owner) external view returns (uint256[] memory) {
        return ownerFighters[_owner];
    }

    // ──────────────────── Match Management ────────────────────

    /**
     * @notice Create a match challenging another fighter with a wager
     * @param challengerId Your fighter ID
     * @param defenderId Opponent fighter ID
     */
    function createMatch(uint256 challengerId, uint256 defenderId) external payable whenNotPaused returns (uint256) {
        require(msg.value > 0, "Wager required");
        Fighter storage c = fighters[challengerId];
        Fighter storage d = fighters[defenderId];
        require(c.registered && d.registered, "Fighter not found");
        require(c.owner == msg.sender, "Not your fighter");
        require(c.owner != d.owner, "Cannot self-battle");

        uint256 matchId = nextMatchId++;
        matches[matchId] = Match({
            matchId: matchId,
            challengerId: challengerId,
            defenderId: defenderId,
            wager: msg.value,
            challengerOwner: msg.sender,
            defenderOwner: d.owner,
            status: MatchStatus.Pending,
            winnerId: 0,
            createdAt: block.timestamp,
            resolvedAt: 0
        });

        emit MatchCreated(matchId, challengerId, defenderId, msg.value);
        return matchId;
    }

    /**
     * @notice Defender accepts match by sending matching wager
     * @param matchId The match to join
     */
    function acceptMatch(uint256 matchId) external payable whenNotPaused {
        Match storage m = matches[matchId];
        require(m.status == MatchStatus.Pending, "Not pending");
        require(m.defenderOwner == msg.sender, "Not defender");
        require(msg.value == m.wager, "Wager mismatch");

        m.status = MatchStatus.Active;
        m.wager += msg.value; // total pot
    }

    /**
     * @notice Resolve a match (owner/oracle only)
     * @param matchId Match to resolve
     * @param winnerId The winning fighter ID
     */
    function resolveMatch(uint256 matchId, uint256 winnerId) external onlyOwner nonReentrant {
        Match storage m = matches[matchId];
        require(m.status == MatchStatus.Active, "Not active");
        require(winnerId == m.challengerId || winnerId == m.defenderId, "Invalid winner");

        m.status = MatchStatus.Resolved;
        m.winnerId = winnerId;
        m.resolvedAt = block.timestamp;

        uint256 loserId = winnerId == m.challengerId ? m.defenderId : m.challengerId;
        Fighter storage winner = fighters[winnerId];
        Fighter storage loser = fighters[loserId];

        // ELO calculation
        (uint256 newWinnerElo, uint256 newLoserElo) = _calculateElo(
            winner.eloRating, loser.eloRating
        );
        winner.eloRating = newWinnerElo;
        loser.eloRating = newLoserElo;
        winner.wins++;
        loser.losses++;

        // Distribute wager
        uint256 fee = (m.wager * platformFeeBPS) / 10000;
        uint256 reward = m.wager - fee;
        address winnerOwner = winnerId == m.challengerId ? m.challengerOwner : m.defenderOwner;
        pendingWithdrawals[winnerOwner] += reward;
        pendingWithdrawals[owner] += fee;

        emit MatchResolved(matchId, winnerId, newWinnerElo, newLoserElo);
    }

    /**
     * @notice Cancel a pending match (challenger only)
     */
    function cancelMatch(uint256 matchId) external nonReentrant {
        Match storage m = matches[matchId];
        require(m.status == MatchStatus.Pending, "Not pending");
        require(m.challengerOwner == msg.sender, "Not challenger");

        m.status = MatchStatus.Cancelled;
        pendingWithdrawals[msg.sender] += m.wager;

        emit MatchCancelled(matchId);
    }

    /**
     * @notice Claim accumulated rewards
     */
    function claimRewards() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to claim");
        pendingWithdrawals[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        emit RewardsClaimed(msg.sender, amount);
    }

    // ──────────────────── ELO Calculation ────────────────────

    /**
     * @dev Simplified ELO rating update
     */
    function _calculateElo(uint256 winnerElo, uint256 loserElo)
        internal
        pure
        returns (uint256 newWinner, uint256 newLoser)
    {
        uint256 diff;
        uint256 expected;

        if (winnerElo >= loserElo) {
            diff = winnerElo - loserElo;
        } else {
            diff = loserElo - winnerElo;
        }

        // Simplified expected score: cap diff at 400
        if (diff > 400) diff = 400;

        // Winner expected ~= 1 / (1 + 10^(diff/400))
        // Simplified: if winner had higher ELO, gain less; otherwise gain more
        if (winnerElo >= loserElo) {
            expected = 50 + (diff * 50) / 400; // 50-100 range (percentage)
        } else {
            expected = 50 - (diff * 50) / 400; // 0-50 range
        }

        uint256 gain = (K_FACTOR * (100 - expected)) / 100;
        if (gain == 0) gain = 1;

        newWinner = winnerElo + gain;
        newLoser = loserElo > gain ? loserElo - gain : 1;
    }

    // ──────────────────── Admin ────────────────────

    function setFee(uint256 newFeeBPS) external onlyOwner {
        require(newFeeBPS <= 1000, "Fee too high");
        platformFeeBPS = newFeeBPS;
        emit FeeUpdated(newFeeBPS);
    }

    /**
     * @notice Get match details
     */
    function getMatch(uint256 matchId) external view returns (Match memory) {
        return matches[matchId];
    }

    /**
     * @notice Get fighter details
     */
    function getFighter(uint256 fighterId) external view returns (Fighter memory) {
        return fighters[fighterId];
    }

    receive() external payable {}
}
