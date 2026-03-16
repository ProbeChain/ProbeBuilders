// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title RewardDistributor
 * @author ProbeChain Team
 * @notice Universal reward distributor with multiple concurrent staking pools on ProbeChain
 * @dev Supports multiple reward tokens, configurable rates, and time-based reward accumulation
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender); _; }
    function owner() public view virtual returns (address) { return _owner; }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner); _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardReentrantCall();
        _status = _ENTERED; _; _status = _NOT_ENTERED;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    error ExpectedPause();
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    modifier whenPaused() { if (!_paused) revert ExpectedPause(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract RewardDistributor is Ownable, ReentrancyGuard, Pausable {
    /// @notice Reward pool configuration
    struct Pool {
        uint256 id;
        address rewardToken;
        uint256 rewardRate;       // tokens per second
        uint256 duration;         // pool duration in seconds
        uint256 totalStaked;
        uint256 rewardPerTokenStored;
        uint256 lastUpdateTime;
        uint256 periodFinish;
        bool active;
    }

    /// @notice User stake info per pool
    struct UserStake {
        uint256 amount;
        uint256 rewardPerTokenPaid;
        uint256 rewards;
    }

    mapping(uint256 => Pool) private _pools;
    mapping(uint256 => mapping(address => UserStake)) private _userStakes;

    uint256 private _nextPoolId = 1;
    uint256 public totalPools;

    /// @notice Emitted when a pool is created
    event PoolCreated(uint256 indexed poolId, address rewardToken, uint256 rewardRate, uint256 duration);
    /// @notice Emitted on stake
    event Staked(uint256 indexed poolId, address indexed user, uint256 amount);
    /// @notice Emitted on withdraw
    event Withdrawn(uint256 indexed poolId, address indexed user, uint256 amount);
    /// @notice Emitted on reward claim
    event RewardClaimed(uint256 indexed poolId, address indexed user, uint256 reward);

    error PoolNotFound(uint256 poolId);
    error PoolNotActive(uint256 poolId);
    error ZeroAmount();
    error InsufficientStake(uint256 staked, uint256 requested);
    error NoRewardToClaim();

    /**
     * @notice Create a new reward pool
     * @param rewardToken The ERC20 token used for rewards
     * @param rewardRate Tokens distributed per second
     * @param duration Pool duration in seconds
     * @return poolId The created pool ID
     */
    function createPool(
        address rewardToken,
        uint256 rewardRate,
        uint256 duration
    ) external onlyOwner returns (uint256 poolId) {
        poolId = _nextPoolId++;
        _pools[poolId] = Pool({
            id: poolId,
            rewardToken: rewardToken,
            rewardRate: rewardRate,
            duration: duration,
            totalStaked: 0,
            rewardPerTokenStored: 0,
            lastUpdateTime: block.timestamp,
            periodFinish: block.timestamp + duration,
            active: true
        });
        totalPools++;
        emit PoolCreated(poolId, rewardToken, rewardRate, duration);
    }

    /**
     * @notice Stake tokens into a reward pool (sends native ETH/PROBE)
     * @param poolId The pool to stake in
     */
    function stake(uint256 poolId, uint256 amount) external payable nonReentrant whenNotPaused {
        Pool storage pool = _pools[poolId];
        if (pool.id == 0) revert PoolNotFound(poolId);
        if (!pool.active) revert PoolNotActive(poolId);
        if (amount == 0) revert ZeroAmount();

        _updateReward(poolId, msg.sender);

        // For simplicity, this accepts native ETH as the staking token
        require(msg.value == amount, "Sent value must match amount");

        _userStakes[poolId][msg.sender].amount += amount;
        pool.totalStaked += amount;

        emit Staked(poolId, msg.sender, amount);
    }

    /**
     * @notice Withdraw staked tokens from a pool
     * @param poolId The pool to withdraw from
     * @param amount The amount to withdraw
     */
    function withdraw(uint256 poolId, uint256 amount) external nonReentrant whenNotPaused {
        Pool storage pool = _pools[poolId];
        if (pool.id == 0) revert PoolNotFound(poolId);
        if (amount == 0) revert ZeroAmount();

        UserStake storage userStake = _userStakes[poolId][msg.sender];
        if (userStake.amount < amount) revert InsufficientStake(userStake.amount, amount);

        _updateReward(poolId, msg.sender);

        userStake.amount -= amount;
        pool.totalStaked -= amount;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdraw failed");

        emit Withdrawn(poolId, msg.sender, amount);
    }

    /**
     * @notice Claim accumulated rewards from a pool
     * @param poolId The pool to claim from
     */
    function claimReward(uint256 poolId) external nonReentrant whenNotPaused {
        Pool storage pool = _pools[poolId];
        if (pool.id == 0) revert PoolNotFound(poolId);

        _updateReward(poolId, msg.sender);

        UserStake storage userStake = _userStakes[poolId][msg.sender];
        uint256 reward = userStake.rewards;
        if (reward == 0) revert NoRewardToClaim();

        userStake.rewards = 0;

        bool success = IERC20(pool.rewardToken).transfer(msg.sender, reward);
        require(success, "Reward transfer failed");

        emit RewardClaimed(poolId, msg.sender, reward);
    }

    /**
     * @notice Get earned rewards for a user in a pool
     * @param poolId The pool ID
     * @param user The user address
     * @return earned The earned reward amount
     */
    function earned(uint256 poolId, address user) public view returns (uint256) {
        Pool storage pool = _pools[poolId];
        UserStake storage userStake = _userStakes[poolId][user];

        uint256 rewardPerToken = _rewardPerToken(pool);
        return (userStake.amount * (rewardPerToken - userStake.rewardPerTokenPaid)) / 1e18 + userStake.rewards;
    }

    /**
     * @notice Get pool info
     * @param poolId The pool ID
     * @return pool The pool data
     */
    function getPool(uint256 poolId) external view returns (Pool memory pool) {
        if (_pools[poolId].id == 0) revert PoolNotFound(poolId);
        return _pools[poolId];
    }

    /**
     * @notice Get user stake info
     * @param poolId The pool ID
     * @param user The user address
     * @return stakeInfo The user stake data
     */
    function getUserStake(uint256 poolId, address user) external view returns (UserStake memory stakeInfo) {
        return _userStakes[poolId][user];
    }

    /// @dev Calculate reward per token
    function _rewardPerToken(Pool storage pool) private view returns (uint256) {
        if (pool.totalStaked == 0) return pool.rewardPerTokenStored;
        uint256 lastTime = block.timestamp < pool.periodFinish ? block.timestamp : pool.periodFinish;
        uint256 elapsed = lastTime > pool.lastUpdateTime ? lastTime - pool.lastUpdateTime : 0;
        return pool.rewardPerTokenStored + (elapsed * pool.rewardRate * 1e18) / pool.totalStaked;
    }

    /// @dev Update reward state
    function _updateReward(uint256 poolId, address user) private {
        Pool storage pool = _pools[poolId];
        pool.rewardPerTokenStored = _rewardPerToken(pool);
        pool.lastUpdateTime = block.timestamp < pool.periodFinish ? block.timestamp : pool.periodFinish;

        UserStake storage userStake = _userStakes[poolId][user];
        userStake.rewards = earned(poolId, user);
        userStake.rewardPerTokenPaid = pool.rewardPerTokenStored;
    }

    /// @notice Deactivate a pool
    function deactivatePool(uint256 poolId) external onlyOwner {
        if (_pools[poolId].id == 0) revert PoolNotFound(poolId);
        _pools[poolId].active = false;
    }

    receive() external payable {}
}
