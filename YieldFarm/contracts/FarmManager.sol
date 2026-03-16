// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title FarmManager
 * @author ProbeBuilders
 * @notice LP yield farming manager for ProbeChain Rydberg Testnet.
 *         Create farms, stake LP tokens, earn per-second rewards.
 * @dev Inline Ownable, ReentrancyGuard, Pausable. EVM London compatible.
 */

/* ───────── Minimal Interface ───────── */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/* ───────── Abstract helpers (inlined) ───────── */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed prev, address indexed next_);
    error OwnableUnauthorized();
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorized(); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardLocked();
    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardLocked();
        _status = 2;
        _;
        _status = 1;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();
    modifier whenNotPaused() { if (_paused) revert ContractPaused(); _; }
    modifier whenPaused() { if (!_paused) revert ContractNotPaused(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

/* ───────── Main Contract ───────── */

contract FarmManager is Ownable, ReentrancyGuard, Pausable {

    /* ── Constants ── */

    uint256 public constant PRECISION = 1e18;

    /* ── Structs ── */

    /// @notice A yield farm configuration
    struct Farm {
        address lpToken;           // LP token to stake
        address rewardToken;       // reward token
        uint256 rewardRate;        // reward tokens per second (18 decimals)
        uint256 totalStaked;       // total LP staked in this farm
        uint256 accRewardPerShare; // accumulated reward per share (scaled by PRECISION)
        uint256 lastUpdateTime;    // last time accRewardPerShare was updated
        uint256 startTime;         // farm start timestamp
        uint256 endTime;           // farm end timestamp
        bool    active;
    }

    /// @notice User stake info for a specific farm
    struct UserInfo {
        uint256 amount;     // LP tokens staked
        uint256 rewardDebt; // reward debt for proper accounting
    }

    /* ── State ── */

    uint256 public nextFarmId;
    mapping(uint256 => Farm) public farms;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => uint256[]) private _userFarms;

    /* ── Events ── */

    /// @notice Emitted when a new farm is created
    event FarmCreated(uint256 indexed farmId, address lpToken, address rewardToken, uint256 rewardRate, uint256 duration);
    /// @notice Emitted when user stakes LP tokens
    event Staked(uint256 indexed farmId, address indexed user, uint256 amount);
    /// @notice Emitted when user withdraws LP tokens
    event Withdrawn(uint256 indexed farmId, address indexed user, uint256 amount);
    /// @notice Emitted when user claims reward
    event RewardClaimed(uint256 indexed farmId, address indexed user, uint256 amount);
    /// @notice Emitted when a farm is stopped early
    event FarmStopped(uint256 indexed farmId);

    /* ── Errors ── */

    error FarmNotActive();
    error FarmEnded();
    error InsufficientStake();
    error TransferFailed();
    error ZeroAmount();

    /* ── Constructor ── */

    constructor() Ownable() {}

    /* ── Farm management ── */

    /**
     * @notice Create a new yield farm. Owner must fund with reward tokens separately.
     * @param lpToken LP token address for staking
     * @param rewardToken Reward token address
     * @param rewardRate Reward tokens per second (18 decimals)
     * @param duration Farm duration in seconds
     * @return farmId The created farm ID
     */
    function createFarm(
        address lpToken,
        address rewardToken,
        uint256 rewardRate,
        uint256 duration
    ) external onlyOwner returns (uint256 farmId) {
        require(lpToken != address(0), "zero lp");
        require(rewardToken != address(0), "zero reward");
        require(rewardRate > 0, "zero rate");
        require(duration > 0, "zero duration");

        farmId = nextFarmId++;
        farms[farmId] = Farm({
            lpToken: lpToken,
            rewardToken: rewardToken,
            rewardRate: rewardRate,
            totalStaked: 0,
            accRewardPerShare: 0,
            lastUpdateTime: block.timestamp,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            active: true
        });

        emit FarmCreated(farmId, lpToken, rewardToken, rewardRate, duration);
    }

    /**
     * @notice Stop a farm early
     * @param farmId The farm to stop
     */
    function stopFarm(uint256 farmId) external onlyOwner {
        Farm storage farm = farms[farmId];
        if (!farm.active) revert FarmNotActive();
        _updateFarm(farmId);
        farm.active = false;
        farm.endTime = block.timestamp;
        emit FarmStopped(farmId);
    }

    /* ── Core staking functions ── */

    /**
     * @notice Stake LP tokens into a farm
     * @param farmId The farm to stake in
     * @param amount Amount of LP tokens to stake
     */
    function stake(uint256 farmId, uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        Farm storage farm = farms[farmId];
        if (!farm.active) revert FarmNotActive();
        if (block.timestamp >= farm.endTime) revert FarmEnded();

        _updateFarm(farmId);

        UserInfo storage user = userInfo[farmId][msg.sender];

        // Claim any pending reward first
        if (user.amount > 0) {
            uint256 pending = (user.amount * farm.accRewardPerShare / PRECISION) - user.rewardDebt;
            if (pending > 0) {
                _safeRewardTransfer(farm.rewardToken, msg.sender, pending);
                emit RewardClaimed(farmId, msg.sender, pending);
            }
        } else {
            _userFarms[msg.sender].push(farmId);
        }

        // Transfer LP tokens to this contract
        bool ok = IERC20(farm.lpToken).transferFrom(msg.sender, address(this), amount);
        if (!ok) revert TransferFailed();

        user.amount += amount;
        farm.totalStaked += amount;
        user.rewardDebt = user.amount * farm.accRewardPerShare / PRECISION;

        emit Staked(farmId, msg.sender, amount);
    }

    /**
     * @notice Withdraw LP tokens from a farm
     * @param farmId The farm to withdraw from
     * @param amount Amount of LP tokens to withdraw
     */
    function withdraw(uint256 farmId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        UserInfo storage user = userInfo[farmId][msg.sender];
        if (user.amount < amount) revert InsufficientStake();

        Farm storage farm = farms[farmId];
        _updateFarm(farmId);

        // Claim pending reward
        uint256 pending = (user.amount * farm.accRewardPerShare / PRECISION) - user.rewardDebt;
        if (pending > 0) {
            _safeRewardTransfer(farm.rewardToken, msg.sender, pending);
            emit RewardClaimed(farmId, msg.sender, pending);
        }

        user.amount -= amount;
        farm.totalStaked -= amount;
        user.rewardDebt = user.amount * farm.accRewardPerShare / PRECISION;

        bool ok = IERC20(farm.lpToken).transfer(msg.sender, amount);
        if (!ok) revert TransferFailed();

        emit Withdrawn(farmId, msg.sender, amount);
    }

    /**
     * @notice Claim reward without withdrawing LP tokens
     * @param farmId The farm to claim from
     */
    function claimReward(uint256 farmId) external nonReentrant {
        Farm storage farm = farms[farmId];
        _updateFarm(farmId);

        UserInfo storage user = userInfo[farmId][msg.sender];
        uint256 pending = (user.amount * farm.accRewardPerShare / PRECISION) - user.rewardDebt;

        if (pending > 0) {
            user.rewardDebt = user.amount * farm.accRewardPerShare / PRECISION;
            _safeRewardTransfer(farm.rewardToken, msg.sender, pending);
            emit RewardClaimed(farmId, msg.sender, pending);
        }
    }

    /* ── View helpers ── */

    /// @notice Get pending reward for a user in a farm
    function pendingReward(uint256 farmId, address account) external view returns (uint256) {
        Farm storage farm = farms[farmId];
        UserInfo storage user = userInfo[farmId][account];

        uint256 accReward = farm.accRewardPerShare;
        if (block.timestamp > farm.lastUpdateTime && farm.totalStaked > 0) {
            uint256 elapsed = _min(block.timestamp, farm.endTime) - farm.lastUpdateTime;
            uint256 reward = elapsed * farm.rewardRate;
            accReward += reward * PRECISION / farm.totalStaked;
        }

        return (user.amount * accReward / PRECISION) - user.rewardDebt;
    }

    /// @notice Get all farm IDs where user has staked
    function getUserFarms(address account) external view returns (uint256[] memory) {
        return _userFarms[account];
    }

    /// @notice Check if a farm is currently active and within duration
    function isFarmActive(uint256 farmId) external view returns (bool) {
        Farm storage farm = farms[farmId];
        return farm.active && block.timestamp < farm.endTime;
    }

    /* ── Internal ── */

    /// @dev Update accumulated rewards per share for a farm
    function _updateFarm(uint256 farmId) private {
        Farm storage farm = farms[farmId];
        if (block.timestamp <= farm.lastUpdateTime) return;

        if (farm.totalStaked == 0) {
            farm.lastUpdateTime = block.timestamp;
            return;
        }

        uint256 end = _min(block.timestamp, farm.endTime);
        if (end <= farm.lastUpdateTime) return;

        uint256 elapsed = end - farm.lastUpdateTime;
        uint256 reward = elapsed * farm.rewardRate;
        farm.accRewardPerShare += reward * PRECISION / farm.totalStaked;
        farm.lastUpdateTime = block.timestamp;
    }

    /// @dev Safe transfer: don't fail if contract lacks reward balance
    function _safeRewardTransfer(address token, address to, uint256 amount) private {
        uint256 bal = IERC20(token).balanceOf(address(this));
        uint256 toSend = amount > bal ? bal : amount;
        if (toSend > 0) {
            IERC20(token).transfer(to, toSend);
        }
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
