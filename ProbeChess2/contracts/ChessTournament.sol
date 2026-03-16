// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title ChessTournament
 * @author ProbeChain Builders
 * @notice Advanced chess tournament with Swiss-system pairing and prize distribution
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
// ChessTournament
// ──────────────────────────────────────────────────────────────
contract ChessTournament is Ownable, ReentrancyGuard, Pausable {

    enum MatchResult { Pending, WhiteWins, BlackWins, Draw }
    enum TournamentState { Registration, Active, Completed, Cancelled }

    struct Tournament {
        uint256 entryFee;
        uint256 maxPlayers;
        uint256 totalRounds;
        uint256 currentRound;
        uint256 prizePool;
        TournamentState state;
        address organizer;
        address[] players;
        uint256 createdAt;
    }

    struct PlayerStats {
        uint256 tournamentId;
        address player;
        uint256 score;          // Stored as score * 2 (so draw = 1, win = 2, loss = 0)
        uint256 wins;
        uint256 draws;
        uint256 losses;
        uint256 buchholz;       // Tiebreak: sum of opponents' scores
    }

    struct Match {
        uint256 tournamentId;
        uint256 round;
        address white;
        address black;
        MatchResult result;
        uint256 playedAt;
    }

    // ── State ────────────────────────────────────────────────
    uint256 public tournamentCounter;
    uint256 public matchCounter;
    uint256 public platformFeePercent = 5;

    mapping(uint256 => Tournament) public tournaments;
    mapping(uint256 => Match) public matches;
    mapping(uint256 => mapping(address => PlayerStats)) public playerStats;
    mapping(uint256 => mapping(address => bool)) public registered;

    /// @dev tournamentId => round => matchIds
    mapping(uint256 => mapping(uint256 => uint256[])) public roundMatches;
    /// @dev tournamentId => player => opponent addresses they've played
    mapping(uint256 => mapping(address => mapping(address => bool))) public hasPlayed;

    // ── Prize distribution: 50%, 30%, 20%
    uint256 public constant FIRST_SHARE = 50;
    uint256 public constant SECOND_SHARE = 30;
    uint256 public constant THIRD_SHARE = 20;

    // ── Events ───────────────────────────────────────────────
    event TournamentCreated(uint256 indexed tournamentId, uint256 entryFee, uint256 maxPlayers, uint256 rounds);
    event PlayerRegistered(uint256 indexed tournamentId, address indexed player);
    event TournamentStarted(uint256 indexed tournamentId);
    event MatchCreated(uint256 indexed matchId, uint256 indexed tournamentId, uint256 round, address white, address black);
    event MatchResultReported(uint256 indexed matchId, MatchResult result);
    event RoundAdvanced(uint256 indexed tournamentId, uint256 newRound);
    event PrizeClaimed(uint256 indexed tournamentId, address indexed player, uint256 amount, uint256 place);
    event TournamentCompleted(uint256 indexed tournamentId);

    // ── Constructor ──────────────────────────────────────────
    constructor() {}

    // ── Receive ──────────────────────────────────────────────
    receive() external payable {}

    // ── Core Functions ───────────────────────────────────────

    /**
     * @notice Create a new chess tournament with Swiss-system pairing
     * @param entryFee Entry fee in wei
     * @param maxPlayers Maximum number of players
     * @param rounds Number of Swiss rounds
     * @return tournamentId The new tournament ID
     */
    function createTournament(uint256 entryFee, uint256 maxPlayers, uint256 rounds)
        external
        payable
        whenNotPaused
        returns (uint256 tournamentId)
    {
        require(maxPlayers >= 4, "ChessTournament: min 4 players");
        require(maxPlayers <= 128, "ChessTournament: max 128 players");
        require(rounds >= 3, "ChessTournament: min 3 rounds");
        require(rounds <= 15, "ChessTournament: max 15 rounds");

        tournamentId = ++tournamentCounter;
        Tournament storage t = tournaments[tournamentId];
        t.entryFee = entryFee;
        t.maxPlayers = maxPlayers;
        t.totalRounds = rounds;
        t.prizePool = msg.value;
        t.state = TournamentState.Registration;
        t.organizer = msg.sender;
        t.createdAt = block.timestamp;

        emit TournamentCreated(tournamentId, entryFee, maxPlayers, rounds);
    }

    /**
     * @notice Register for a tournament
     * @param tournamentId The tournament to register for
     */
    function register(uint256 tournamentId) external payable whenNotPaused {
        Tournament storage t = tournaments[tournamentId];
        require(t.state == TournamentState.Registration, "ChessTournament: not in registration");
        require(!registered[tournamentId][msg.sender], "ChessTournament: already registered");
        require(t.players.length < t.maxPlayers, "ChessTournament: tournament full");
        require(msg.value >= t.entryFee, "ChessTournament: insufficient fee");

        t.players.push(msg.sender);
        registered[tournamentId][msg.sender] = true;
        t.prizePool += msg.value;

        playerStats[tournamentId][msg.sender] = PlayerStats({
            tournamentId: tournamentId,
            player: msg.sender,
            score: 0,
            wins: 0,
            draws: 0,
            losses: 0,
            buchholz: 0
        });

        emit PlayerRegistered(tournamentId, msg.sender);
    }

    /**
     * @notice Start the tournament (closes registration)
     * @param tournamentId The tournament to start
     */
    function startTournament(uint256 tournamentId) external {
        Tournament storage t = tournaments[tournamentId];
        require(msg.sender == t.organizer || msg.sender == owner(), "ChessTournament: not authorized");
        require(t.state == TournamentState.Registration, "ChessTournament: not in registration");
        require(t.players.length >= 4, "ChessTournament: need at least 4 players");

        t.state = TournamentState.Active;
        t.currentRound = 1;

        emit TournamentStarted(tournamentId);
    }

    /**
     * @notice Create a match between two players (Swiss pairing)
     * @param tournamentId The tournament
     * @param white White player
     * @param black Black player
     * @return matchId The new match ID
     */
    function createMatch(uint256 tournamentId, address white, address black)
        external
        returns (uint256 matchId)
    {
        Tournament storage t = tournaments[tournamentId];
        require(msg.sender == t.organizer || msg.sender == owner(), "ChessTournament: not authorized");
        require(t.state == TournamentState.Active, "ChessTournament: not active");
        require(registered[tournamentId][white], "ChessTournament: white not registered");
        require(registered[tournamentId][black], "ChessTournament: black not registered");
        require(!hasPlayed[tournamentId][white][black], "ChessTournament: already played each other");

        matchId = ++matchCounter;
        matches[matchId] = Match({
            tournamentId: tournamentId,
            round: t.currentRound,
            white: white,
            black: black,
            result: MatchResult.Pending,
            playedAt: 0
        });

        roundMatches[tournamentId][t.currentRound].push(matchId);
        hasPlayed[tournamentId][white][black] = true;
        hasPlayed[tournamentId][black][white] = true;

        emit MatchCreated(matchId, tournamentId, t.currentRound, white, black);
    }

    /**
     * @notice Report the result of a match
     * @param matchId The match ID
     * @param result The match result
     */
    function reportResult(uint256 matchId, MatchResult result) external {
        Match storage m = matches[matchId];
        Tournament storage t = tournaments[m.tournamentId];
        require(msg.sender == t.organizer || msg.sender == owner(), "ChessTournament: not authorized");
        require(m.result == MatchResult.Pending, "ChessTournament: already reported");
        require(result != MatchResult.Pending, "ChessTournament: invalid result");

        m.result = result;
        m.playedAt = block.timestamp;

        PlayerStats storage ws = playerStats[m.tournamentId][m.white];
        PlayerStats storage bs = playerStats[m.tournamentId][m.black];

        if (result == MatchResult.WhiteWins) {
            ws.score += 2;
            ws.wins++;
            bs.losses++;
        } else if (result == MatchResult.BlackWins) {
            bs.score += 2;
            bs.wins++;
            ws.losses++;
        } else {
            // Draw
            ws.score += 1;
            bs.score += 1;
            ws.draws++;
            bs.draws++;
        }

        emit MatchResultReported(matchId, result);
    }

    /**
     * @notice Advance to the next round
     * @param tournamentId The tournament
     */
    function advanceRound(uint256 tournamentId) external {
        Tournament storage t = tournaments[tournamentId];
        require(msg.sender == t.organizer || msg.sender == owner(), "ChessTournament: not authorized");
        require(t.state == TournamentState.Active, "ChessTournament: not active");
        require(t.currentRound < t.totalRounds, "ChessTournament: all rounds completed");

        // Calculate Buchholz tiebreakers for current standings
        _updateBuchholz(tournamentId);

        t.currentRound++;
        emit RoundAdvanced(tournamentId, t.currentRound);
    }

    /**
     * @notice Claim prize (top 3 players claim after tournament completion)
     * @param tournamentId The tournament
     * @param first First place player
     * @param second Second place player
     * @param third Third place player
     */
    function claimPrize(uint256 tournamentId, address first, address second, address third)
        external
        nonReentrant
    {
        Tournament storage t = tournaments[tournamentId];
        require(msg.sender == t.organizer || msg.sender == owner(), "ChessTournament: not authorized");
        require(t.state == TournamentState.Active, "ChessTournament: not active");
        require(t.currentRound >= t.totalRounds, "ChessTournament: rounds not finished");

        t.state = TournamentState.Completed;
        _updateBuchholz(tournamentId);

        uint256 fee = (t.prizePool * platformFeePercent) / 100;
        uint256 distributable = t.prizePool - fee;

        uint256 p1 = (distributable * FIRST_SHARE) / 100;
        uint256 p2 = (distributable * SECOND_SHARE) / 100;
        uint256 p3 = distributable - p1 - p2;

        (bool s1,) = first.call{value: p1}("");
        require(s1, "ChessTournament: 1st transfer failed");
        emit PrizeClaimed(tournamentId, first, p1, 1);

        (bool s2,) = second.call{value: p2}("");
        require(s2, "ChessTournament: 2nd transfer failed");
        emit PrizeClaimed(tournamentId, second, p2, 2);

        (bool s3,) = third.call{value: p3}("");
        require(s3, "ChessTournament: 3rd transfer failed");
        emit PrizeClaimed(tournamentId, third, p3, 3);

        if (fee > 0) {
            (bool sf,) = owner().call{value: fee}("");
            require(sf, "ChessTournament: fee transfer failed");
        }

        emit TournamentCompleted(tournamentId);
    }

    // ── Internal ─────────────────────────────────────────────

    /**
     * @dev Update Buchholz tiebreaker scores for all players
     */
    function _updateBuchholz(uint256 tournamentId) internal {
        Tournament storage t = tournaments[tournamentId];
        for (uint256 i = 0; i < t.players.length; i++) {
            address p = t.players[i];
            uint256 buch = 0;
            // Sum opponents' scores
            for (uint256 j = 0; j < t.players.length; j++) {
                address opp = t.players[j];
                if (hasPlayed[tournamentId][p][opp]) {
                    buch += playerStats[tournamentId][opp].score;
                }
            }
            playerStats[tournamentId][p].buchholz = buch;
        }
    }

    // ── Admin ────────────────────────────────────────────────

    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 20, "ChessTournament: fee too high");
        platformFeePercent = _fee;
    }

    // ── View Helpers ─────────────────────────────────────────

    function getPlayers(uint256 tournamentId) external view returns (address[] memory) {
        return tournaments[tournamentId].players;
    }

    function getRoundMatches(uint256 tournamentId, uint256 round) external view returns (uint256[] memory) {
        return roundMatches[tournamentId][round];
    }
}
