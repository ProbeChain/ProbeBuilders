// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title ChessGame
 * @notice On-chain chess game manager with ELO ranking, wagers, and timeout forfeits
 * @dev Stores move history on-chain; move validation is done off-chain by the oracle
 */
contract ChessGame {
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
    modifier whenNotPaused() { require(!paused, "Paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ──────────────────── Constants ────────────────────
    uint256 public constant BASE_ELO = 1200;
    uint256 public constant K_FACTOR = 32;
    uint256 public constant MOVE_TIMEOUT = 1 days;
    uint256 public constant MIN_WAGER = 0.001 ether;

    // ──────────────────── Data Structures ────────────────────
    enum GameStatus { Open, Active, WhiteWins, BlackWins, Draw, Cancelled }

    struct Game {
        uint256 gameId;
        address white;
        address black;
        uint256 wager;
        GameStatus status;
        bytes32[] moves;
        bool whiteToMove;
        uint256 lastMoveTime;
        uint256 createdAt;
    }

    struct Player {
        uint256 eloRating;
        uint256 wins;
        uint256 losses;
        uint256 draws;
        uint256 gamesPlayed;
        bool registered;
    }

    // ──────────────────── State ────────────────────
    uint256 public nextGameId = 1;
    uint256 public platformFeeBPS = 200; // 2%

    mapping(uint256 => Game) public games;
    mapping(uint256 => bytes32[]) private gameMoves;
    mapping(address => Player) public players;
    mapping(address => uint256) public pendingWithdrawals;
    mapping(address => uint256[]) public playerGames;

    // ──────────────────── Events ────────────────────
    event PlayerRegistered(address indexed player, uint256 eloRating);
    event GameCreated(uint256 indexed gameId, address indexed white, uint256 wager);
    event GameJoined(uint256 indexed gameId, address indexed black);
    event MovePlayed(uint256 indexed gameId, address indexed player, bytes32 moveData, uint256 moveIndex);
    event GameEnded(uint256 indexed gameId, GameStatus result, uint256 whiteElo, uint256 blackElo);
    event GameCancelled(uint256 indexed gameId);
    event RewardsClaimed(address indexed player, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    // ──────────────────── Player Registration ────────────────────

    /**
     * @notice Register as a chess player
     */
    function registerPlayer() external {
        require(!players[msg.sender].registered, "Already registered");
        players[msg.sender] = Player({
            eloRating: BASE_ELO,
            wins: 0,
            losses: 0,
            draws: 0,
            gamesPlayed: 0,
            registered: true
        });
        emit PlayerRegistered(msg.sender, BASE_ELO);
    }

    // ──────────────────── Game Lifecycle ────────────────────

    /**
     * @notice Create a new chess game with a wager
     * @return gameId The new game ID
     */
    function createGame() external payable whenNotPaused returns (uint256) {
        require(players[msg.sender].registered, "Not registered");
        require(msg.value >= MIN_WAGER, "Wager too low");

        uint256 gameId = nextGameId++;
        Game storage g = games[gameId];
        g.gameId = gameId;
        g.white = msg.sender;
        g.wager = msg.value;
        g.status = GameStatus.Open;
        g.whiteToMove = true;
        g.createdAt = block.timestamp;

        playerGames[msg.sender].push(gameId);
        emit GameCreated(gameId, msg.sender, msg.value);
        return gameId;
    }

    /**
     * @notice Join an open game as black by matching the wager
     * @param gameId The game to join
     */
    function joinGame(uint256 gameId) external payable whenNotPaused {
        Game storage g = games[gameId];
        require(g.status == GameStatus.Open, "Not open");
        require(msg.sender != g.white, "Cannot play yourself");
        require(players[msg.sender].registered, "Not registered");
        require(msg.value == g.wager, "Wager mismatch");

        g.black = msg.sender;
        g.status = GameStatus.Active;
        g.lastMoveTime = block.timestamp;
        g.wager += msg.value;

        playerGames[msg.sender].push(gameId);
        emit GameJoined(gameId, msg.sender);
    }

    /**
     * @notice Submit a chess move (encoded as bytes32)
     * @param gameId The game ID
     * @param moveData Encoded move (e.g., algebraic notation hash)
     */
    function submitMove(uint256 gameId, bytes32 moveData) external whenNotPaused {
        Game storage g = games[gameId];
        require(g.status == GameStatus.Active, "Not active");

        if (g.whiteToMove) {
            require(msg.sender == g.white, "Not your turn");
        } else {
            require(msg.sender == g.black, "Not your turn");
        }

        gameMoves[gameId].push(moveData);
        g.whiteToMove = !g.whiteToMove;
        g.lastMoveTime = block.timestamp;

        emit MovePlayed(gameId, msg.sender, moveData, gameMoves[gameId].length - 1);
    }

    /**
     * @notice Claim victory (oracle/owner resolves)
     * @param gameId The game ID
     * @param winner Address of the winner (address(0) for draw)
     */
    function claimVictory(uint256 gameId, address winner) external onlyOwner nonReentrant {
        Game storage g = games[gameId];
        require(g.status == GameStatus.Active, "Not active");

        if (winner == address(0)) {
            // Draw
            g.status = GameStatus.Draw;
            _settleDraw(g);
        } else if (winner == g.white) {
            g.status = GameStatus.WhiteWins;
            _settleWin(g, g.white, g.black);
        } else if (winner == g.black) {
            g.status = GameStatus.BlackWins;
            _settleWin(g, g.black, g.white);
        } else {
            revert("Invalid winner");
        }

        (uint256 wElo, uint256 bElo) = (players[g.white].eloRating, players[g.black].eloRating);
        emit GameEnded(gameId, g.status, wElo, bElo);
    }

    /**
     * @notice Propose a draw (both players must call)
     */
    mapping(uint256 => mapping(address => bool)) public drawProposals;

    function proposeDraw(uint256 gameId) external {
        Game storage g = games[gameId];
        require(g.status == GameStatus.Active, "Not active");
        require(msg.sender == g.white || msg.sender == g.black, "Not player");

        drawProposals[gameId][msg.sender] = true;

        if (drawProposals[gameId][g.white] && drawProposals[gameId][g.black]) {
            g.status = GameStatus.Draw;
            _settleDraw(g);
            emit GameEnded(gameId, GameStatus.Draw, players[g.white].eloRating, players[g.black].eloRating);
        }
    }

    /**
     * @notice Claim timeout forfeit if opponent hasn't moved
     * @param gameId The game ID
     */
    function claimTimeout(uint256 gameId) external nonReentrant {
        Game storage g = games[gameId];
        require(g.status == GameStatus.Active, "Not active");
        require(block.timestamp > g.lastMoveTime + MOVE_TIMEOUT, "Not timed out");

        address winner;
        address loser;
        if (g.whiteToMove) {
            // White timed out, black wins
            require(msg.sender == g.black, "Not eligible");
            g.status = GameStatus.BlackWins;
            winner = g.black;
            loser = g.white;
        } else {
            require(msg.sender == g.white, "Not eligible");
            g.status = GameStatus.WhiteWins;
            winner = g.white;
            loser = g.black;
        }

        _settleWin(g, winner, loser);
        emit GameEnded(gameId, g.status, players[g.white].eloRating, players[g.black].eloRating);
    }

    /**
     * @notice Cancel an open (unjoined) game
     */
    function cancelGame(uint256 gameId) external nonReentrant {
        Game storage g = games[gameId];
        require(g.status == GameStatus.Open, "Not open");
        require(g.white == msg.sender, "Not creator");

        g.status = GameStatus.Cancelled;
        pendingWithdrawals[msg.sender] += g.wager;
        emit GameCancelled(gameId);
    }

    /**
     * @notice Claim accumulated winnings
     */
    function claimRewards() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to claim");
        pendingWithdrawals[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        emit RewardsClaimed(msg.sender, amount);
    }

    // ──────────────────── Internal Settlement ────────────────────

    function _settleWin(Game storage g, address winner, address loser) internal {
        uint256 fee = (g.wager * platformFeeBPS) / 10000;
        uint256 reward = g.wager - fee;
        pendingWithdrawals[winner] += reward;
        pendingWithdrawals[owner] += fee;

        // ELO update
        Player storage w = players[winner];
        Player storage l = players[loser];
        (uint256 newW, uint256 newL) = _calcElo(w.eloRating, l.eloRating);
        w.eloRating = newW;
        l.eloRating = newL;
        w.wins++;
        l.losses++;
        w.gamesPlayed++;
        l.gamesPlayed++;
    }

    function _settleDraw(Game storage g) internal {
        uint256 half = g.wager / 2;
        pendingWithdrawals[g.white] += half;
        pendingWithdrawals[g.black] += g.wager - half;

        players[g.white].draws++;
        players[g.black].draws++;
        players[g.white].gamesPlayed++;
        players[g.black].gamesPlayed++;
    }

    function _calcElo(uint256 winnerElo, uint256 loserElo)
        internal pure returns (uint256 newW, uint256 newL)
    {
        uint256 diff = winnerElo >= loserElo ? winnerElo - loserElo : loserElo - winnerElo;
        if (diff > 400) diff = 400;

        uint256 expected = winnerElo >= loserElo
            ? 50 + (diff * 50) / 400
            : 50 - (diff * 50) / 400;

        uint256 gain = (K_FACTOR * (100 - expected)) / 100;
        if (gain == 0) gain = 1;

        newW = winnerElo + gain;
        newL = loserElo > gain ? loserElo - gain : 1;
    }

    // ──────────────────── Views ────────────────────

    function getMoves(uint256 gameId) external view returns (bytes32[] memory) {
        return gameMoves[gameId];
    }

    function getPlayerGames(address player) external view returns (uint256[] memory) {
        return playerGames[player];
    }

    function setFee(uint256 newFeeBPS) external onlyOwner {
        require(newFeeBPS <= 1000, "Fee too high");
        platformFeeBPS = newFeeBPS;
    }

    receive() external payable {}
}
