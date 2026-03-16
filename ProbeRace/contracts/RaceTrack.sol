// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title RaceTrack
 * @author ProbeChain Builders
 * @notice On-chain racing game with leaderboard and season tracking
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London)
 */

// ──────────────────────────────────────────────────────────────
// Inline Ownable
// ──────────────────────────────────────────────────────────────
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ──────────────────────────────────────────────────────────────
// Inline ReentrancyGuard
// ──────────────────────────────────────────────────────────────
abstract contract ReentrancyGuard {
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// ──────────────────────────────────────────────────────────────
// Inline Pausable
// ──────────────────────────────────────────────────────────────
abstract contract Pausable is Ownable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function pause() external onlyOwner {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

// ──────────────────────────────────────────────────────────────
// RaceTrack
// ──────────────────────────────────────────────────────────────
contract RaceTrack is Ownable, ReentrancyGuard, Pausable {
    // ── Structs ──────────────────────────────────────────────
    struct Race {
        uint256 trackId;
        uint256 entryFee;
        uint256 maxRacers;
        uint256 prizePool;
        uint256 season;
        address creator;
        address[] racers;
        bool finalized;
        address winner;
        uint256 winnerTime;
    }

    struct LeaderboardEntry {
        address racer;
        uint256 totalWins;
        uint256 bestTime;
        uint256 totalEarnings;
    }

    // ── State ────────────────────────────────────────────────
    uint256 public raceCounter;
    uint256 public currentSeason;
    uint256 public platformFeePercent = 5;
    address public oracle;

    mapping(uint256 => Race) public races;
    mapping(uint256 => mapping(address => bool)) public hasJoined;
    mapping(uint256 => mapping(address => uint256)) public finishTimes;
    mapping(uint256 => mapping(address => bytes32)) public proofHashes;
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    /// @dev season => racer => LeaderboardEntry
    mapping(uint256 => mapping(address => LeaderboardEntry)) public leaderboard;
    mapping(uint256 => address[]) public seasonRacers;

    // ── Events ───────────────────────────────────────────────
    event RaceCreated(uint256 indexed raceId, uint256 trackId, uint256 entryFee, uint256 maxRacers, uint256 season);
    event RacerJoined(uint256 indexed raceId, address indexed racer);
    event ResultSubmitted(uint256 indexed raceId, address indexed racer, uint256 finishTime);
    event RaceFinalized(uint256 indexed raceId, address indexed winner, uint256 winnerTime);
    event PrizeClaimed(uint256 indexed raceId, address indexed racer, uint256 amount);
    event SeasonAdvanced(uint256 indexed newSeason);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    // ── Constructor ──────────────────────────────────────────
    constructor(address _oracle) {
        require(_oracle != address(0), "RaceTrack: zero oracle");
        oracle = _oracle;
        currentSeason = 1;
    }

    // ── Modifiers ────────────────────────────────────────────
    modifier onlyOracle() {
        require(msg.sender == oracle, "RaceTrack: caller is not oracle");
        _;
    }

    // ── Core Functions ───────────────────────────────────────

    /**
     * @notice Create a new race on a given track
     * @param trackId Identifier of the track layout
     * @param entryFee Wei required to join the race
     * @param maxRacers Maximum number of participants
     * @return raceId The newly created race ID
     */
    function createRace(uint256 trackId, uint256 entryFee, uint256 maxRacers)
        external
        whenNotPaused
        returns (uint256 raceId)
    {
        require(maxRacers >= 2, "RaceTrack: need at least 2 racers");
        raceId = ++raceCounter;

        Race storage r = races[raceId];
        r.trackId = trackId;
        r.entryFee = entryFee;
        r.maxRacers = maxRacers;
        r.season = currentSeason;
        r.creator = msg.sender;

        emit RaceCreated(raceId, trackId, entryFee, maxRacers, currentSeason);
    }

    /**
     * @notice Join an existing race by paying the entry fee
     * @param raceId The race to join
     */
    function joinRace(uint256 raceId) external payable whenNotPaused nonReentrant {
        Race storage r = races[raceId];
        require(r.creator != address(0), "RaceTrack: race does not exist");
        require(!r.finalized, "RaceTrack: race already finalized");
        require(!hasJoined[raceId][msg.sender], "RaceTrack: already joined");
        require(r.racers.length < r.maxRacers, "RaceTrack: race full");
        require(msg.value == r.entryFee, "RaceTrack: incorrect entry fee");

        r.racers.push(msg.sender);
        r.prizePool += msg.value;
        hasJoined[raceId][msg.sender] = true;

        emit RacerJoined(raceId, msg.sender);
    }

    /**
     * @notice Oracle submits a racer's finish time and proof
     * @param raceId The race identifier
     * @param racer The racer address
     * @param finishTime The finish time in milliseconds
     * @param proofHash Proof hash for verification
     */
    function submitResult(uint256 raceId, address racer, uint256 finishTime, bytes32 proofHash)
        external
        onlyOracle
    {
        Race storage r = races[raceId];
        require(!r.finalized, "RaceTrack: race finalized");
        require(hasJoined[raceId][racer], "RaceTrack: racer not in race");
        require(finishTimes[raceId][racer] == 0, "RaceTrack: result already submitted");

        finishTimes[raceId][racer] = finishTime;
        proofHashes[raceId][racer] = proofHash;

        if (r.winner == address(0) || finishTime < r.winnerTime) {
            r.winner = racer;
            r.winnerTime = finishTime;
        }

        emit ResultSubmitted(raceId, racer, finishTime);
    }

    /**
     * @notice Finalize a race and update leaderboard
     * @param raceId The race to finalize
     */
    function finalizeRace(uint256 raceId) external onlyOracle {
        Race storage r = races[raceId];
        require(!r.finalized, "RaceTrack: already finalized");
        require(r.winner != address(0), "RaceTrack: no results yet");

        r.finalized = true;

        LeaderboardEntry storage entry = leaderboard[r.season][r.winner];
        if (entry.racer == address(0)) {
            entry.racer = r.winner;
            seasonRacers[r.season].push(r.winner);
        }
        entry.totalWins++;
        if (entry.bestTime == 0 || r.winnerTime < entry.bestTime) {
            entry.bestTime = r.winnerTime;
        }

        emit RaceFinalized(raceId, r.winner, r.winnerTime);
    }

    /**
     * @notice Winner claims the prize from a finalized race
     * @param raceId The race to claim from
     */
    function claimPrize(uint256 raceId) external nonReentrant {
        Race storage r = races[raceId];
        require(r.finalized, "RaceTrack: not finalized");
        require(r.winner == msg.sender, "RaceTrack: not the winner");
        require(!hasClaimed[raceId][msg.sender], "RaceTrack: already claimed");

        hasClaimed[raceId][msg.sender] = true;

        uint256 fee = (r.prizePool * platformFeePercent) / 100;
        uint256 payout = r.prizePool - fee;

        leaderboard[r.season][msg.sender].totalEarnings += payout;

        (bool sent,) = msg.sender.call{value: payout}("");
        require(sent, "RaceTrack: transfer failed");

        if (fee > 0) {
            (bool feeSent,) = owner().call{value: fee}("");
            require(feeSent, "RaceTrack: fee transfer failed");
        }

        emit PrizeClaimed(raceId, msg.sender, payout);
    }

    // ── Season Management ────────────────────────────────────

    /// @notice Advance to the next season
    function advanceSeason() external onlyOwner {
        currentSeason++;
        emit SeasonAdvanced(currentSeason);
    }

    // ── Admin ────────────────────────────────────────────────

    /// @notice Update the oracle address
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "RaceTrack: zero oracle");
        emit OracleUpdated(oracle, _oracle);
        oracle = _oracle;
    }

    /// @notice Update the platform fee percentage
    function setPlatformFee(uint256 _fee) external onlyOwner {
        require(_fee <= 20, "RaceTrack: fee too high");
        platformFeePercent = _fee;
    }

    // ── View Helpers ─────────────────────────────────────────

    function getRacers(uint256 raceId) external view returns (address[] memory) {
        return races[raceId].racers;
    }

    function getSeasonRacers(uint256 season) external view returns (address[] memory) {
        return seasonRacers[season];
    }

    function getRaceCount() external view returns (uint256) {
        return raceCounter;
    }
}
