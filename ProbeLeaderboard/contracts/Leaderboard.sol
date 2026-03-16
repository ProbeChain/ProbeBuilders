// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Leaderboard
 * @author ProbeChain Rydberg Testnet
 * @notice Global leaderboard system with multiple boards, score submission, and ranking
 * @dev Create boards, submit scores by authorized reporters, query top players and ranks
 */

// ---------- Inlined Ownable ----------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: caller is not the owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner); _owner = newOwner;
    }
}

// ---------- Inlined ReentrancyGuard ----------
abstract contract ReentrancyGuard {
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    constructor() { _status = _NOT_ENTERED; }
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED; _; _status = _NOT_ENTERED;
    }
}

// ---------- Inlined Pausable ----------
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

contract Leaderboard is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum SortOrder { HighestFirst, LowestFirst }
    enum BoardCategory { Gaming, DeFi, Social, Development, Trading, Governance, Other }

    // ---------- Structs ----------
    struct Board {
        uint256 id;
        string name;
        BoardCategory category;
        SortOrder sortOrder;
        address creator;
        uint256 playerCount;
        uint256 totalSubmissions;
        uint256 createdAt;
        bool active;
    }

    struct PlayerScore {
        address player;
        uint256 score;
        bytes32 proofHash;
        uint256 submittedAt;
        uint256 submissions;
    }

    // ---------- State ----------
    uint256 public nextBoardId;
    uint256 public maxTopPlayers;

    mapping(uint256 => Board) public boards;
    mapping(uint256 => mapping(address => PlayerScore)) public playerScores;
    mapping(uint256 => address[]) public boardPlayers;
    mapping(address => bool) public authorizedReporters;
    mapping(address => uint256[]) public playerBoards;

    // ---------- Events ----------
    /// @notice Emitted when a new board is registered
    event BoardRegistered(uint256 indexed boardId, string name, BoardCategory category, SortOrder sortOrder);
    /// @notice Emitted when a score is submitted
    event ScoreSubmitted(uint256 indexed boardId, address indexed player, uint256 score, bytes32 proofHash);
    /// @notice Emitted when a score is updated (new high/low score)
    event ScoreUpdated(uint256 indexed boardId, address indexed player, uint256 oldScore, uint256 newScore);
    /// @notice Emitted when a reporter is authorized
    event ReporterAuthorized(address indexed reporter);
    /// @notice Emitted when a board is deactivated
    event BoardDeactivated(uint256 indexed boardId);

    // ---------- Constructor ----------
    constructor(uint256 _maxTopPlayers) Ownable() ReentrancyGuard() Pausable() {
        maxTopPlayers = _maxTopPlayers > 0 ? _maxTopPlayers : 100;
        nextBoardId = 1;
    }

    /**
     * @notice Authorize a score reporter
     * @param reporter The address to authorize
     */
    function authorizeReporter(address reporter) external onlyOwner {
        require(reporter != address(0), "Zero address");
        authorizedReporters[reporter] = true;
        emit ReporterAuthorized(reporter);
    }

    /**
     * @notice Revoke reporter authorization
     * @param reporter The address to revoke
     */
    function revokeReporter(address reporter) external onlyOwner {
        authorizedReporters[reporter] = false;
    }

    /**
     * @notice Register a new leaderboard
     * @param _name Board name
     * @param category Board category
     * @param sortOrder Whether highest or lowest score wins
     * @return boardId The created board ID
     */
    function registerBoard(string calldata _name, BoardCategory category, SortOrder sortOrder)
        external
        whenNotPaused
        returns (uint256 boardId)
    {
        require(bytes(_name).length > 0 && bytes(_name).length <= 128, "Invalid name");

        boardId = nextBoardId++;
        Board storage b = boards[boardId];
        b.id = boardId;
        b.name = _name;
        b.category = category;
        b.sortOrder = sortOrder;
        b.creator = msg.sender;
        b.createdAt = block.timestamp;
        b.active = true;

        emit BoardRegistered(boardId, _name, category, sortOrder);
    }

    /**
     * @notice Submit a score for a player on a board
     * @param boardId The target board
     * @param player The player address
     * @param score The score value
     * @param proofHash Hash of proof data
     */
    function submitScore(uint256 boardId, address player, uint256 score, bytes32 proofHash)
        external
        whenNotPaused
    {
        require(authorizedReporters[msg.sender] || msg.sender == owner(), "Not authorized reporter");
        Board storage b = boards[boardId];
        require(b.active, "Board not active");
        require(player != address(0), "Zero player address");
        require(proofHash != bytes32(0), "Empty proof hash");

        PlayerScore storage ps = playerScores[boardId][player];
        b.totalSubmissions++;

        if (ps.player == address(0)) {
            // New player on this board
            ps.player = player;
            ps.score = score;
            ps.proofHash = proofHash;
            ps.submittedAt = block.timestamp;
            ps.submissions = 1;

            boardPlayers[boardId].push(player);
            playerBoards[player].push(boardId);
            b.playerCount++;

            emit ScoreSubmitted(boardId, player, score, proofHash);
        } else {
            // Existing player - update if better score
            uint256 oldScore = ps.score;
            bool isBetter;
            if (b.sortOrder == SortOrder.HighestFirst) {
                isBetter = score > oldScore;
            } else {
                isBetter = score < oldScore;
            }

            ps.submissions++;
            if (isBetter) {
                ps.score = score;
                ps.proofHash = proofHash;
                ps.submittedAt = block.timestamp;
                emit ScoreUpdated(boardId, player, oldScore, score);
            }

            emit ScoreSubmitted(boardId, player, score, proofHash);
        }
    }

    /**
     * @notice Get top players for a board (sorted)
     * @param boardId The board to query
     * @param count Number of top players to return
     * @return players Array of player addresses
     * @return scores Array of corresponding scores
     */
    function getTopPlayers(uint256 boardId, uint256 count)
        external
        view
        returns (address[] memory players, uint256[] memory scores)
    {
        Board storage b = boards[boardId];
        require(b.id != 0, "Board does not exist");

        address[] storage allPlayers = boardPlayers[boardId];
        uint256 len = allPlayers.length;
        uint256 resultCount = count < len ? count : len;

        // Copy to memory for sorting
        address[] memory tempPlayers = new address[](len);
        uint256[] memory tempScores = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            tempPlayers[i] = allPlayers[i];
            tempScores[i] = playerScores[boardId][allPlayers[i]].score;
        }

        // Simple selection sort for top N
        for (uint256 i = 0; i < resultCount; i++) {
            uint256 bestIdx = i;
            for (uint256 j = i + 1; j < len; j++) {
                bool jIsBetter;
                if (b.sortOrder == SortOrder.HighestFirst) {
                    jIsBetter = tempScores[j] > tempScores[bestIdx];
                } else {
                    jIsBetter = tempScores[j] < tempScores[bestIdx];
                }
                if (jIsBetter) bestIdx = j;
            }
            if (bestIdx != i) {
                (tempPlayers[i], tempPlayers[bestIdx]) = (tempPlayers[bestIdx], tempPlayers[i]);
                (tempScores[i], tempScores[bestIdx]) = (tempScores[bestIdx], tempScores[i]);
            }
        }

        players = new address[](resultCount);
        scores = new uint256[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            players[i] = tempPlayers[i];
            scores[i] = tempScores[i];
        }
    }

    /**
     * @notice Get a player's rank on a board
     * @param boardId The board to query
     * @param player The player address
     * @return rank The player's rank (1-indexed, 0 if not found)
     * @return score The player's score
     */
    function getPlayerRank(uint256 boardId, address player)
        external
        view
        returns (uint256 rank, uint256 score)
    {
        Board storage b = boards[boardId];
        require(b.id != 0, "Board does not exist");

        PlayerScore storage ps = playerScores[boardId][player];
        if (ps.player == address(0)) return (0, 0);

        score = ps.score;
        rank = 1;

        address[] storage allPlayers = boardPlayers[boardId];
        for (uint256 i = 0; i < allPlayers.length; i++) {
            if (allPlayers[i] != player) {
                uint256 otherScore = playerScores[boardId][allPlayers[i]].score;
                if (b.sortOrder == SortOrder.HighestFirst) {
                    if (otherScore > score) rank++;
                } else {
                    if (otherScore < score) rank++;
                }
            }
        }
    }

    /**
     * @notice Deactivate a board
     * @param boardId The board to deactivate
     */
    function deactivateBoard(uint256 boardId) external {
        Board storage b = boards[boardId];
        require(b.creator == msg.sender || msg.sender == owner(), "Not authorized");
        require(b.active, "Already inactive");
        b.active = false;
        emit BoardDeactivated(boardId);
    }

    // ---------- View ----------
    function getPlayerBoards(address player) external view returns (uint256[] memory) {
        return playerBoards[player];
    }

    function getBoardPlayerCount(uint256 boardId) external view returns (uint256) {
        return boards[boardId].playerCount;
    }

    function setMaxTopPlayers(uint256 _max) external onlyOwner {
        require(_max > 0, "Must be > 0");
        maxTopPlayers = _max;
    }
}
