// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PredictionMarket
 * @author ProbeChain
 * @notice Prediction markets with multi-outcome betting and oracle resolution
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() { _status = _NOT_ENTERED; }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

abstract contract Pausable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function _pause() internal whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function _unpause() internal whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

contract PredictionMarket is Ownable, ReentrancyGuard, Pausable {
    /// @notice Market status
    enum MarketStatus { Open, Closed, Resolved }

    /// @notice Prediction market
    struct Market {
        uint256 id;
        string question;
        string[] options;
        uint256 resolveDate;
        MarketStatus status;
        uint256 winningOutcome;
        uint256 totalPool;
        address creator;
        uint256 createdAt;
    }

    /// @dev Market counter
    uint256 private _nextMarketId;

    /// @dev Market ID => Market
    mapping(uint256 => Market) private _markets;

    /// @dev Market ID => outcome index => total bet amount
    mapping(uint256 => mapping(uint256 => uint256)) private _outcomePools;

    /// @dev Market ID => user => outcome index => bet amount
    mapping(uint256 => mapping(address => mapping(uint256 => uint256))) private _bets;

    /// @dev Market ID => user => claimed
    mapping(uint256 => mapping(address => bool)) private _claimed;

    /// @dev Authorized oracles
    mapping(address => bool) public oracles;

    /// @dev All market IDs
    uint256[] private _marketIds;

    /// @dev Platform fee BPS
    uint256 public platformFeeBPS;

    /// @dev Collected fees
    uint256 public collectedFees;

    // ───────── Events ─────────

    /// @notice Emitted when a market is created
    event MarketCreated(uint256 indexed marketId, string question, uint256 resolveDate, address indexed creator);

    /// @notice Emitted when a bet is placed
    event OutcomePurchased(uint256 indexed marketId, address indexed buyer, uint256 outcomeIndex, uint256 amount);

    /// @notice Emitted when a market is resolved
    event MarketResolved(uint256 indexed marketId, uint256 winningOutcome, address indexed oracle);

    /// @notice Emitted when winnings are claimed
    event WinningsClaimed(uint256 indexed marketId, address indexed claimer, uint256 amount);

    /// @notice Emitted when an oracle is updated
    event OracleUpdated(address indexed oracle, bool status);

    // ───────── Constructor ─────────

    constructor() {
        _nextMarketId = 1;
        platformFeeBPS = 200; // 2%
    }

    // ───────── Admin ─────────

    function setOracle(address oracle, bool status) external onlyOwner {
        require(oracle != address(0), "PM: zero address");
        oracles[oracle] = status;
        emit OracleUpdated(oracle, status);
    }

    function setPlatformFee(uint256 feeBPS) external onlyOwner {
        require(feeBPS <= 500, "PM: fee too high");
        platformFeeBPS = feeBPS;
    }

    function withdrawFees(address payable to) external onlyOwner nonReentrant {
        require(collectedFees > 0, "PM: no fees");
        uint256 amount = collectedFees;
        collectedFees = 0;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "PM: transfer failed");
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Create a new prediction market
    /// @param question The question being predicted
    /// @param options Array of outcome option strings
    /// @param resolveDate Unix timestamp when market can be resolved
    /// @return marketId The new market ID
    function createMarket(
        string calldata question,
        string[] calldata options,
        uint256 resolveDate
    ) external whenNotPaused returns (uint256 marketId) {
        require(bytes(question).length > 0, "PM: empty question");
        require(options.length >= 2, "PM: need 2+ options");
        require(options.length <= 10, "PM: too many options");
        require(resolveDate > block.timestamp, "PM: past resolve date");

        marketId = _nextMarketId++;

        Market storage m = _markets[marketId];
        m.id = marketId;
        m.question = question;
        m.resolveDate = resolveDate;
        m.status = MarketStatus.Open;
        m.winningOutcome = type(uint256).max;
        m.totalPool = 0;
        m.creator = msg.sender;
        m.createdAt = block.timestamp;

        for (uint256 i = 0; i < options.length; i++) {
            m.options.push(options[i]);
        }

        _marketIds.push(marketId);

        emit MarketCreated(marketId, question, resolveDate, msg.sender);
    }

    /// @notice Buy an outcome in a market
    /// @param marketId The market to bet on
    /// @param outcomeIndex The outcome index to buy
    function buyOutcome(
        uint256 marketId,
        uint256 outcomeIndex
    ) external payable whenNotPaused nonReentrant {
        Market storage m = _markets[marketId];
        require(m.id != 0, "PM: not found");
        require(m.status == MarketStatus.Open, "PM: not open");
        require(block.timestamp < m.resolveDate, "PM: expired");
        require(outcomeIndex < m.options.length, "PM: invalid outcome");
        require(msg.value > 0, "PM: zero amount");

        _bets[marketId][msg.sender][outcomeIndex] += msg.value;
        _outcomePools[marketId][outcomeIndex] += msg.value;
        m.totalPool += msg.value;

        emit OutcomePurchased(marketId, msg.sender, outcomeIndex, msg.value);
    }

    /// @notice Resolve a market with the winning outcome (oracle only)
    /// @param marketId The market to resolve
    /// @param winningOutcome The winning outcome index
    function resolveMarket(
        uint256 marketId,
        uint256 winningOutcome
    ) external whenNotPaused {
        require(oracles[msg.sender], "PM: not oracle");

        Market storage m = _markets[marketId];
        require(m.id != 0, "PM: not found");
        require(m.status == MarketStatus.Open, "PM: not open");
        require(block.timestamp >= m.resolveDate, "PM: too early");
        require(winningOutcome < m.options.length, "PM: invalid outcome");

        m.status = MarketStatus.Resolved;
        m.winningOutcome = winningOutcome;

        // Collect platform fee
        uint256 fee = (m.totalPool * platformFeeBPS) / 10000;
        collectedFees += fee;

        emit MarketResolved(marketId, winningOutcome, msg.sender);
    }

    /// @notice Claim winnings from a resolved market
    /// @param marketId The market to claim from
    function claimWinnings(uint256 marketId) external whenNotPaused nonReentrant {
        Market storage m = _markets[marketId];
        require(m.id != 0, "PM: not found");
        require(m.status == MarketStatus.Resolved, "PM: not resolved");
        require(!_claimed[marketId][msg.sender], "PM: already claimed");

        uint256 userBet = _bets[marketId][msg.sender][m.winningOutcome];
        require(userBet > 0, "PM: no winning bet");

        _claimed[marketId][msg.sender] = true;

        uint256 winnerPool = _outcomePools[marketId][m.winningOutcome];
        uint256 fee = (m.totalPool * platformFeeBPS) / 10000;
        uint256 distributable = m.totalPool - fee;

        uint256 payout = (userBet * distributable) / winnerPool;

        (bool sent, ) = msg.sender.call{value: payout}("");
        require(sent, "PM: transfer failed");

        emit WinningsClaimed(marketId, msg.sender, payout);
    }

    // ───────── View Functions ─────────

    /// @notice Get market details
    function getMarket(uint256 marketId) external view returns (Market memory) {
        require(_markets[marketId].id != 0, "PM: not found");
        return _markets[marketId];
    }

    /// @notice Get pool amount for an outcome
    function getOutcomePool(uint256 marketId, uint256 outcomeIndex) external view returns (uint256) {
        return _outcomePools[marketId][outcomeIndex];
    }

    /// @notice Get user bet on a specific outcome
    function getUserBet(uint256 marketId, address user, uint256 outcomeIndex) external view returns (uint256) {
        return _bets[marketId][user][outcomeIndex];
    }

    /// @notice Get all market IDs
    function getMarketIds() external view returns (uint256[] memory) {
        return _marketIds;
    }

    /// @notice Total markets
    function totalMarkets() external view returns (uint256) {
        return _nextMarketId - 1;
    }
}
