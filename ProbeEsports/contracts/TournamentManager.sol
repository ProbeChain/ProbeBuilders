// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title TournamentManager
 * @author ProbeChain Builders
 * @notice Esports tournament with single/double elimination, team registration, and prize distribution
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
// TournamentManager
// ──────────────────────────────────────────────────────────────
contract TournamentManager is Ownable, ReentrancyGuard, Pausable {

    enum Format { SingleElimination, DoubleElimination }
    enum TournamentStatus { Registration, InProgress, Completed, Cancelled }

    struct Tournament {
        string name;
        uint256 prizePool;
        uint256 entryFee;
        uint256 maxTeams;
        Format format;
        TournamentStatus status;
        address organizer;
        uint256[] teamIds;
        uint256 currentRound;
        uint256 createdAt;
    }

    struct Team {
        string teamName;
        address captain;
        address[] members;
        uint256 tournamentId;
        bool eliminated;
        uint256 wins;
        uint256 losses;
    }

    struct Match {
        uint256 tournamentId;
        uint256 round;
        uint256 team1Id;
        uint256 team2Id;
        uint256 winnerId;
        bool played;
        uint256 playedAt;
    }

    // ── State ────────────────────────────────────────────────
    uint256 public tournamentCounter;
    uint256 public teamCounter;
    uint256 public matchCounter;
    uint256 public platformFeePercent = 5;

    mapping(uint256 => Tournament) public tournaments;
    mapping(uint256 => Team) public teams;
    mapping(uint256 => Match) public matches;
    mapping(uint256 => mapping(address => uint256)) public playerTeam; // tournamentId => player => teamId
    mapping(uint256 => address[]) public prizeRecipients; // tournamentId => winners

    // ── Prize splits: 1st = 60%, 2nd = 25%, 3rd = 15%
    uint256 public constant FIRST_PLACE = 60;
    uint256 public constant SECOND_PLACE = 25;
    uint256 public constant THIRD_PLACE = 15;

    // ── Events ───────────────────────────────────────────────
    event TournamentCreated(uint256 indexed tournamentId, string name, uint256 prizePool, uint256 maxTeams, Format format);
    event TeamRegistered(uint256 indexed tournamentId, uint256 indexed teamId, string teamName, address captain);
    event TournamentStarted(uint256 indexed tournamentId);
    event MatchCreated(uint256 indexed matchId, uint256 indexed tournamentId, uint256 round, uint256 team1Id, uint256 team2Id);
    event MatchReported(uint256 indexed matchId, uint256 indexed winnerId);
    event RoundAdvanced(uint256 indexed tournamentId, uint256 newRound);
    event PrizesDistributed(uint256 indexed tournamentId, address first, address second, address third);
    event TournamentCancelled(uint256 indexed tournamentId);

    // ── Constructor ──────────────────────────────────────────
    constructor() {}

    // ── Receive ──────────────────────────────────────────────
    receive() external payable {}

    // ── Core Functions ───────────────────────────────────────

    /**
     * @notice Create a new tournament
     * @param _name Tournament name
     * @param _maxTeams Maximum teams allowed
     * @param _format Single or double elimination
     * @return tournamentId The new tournament ID
     */
    function createTournament(
        string calldata _name,
        uint256 _maxTeams,
        Format _format
    ) external payable whenNotPaused returns (uint256 tournamentId) {
        require(_maxTeams >= 4, "TournamentManager: min 4 teams");
        require(_maxTeams <= 64, "TournamentManager: max 64 teams");

        tournamentId = ++tournamentCounter;
        Tournament storage t = tournaments[tournamentId];
        t.name = _name;
        t.prizePool = msg.value;
        t.maxTeams = _maxTeams;
        t.format = _format;
        t.status = TournamentStatus.Registration;
        t.organizer = msg.sender;
        t.createdAt = block.timestamp;

        emit TournamentCreated(tournamentId, _name, msg.value, _maxTeams, _format);
    }

    /**
     * @notice Set entry fee for a tournament (organizer only)
     * @param tournamentId The tournament
     * @param _entryFee Entry fee in wei
     */
    function setEntryFee(uint256 tournamentId, uint256 _entryFee) external {
        Tournament storage t = tournaments[tournamentId];
        require(msg.sender == t.organizer || msg.sender == owner(), "TournamentManager: not authorized");
        require(t.status == TournamentStatus.Registration, "TournamentManager: not in registration");
        t.entryFee = _entryFee;
    }

    /**
     * @notice Register a team for a tournament
     * @param tournamentId The tournament to register for
     * @param teamName Name of the team
     * @param members Array of team member addresses
     * @return teamId The new team ID
     */
    function registerTeam(
        uint256 tournamentId,
        string calldata teamName,
        address[] calldata members
    ) external payable whenNotPaused returns (uint256 teamId) {
        Tournament storage t = tournaments[tournamentId];
        require(t.status == TournamentStatus.Registration, "TournamentManager: not in registration");
        require(t.teamIds.length < t.maxTeams, "TournamentManager: tournament full");
        require(members.length >= 1 && members.length <= 10, "TournamentManager: invalid team size");
        require(msg.value >= t.entryFee, "TournamentManager: insufficient entry fee");

        // Check no member is already in another team for this tournament
        for (uint256 i = 0; i < members.length; i++) {
            require(playerTeam[tournamentId][members[i]] == 0, "TournamentManager: member already registered");
        }
        require(playerTeam[tournamentId][msg.sender] == 0, "TournamentManager: captain already registered");

        teamId = ++teamCounter;
        Team storage team = teams[teamId];
        team.teamName = teamName;
        team.captain = msg.sender;
        team.tournamentId = tournamentId;

        for (uint256 i = 0; i < members.length; i++) {
            team.members.push(members[i]);
            playerTeam[tournamentId][members[i]] = teamId;
        }
        playerTeam[tournamentId][msg.sender] = teamId;

        t.teamIds.push(teamId);
        t.prizePool += msg.value;

        emit TeamRegistered(tournamentId, teamId, teamName, msg.sender);
    }

    /**
     * @notice Start a tournament (closes registration)
     * @param tournamentId The tournament to start
     */
    function startTournament(uint256 tournamentId) external {
        Tournament storage t = tournaments[tournamentId];
        require(msg.sender == t.organizer || msg.sender == owner(), "TournamentManager: not authorized");
        require(t.status == TournamentStatus.Registration, "TournamentManager: not in registration");
        require(t.teamIds.length >= 4, "TournamentManager: need at least 4 teams");

        t.status = TournamentStatus.InProgress;
        t.currentRound = 1;
        emit TournamentStarted(tournamentId);
    }

    /**
     * @notice Create a match between two teams
     * @param tournamentId The tournament
     * @param team1Id First team
     * @param team2Id Second team
     * @return matchId The new match ID
     */
    function createMatch(uint256 tournamentId, uint256 team1Id, uint256 team2Id)
        external
        returns (uint256 matchId)
    {
        Tournament storage t = tournaments[tournamentId];
        require(msg.sender == t.organizer || msg.sender == owner(), "TournamentManager: not authorized");
        require(t.status == TournamentStatus.InProgress, "TournamentManager: not in progress");

        matchId = ++matchCounter;
        matches[matchId] = Match({
            tournamentId: tournamentId,
            round: t.currentRound,
            team1Id: team1Id,
            team2Id: team2Id,
            winnerId: 0,
            played: false,
            playedAt: 0
        });

        emit MatchCreated(matchId, tournamentId, t.currentRound, team1Id, team2Id);
    }

    /**
     * @notice Report the result of a match
     * @param matchId The match
     * @param winnerId The winning team ID
     */
    function reportMatch(uint256 matchId, uint256 winnerId) external {
        Match storage m = matches[matchId];
        Tournament storage t = tournaments[m.tournamentId];
        require(msg.sender == t.organizer || msg.sender == owner(), "TournamentManager: not authorized");
        require(!m.played, "TournamentManager: already played");
        require(winnerId == m.team1Id || winnerId == m.team2Id, "TournamentManager: invalid winner");

        m.winnerId = winnerId;
        m.played = true;
        m.playedAt = block.timestamp;

        uint256 loserId = winnerId == m.team1Id ? m.team2Id : m.team1Id;
        teams[winnerId].wins++;
        teams[loserId].losses++;

        // In single elimination, loser is eliminated
        if (t.format == Format.SingleElimination) {
            teams[loserId].eliminated = true;
        } else {
            // Double elimination: eliminated after 2 losses
            if (teams[loserId].losses >= 2) {
                teams[loserId].eliminated = true;
            }
        }

        emit MatchReported(matchId, winnerId);
    }

    /**
     * @notice Advance tournament to next round
     * @param tournamentId The tournament
     */
    function advanceRound(uint256 tournamentId) external {
        Tournament storage t = tournaments[tournamentId];
        require(msg.sender == t.organizer || msg.sender == owner(), "TournamentManager: not authorized");
        require(t.status == TournamentStatus.InProgress, "TournamentManager: not in progress");

        t.currentRound++;
        emit RoundAdvanced(tournamentId, t.currentRound);
    }

    /**
     * @notice Distribute prizes to top 3 teams
     * @param tournamentId The tournament
     * @param first 1st place team captain
     * @param second 2nd place team captain
     * @param third 3rd place team captain
     */
    function distributePrizes(uint256 tournamentId, address first, address second, address third)
        external
        nonReentrant
    {
        Tournament storage t = tournaments[tournamentId];
        require(msg.sender == t.organizer || msg.sender == owner(), "TournamentManager: not authorized");
        require(t.status == TournamentStatus.InProgress, "TournamentManager: not in progress");
        require(t.prizePool > 0, "TournamentManager: no prize pool");

        t.status = TournamentStatus.Completed;

        uint256 fee = (t.prizePool * platformFeePercent) / 100;
        uint256 distributable = t.prizePool - fee;

        uint256 firstPrize = (distributable * FIRST_PLACE) / 100;
        uint256 secondPrize = (distributable * SECOND_PLACE) / 100;
        uint256 thirdPrize = distributable - firstPrize - secondPrize;

        prizeRecipients[tournamentId].push(first);
        prizeRecipients[tournamentId].push(second);
        prizeRecipients[tournamentId].push(third);

        (bool s1,) = first.call{value: firstPrize}("");
        require(s1, "TournamentManager: 1st prize transfer failed");

        (bool s2,) = second.call{value: secondPrize}("");
        require(s2, "TournamentManager: 2nd prize transfer failed");

        (bool s3,) = third.call{value: thirdPrize}("");
        require(s3, "TournamentManager: 3rd prize transfer failed");

        if (fee > 0) {
            (bool sf,) = owner().call{value: fee}("");
            require(sf, "TournamentManager: fee transfer failed");
        }

        emit PrizesDistributed(tournamentId, first, second, third);
    }

    /**
     * @notice Cancel a tournament and refund entry fees
     * @param tournamentId The tournament to cancel
     */
    function cancelTournament(uint256 tournamentId) external nonReentrant {
        Tournament storage t = tournaments[tournamentId];
        require(msg.sender == t.organizer || msg.sender == owner(), "TournamentManager: not authorized");
        require(t.status == TournamentStatus.Registration, "TournamentManager: can only cancel during registration");

        t.status = TournamentStatus.Cancelled;

        // Refund entry fees to captains
        if (t.entryFee > 0) {
            for (uint256 i = 0; i < t.teamIds.length; i++) {
                address captain = teams[t.teamIds[i]].captain;
                (bool sent,) = captain.call{value: t.entryFee}("");
                require(sent, "TournamentManager: refund failed");
            }
        }

        emit TournamentCancelled(tournamentId);
    }

    // ── Admin ────────────────────────────────────────────────

    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 20, "TournamentManager: fee too high");
        platformFeePercent = _fee;
    }

    // ── View Helpers ─────────────────────────────────────────

    function getTeamIds(uint256 tournamentId) external view returns (uint256[] memory) {
        return tournaments[tournamentId].teamIds;
    }

    function getTeamMembers(uint256 teamId) external view returns (address[] memory) {
        return teams[teamId].members;
    }

    function getPrizeRecipients(uint256 tournamentId) external view returns (address[] memory) {
        return prizeRecipients[tournamentId];
    }
}
