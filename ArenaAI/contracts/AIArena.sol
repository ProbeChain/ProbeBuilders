// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title AIArena
 * @author ProbeChain Builders
 * @notice AI agent tournament platform with ELO rating system and wager-based matches
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
// AIArena
// ──────────────────────────────────────────────────────────────
contract AIArena is Ownable, ReentrancyGuard, Pausable {

    // ── Enums ────────────────────────────────────────────────
    enum StrategyType { Offensive, Defensive, Balanced, Adaptive, Swarm, Stealth }
    enum MatchStatus { Scheduled, InProgress, Completed, Cancelled }
    enum TournamentStatus { Open, Active, Completed }

    // ── Structs ──────────────────────────────────────────────
    struct Agent {
        string name;
        bytes32 modelHash;          // IPFS hash of AI model
        StrategyType strategyType;
        address owner_;
        uint256 elo;                // ELO rating (starts at 1200)
        uint256 wins;
        uint256 losses;
        uint256 draws;
        uint256 totalMatches;
        uint256 totalEarnings;
        bool active;
        uint256 registeredAt;
    }

    struct Tournament {
        uint256 agentCount;         // Required agent count
        uint256 wager;              // Per-agent wager
        uint256 prizePool;
        TournamentStatus status;
        address organizer;
        uint256[] agentIds;
        uint256[] matchIds;
        uint256 createdAt;
    }

    struct Match {
        uint256 tournamentId;
        uint256 agent1Id;
        uint256 agent2Id;
        uint256 winnerId;           // 0 if draw or not yet decided
        bytes32 proofHash;
        MatchStatus status;
        uint256 playedAt;
    }

    // ── Constants ────────────────────────────────────────────
    uint256 public constant INITIAL_ELO = 1200;
    uint256 public constant K_FACTOR = 32;         // ELO K-factor
    uint256 public constant ELO_SCALE = 400;       // ELO scale divisor

    // ── State ────────────────────────────────────────────────
    uint256 public agentCounter;
    uint256 public tournamentCounter;
    uint256 public matchCounter;
    uint256 public platformFeePercent = 5;
    address public matchOracle;

    mapping(uint256 => Agent) public agents;
    mapping(uint256 => Tournament) public tournaments;
    mapping(uint256 => Match) public matches;

    /// @dev owner => list of agent IDs
    mapping(address => uint256[]) public ownerAgents;
    /// @dev tournamentId => agentId => has joined
    mapping(uint256 => mapping(uint256 => bool)) public tournamentAgentJoined;
    /// @dev tournamentId => agentId => unclaimed reward
    mapping(uint256 => mapping(uint256 => uint256)) public unclaimedRewards;

    // ── Events ───────────────────────────────────────────────
    event AgentRegistered(uint256 indexed agentId, string name, bytes32 modelHash, StrategyType strategy, address indexed owner_);
    event AgentUpdated(uint256 indexed agentId, bytes32 newModelHash);
    event TournamentCreated(uint256 indexed tournamentId, uint256 agentCount, uint256 wager, address indexed organizer);
    event AgentJoinedTournament(uint256 indexed tournamentId, uint256 indexed agentId);
    event TournamentStarted(uint256 indexed tournamentId);
    event MatchScheduled(uint256 indexed matchId, uint256 indexed tournamentId, uint256 agent1Id, uint256 agent2Id);
    event MatchResult(uint256 indexed matchId, uint256 winnerId, bytes32 proofHash);
    event EloUpdated(uint256 indexed agentId, uint256 oldElo, uint256 newElo);
    event RewardClaimed(uint256 indexed tournamentId, uint256 indexed agentId, uint256 amount);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    // ── Constructor ──────────────────────────────────────────
    constructor(address _oracle) {
        require(_oracle != address(0), "AIArena: zero oracle");
        matchOracle = _oracle;
    }

    // ── Modifiers ────────────────────────────────────────────
    modifier onlyOracle() {
        require(msg.sender == matchOracle || msg.sender == owner(), "AIArena: not oracle");
        _;
    }

    // ── Receive ──────────────────────────────────────────────
    receive() external payable {}

    // ── Agent Management ─────────────────────────────────────

    /**
     * @notice Register a new AI agent
     * @param name Agent name
     * @param modelHash IPFS hash of the AI model
     * @param strategyType Agent strategy type
     * @return agentId The new agent ID
     */
    function registerAgent(string calldata name, bytes32 modelHash, StrategyType strategyType)
        external
        whenNotPaused
        returns (uint256 agentId)
    {
        require(bytes(name).length > 0, "AIArena: empty name");
        require(modelHash != bytes32(0), "AIArena: empty model hash");

        agentId = ++agentCounter;
        agents[agentId] = Agent({
            name: name,
            modelHash: modelHash,
            strategyType: strategyType,
            owner_: msg.sender,
            elo: INITIAL_ELO,
            wins: 0,
            losses: 0,
            draws: 0,
            totalMatches: 0,
            totalEarnings: 0,
            active: true,
            registeredAt: block.timestamp
        });

        ownerAgents[msg.sender].push(agentId);
        emit AgentRegistered(agentId, name, modelHash, strategyType, msg.sender);
    }

    /**
     * @notice Update an agent's model
     * @param agentId The agent to update
     * @param newModelHash New IPFS model hash
     */
    function updateAgent(uint256 agentId, bytes32 newModelHash) external whenNotPaused {
        Agent storage a = agents[agentId];
        require(a.owner_ == msg.sender, "AIArena: not agent owner");
        require(newModelHash != bytes32(0), "AIArena: empty hash");
        a.modelHash = newModelHash;
        emit AgentUpdated(agentId, newModelHash);
    }

    // ── Tournament Management ────────────────────────────────

    /**
     * @notice Create a new AI tournament
     * @param agentCount Required number of agents
     * @param wager Per-agent wager in wei
     * @return tournamentId The new tournament ID
     */
    function createTournament(uint256 agentCount, uint256 wager)
        external
        payable
        whenNotPaused
        returns (uint256 tournamentId)
    {
        require(agentCount >= 2, "AIArena: min 2 agents");
        require(agentCount <= 64, "AIArena: max 64 agents");

        tournamentId = ++tournamentCounter;
        Tournament storage t = tournaments[tournamentId];
        t.agentCount = agentCount;
        t.wager = wager;
        t.prizePool = msg.value;
        t.status = TournamentStatus.Open;
        t.organizer = msg.sender;
        t.createdAt = block.timestamp;

        emit TournamentCreated(tournamentId, agentCount, wager, msg.sender);
    }

    /**
     * @notice Join a tournament with an agent
     * @param tournamentId The tournament
     * @param agentId The agent to enter
     */
    function joinTournament(uint256 tournamentId, uint256 agentId)
        external
        payable
        whenNotPaused
    {
        Tournament storage t = tournaments[tournamentId];
        require(t.status == TournamentStatus.Open, "AIArena: not open");
        require(t.agentIds.length < t.agentCount, "AIArena: tournament full");

        Agent storage a = agents[agentId];
        require(a.owner_ == msg.sender, "AIArena: not agent owner");
        require(a.active, "AIArena: agent inactive");
        require(!tournamentAgentJoined[tournamentId][agentId], "AIArena: already joined");
        require(msg.value >= t.wager, "AIArena: insufficient wager");

        t.agentIds.push(agentId);
        t.prizePool += msg.value;
        tournamentAgentJoined[tournamentId][agentId] = true;

        emit AgentJoinedTournament(tournamentId, agentId);

        // Auto-start when full
        if (t.agentIds.length == t.agentCount) {
            t.status = TournamentStatus.Active;
            emit TournamentStarted(tournamentId);
        }
    }

    /**
     * @notice Schedule a match between two agents in a tournament
     * @param tournamentId The tournament
     * @param agent1Id First agent
     * @param agent2Id Second agent
     * @return matchId The new match ID
     */
    function matchAgents(uint256 tournamentId, uint256 agent1Id, uint256 agent2Id)
        external
        onlyOracle
        returns (uint256 matchId)
    {
        Tournament storage t = tournaments[tournamentId];
        require(t.status == TournamentStatus.Active, "AIArena: tournament not active");
        require(tournamentAgentJoined[tournamentId][agent1Id], "AIArena: agent1 not in tournament");
        require(tournamentAgentJoined[tournamentId][agent2Id], "AIArena: agent2 not in tournament");
        require(agent1Id != agent2Id, "AIArena: same agent");

        matchId = ++matchCounter;
        matches[matchId] = Match({
            tournamentId: tournamentId,
            agent1Id: agent1Id,
            agent2Id: agent2Id,
            winnerId: 0,
            proofHash: bytes32(0),
            status: MatchStatus.Scheduled,
            playedAt: 0
        });

        t.matchIds.push(matchId);
        emit MatchScheduled(matchId, tournamentId, agent1Id, agent2Id);
    }

    /**
     * @notice Submit the result of a match (oracle only)
     * @param matchId The match
     * @param winnerId The winning agent ID (0 for draw)
     * @param proofHash Proof of match execution
     */
    function submitResult(uint256 matchId, uint256 winnerId, bytes32 proofHash)
        external
        onlyOracle
    {
        Match storage m = matches[matchId];
        require(m.status == MatchStatus.Scheduled || m.status == MatchStatus.InProgress, "AIArena: invalid status");
        require(
            winnerId == 0 || winnerId == m.agent1Id || winnerId == m.agent2Id,
            "AIArena: invalid winner"
        );

        m.winnerId = winnerId;
        m.proofHash = proofHash;
        m.status = MatchStatus.Completed;
        m.playedAt = block.timestamp;

        // Update stats and ELO
        _updateElo(m.agent1Id, m.agent2Id, winnerId);

        emit MatchResult(matchId, winnerId, proofHash);
    }

    /**
     * @notice Finalize tournament and set rewards
     * @param tournamentId The tournament
     * @param topAgentIds Ordered array of top agent IDs [1st, 2nd, 3rd]
     */
    function finalizeTournament(uint256 tournamentId, uint256[] calldata topAgentIds)
        external
        onlyOracle
    {
        Tournament storage t = tournaments[tournamentId];
        require(t.status == TournamentStatus.Active, "AIArena: not active");
        require(topAgentIds.length >= 1 && topAgentIds.length <= 3, "AIArena: invalid top agents");

        t.status = TournamentStatus.Completed;

        uint256 fee = (t.prizePool * platformFeePercent) / 100;
        uint256 distributable = t.prizePool - fee;

        if (topAgentIds.length == 1) {
            unclaimedRewards[tournamentId][topAgentIds[0]] = distributable;
        } else if (topAgentIds.length == 2) {
            unclaimedRewards[tournamentId][topAgentIds[0]] = (distributable * 65) / 100;
            unclaimedRewards[tournamentId][topAgentIds[1]] = distributable - (distributable * 65) / 100;
        } else {
            unclaimedRewards[tournamentId][topAgentIds[0]] = (distributable * 50) / 100;
            unclaimedRewards[tournamentId][topAgentIds[1]] = (distributable * 30) / 100;
            unclaimedRewards[tournamentId][topAgentIds[2]] = distributable - (distributable * 50) / 100 - (distributable * 30) / 100;
        }

        if (fee > 0) {
            (bool feeSent,) = owner().call{value: fee}("");
            require(feeSent, "AIArena: fee transfer failed");
        }
    }

    /**
     * @notice Claim tournament reward for an agent
     * @param tournamentId The tournament
     * @param agentId The agent to claim for
     */
    function claimReward(uint256 tournamentId, uint256 agentId) external nonReentrant {
        Agent storage a = agents[agentId];
        require(a.owner_ == msg.sender, "AIArena: not agent owner");

        uint256 reward = unclaimedRewards[tournamentId][agentId];
        require(reward > 0, "AIArena: no reward");

        unclaimedRewards[tournamentId][agentId] = 0;
        a.totalEarnings += reward;

        (bool sent,) = msg.sender.call{value: reward}("");
        require(sent, "AIArena: transfer failed");

        emit RewardClaimed(tournamentId, agentId, reward);
    }

    // ── ELO Calculation ──────────────────────────────────────

    /**
     * @dev Update ELO ratings after a match
     * @param agent1Id First agent
     * @param agent2Id Second agent
     * @param winnerId Winner (0 = draw)
     */
    function _updateElo(uint256 agent1Id, uint256 agent2Id, uint256 winnerId) internal {
        Agent storage a1 = agents[agent1Id];
        Agent storage a2 = agents[agent2Id];

        a1.totalMatches++;
        a2.totalMatches++;

        uint256 oldElo1 = a1.elo;
        uint256 oldElo2 = a2.elo;

        // Simplified ELO: expected score approx using linear difference
        // Full ELO uses 10^(diff/400) but we simplify for gas efficiency
        if (winnerId == agent1Id) {
            a1.wins++;
            a2.losses++;
            // Winner gains, loser loses
            uint256 eloDiff = _min(oldElo2 > oldElo1 ? (oldElo2 - oldElo1) / 10 : 0, K_FACTOR);
            uint256 gain = K_FACTOR / 2 + eloDiff;
            uint256 loss = K_FACTOR / 2 + eloDiff;
            a1.elo = oldElo1 + gain;
            a2.elo = oldElo2 > loss ? oldElo2 - loss : 1;
        } else if (winnerId == agent2Id) {
            a2.wins++;
            a1.losses++;
            uint256 eloDiff = _min(oldElo1 > oldElo2 ? (oldElo1 - oldElo2) / 10 : 0, K_FACTOR);
            uint256 gain = K_FACTOR / 2 + eloDiff;
            uint256 loss = K_FACTOR / 2 + eloDiff;
            a2.elo = oldElo2 + gain;
            a1.elo = oldElo1 > loss ? oldElo1 - loss : 1;
        } else {
            // Draw
            a1.draws++;
            a2.draws++;
            if (oldElo1 > oldElo2) {
                uint256 adj = _min((oldElo1 - oldElo2) / 20, K_FACTOR / 4);
                a1.elo = oldElo1 > adj ? oldElo1 - adj : oldElo1;
                a2.elo = oldElo2 + adj;
            } else if (oldElo2 > oldElo1) {
                uint256 adj = _min((oldElo2 - oldElo1) / 20, K_FACTOR / 4);
                a2.elo = oldElo2 > adj ? oldElo2 - adj : oldElo2;
                a1.elo = oldElo1 + adj;
            }
        }

        emit EloUpdated(agent1Id, oldElo1, a1.elo);
        emit EloUpdated(agent2Id, oldElo2, a2.elo);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // ── Admin ────────────────────────────────────────────────

    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "AIArena: zero oracle");
        emit OracleUpdated(matchOracle, _oracle);
        matchOracle = _oracle;
    }

    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 20, "AIArena: fee too high");
        platformFeePercent = _fee;
    }

    // ── View Helpers ─────────────────────────────────────────

    function getOwnerAgents(address _owner) external view returns (uint256[] memory) {
        return ownerAgents[_owner];
    }

    function getTournamentAgents(uint256 tournamentId) external view returns (uint256[] memory) {
        return tournaments[tournamentId].agentIds;
    }

    function getTournamentMatches(uint256 tournamentId) external view returns (uint256[] memory) {
        return tournaments[tournamentId].matchIds;
    }
}
