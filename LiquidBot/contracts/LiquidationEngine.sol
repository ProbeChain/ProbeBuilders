// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title LiquidationEngine
 * @author ProbeChain Labs
 * @notice Liquidation bot engine with keeper incentives and a 5% liquidation bonus.
 * @dev Designed for ProbeChain Rydberg Testnet (Chain ID 8004, EVM London).
 */

// ---------------------------------------------------------------------------
// Inline: Ownable
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Inline: ReentrancyGuard
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Inline: Pausable
// ---------------------------------------------------------------------------
abstract contract Pausable is Ownable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function pause() external onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

// ---------------------------------------------------------------------------
// Main Contract
// ---------------------------------------------------------------------------
contract LiquidationEngine is Ownable, ReentrancyGuard, Pausable {
    /// @notice Liquidation bonus percentage (5 %).
    uint256 public constant LIQUIDATION_BONUS_BPS = 500;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Minimum keeper reward in wei.
    uint256 public keeperReward;

    struct Position {
        uint256 id;
        address protocol;
        address user;
        uint256 collateral;
        uint256 debt;
        bool liquidated;
        uint256 monitoredAt;
    }

    uint256 private _nextPositionId;
    mapping(uint256 => Position) public positions;
    mapping(address => bool) public registeredKeepers;
    mapping(address => uint256) public keeperBonuses;

    // ---- Events ----------------------------------------------------------
    event PositionMonitored(uint256 indexed positionId, address indexed protocol, address indexed user, uint256 collateral, uint256 debt);
    event LiquidationExecuted(uint256 indexed positionId, address indexed keeper, uint256 repayAmount, uint256 bonus);
    event BonusClaimed(address indexed keeper, uint256 amount);
    event KeeperRegistered(address indexed keeper);
    event KeeperRemoved(address indexed keeper);
    event KeeperRewardUpdated(uint256 newReward);

    constructor(uint256 _keeperReward) {
        keeperReward = _keeperReward;
        _nextPositionId = 1;
    }

    // ---- Keeper Management -----------------------------------------------

    /// @notice Register the caller as a keeper.
    function registerKeeper() external whenNotPaused {
        require(!registeredKeepers[msg.sender], "Already registered");
        registeredKeepers[msg.sender] = true;
        emit KeeperRegistered(msg.sender);
    }

    /// @notice Owner removes a keeper.
    function removeKeeper(address keeper) external onlyOwner {
        require(registeredKeepers[keeper], "Not a keeper");
        registeredKeepers[keeper] = false;
        emit KeeperRemoved(keeper);
    }

    /// @notice Owner updates the keeper reward.
    function setKeeperReward(uint256 _keeperReward) external onlyOwner {
        keeperReward = _keeperReward;
        emit KeeperRewardUpdated(_keeperReward);
    }

    // ---- Core Functions --------------------------------------------------

    /**
     * @notice Monitor a position for potential liquidation.
     * @param protocol  The lending protocol address.
     * @param user      The position owner.
     * @param collateral Current collateral value (wei).
     * @param debt       Current debt value (wei).
     * @return positionId  The newly created position identifier.
     */
    function monitorPosition(
        address protocol,
        address user,
        uint256 collateral,
        uint256 debt
    ) external whenNotPaused returns (uint256 positionId) {
        require(protocol != address(0), "Invalid protocol");
        require(user != address(0), "Invalid user");
        require(collateral > 0 && debt > 0, "Zero values");

        positionId = _nextPositionId++;
        positions[positionId] = Position({
            id: positionId,
            protocol: protocol,
            user: user,
            collateral: collateral,
            debt: debt,
            liquidated: false,
            monitoredAt: block.timestamp
        });

        emit PositionMonitored(positionId, protocol, user, collateral, debt);
    }

    /**
     * @notice Execute a liquidation on a monitored position.
     * @param positionId  The position to liquidate.
     * @param repayAmount The amount being repaid to cover the debt.
     */
    function executeLiquidation(
        uint256 positionId,
        uint256 repayAmount
    ) external payable nonReentrant whenNotPaused {
        require(registeredKeepers[msg.sender], "Not a registered keeper");

        Position storage pos = positions[positionId];
        require(pos.id != 0, "Position does not exist");
        require(!pos.liquidated, "Already liquidated");
        require(repayAmount > 0 && repayAmount <= pos.debt, "Invalid repay amount");

        // Mark liquidated
        pos.liquidated = true;

        // Calculate 5 % bonus
        uint256 bonus = (repayAmount * LIQUIDATION_BONUS_BPS) / BPS_DENOMINATOR;
        uint256 totalKeeperReward = bonus + keeperReward;

        keeperBonuses[msg.sender] += totalKeeperReward;

        emit LiquidationExecuted(positionId, msg.sender, repayAmount, totalKeeperReward);
    }

    /**
     * @notice Keeper claims accumulated bonus.
     */
    function claimBonus() external nonReentrant whenNotPaused {
        uint256 amount = keeperBonuses[msg.sender];
        require(amount > 0, "No bonus to claim");

        keeperBonuses[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");

        emit BonusClaimed(msg.sender, amount);
    }

    // ---- Views -----------------------------------------------------------

    /// @notice Get position details.
    function getPosition(uint256 positionId) external view returns (Position memory) {
        require(positions[positionId].id != 0, "Position does not exist");
        return positions[positionId];
    }

    /// @notice Total positions created.
    function totalPositions() external view returns (uint256) {
        return _nextPositionId - 1;
    }

    // ---- Funding ---------------------------------------------------------

    /// @notice Fund the contract so it can pay keeper bonuses.
    receive() external payable {}

    /// @notice Owner withdraws remaining funds.
    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Withdraw failed");
    }
}
