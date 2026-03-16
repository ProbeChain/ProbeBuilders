// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SimpleStaking
 * @author ProbeChain Team
 * @notice Simple native token staking with fixed APR on ProbeChain Rydberg Testnet
 * @dev Stake PROBE, earn rewards at configurable rate, compound earnings
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

contract SimpleStaking is Ownable, ReentrancyGuard, Pausable {
    /// @notice Staker info
    struct StakeInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
        uint256 stakedAt;
        uint256 lastClaimAt;
        uint256 totalClaimed;
    }

    /// @notice Global staking stats
    struct StakingStats {
        uint256 totalStaked;
        uint256 totalRewardsPaid;
        uint256 totalStakers;
        uint256 rewardRate;     // APR in basis points (1000 = 10%)
    }

    mapping(address => StakeInfo) private _stakes;
    address[] private _stakers;
    mapping(address => bool) private _isStaker;

    StakingStats public stats;
    uint256 public minStake = 0.01 ether;
    uint256 public maxStake = 1000 ether;
    uint256 public cooldownPeriod = 0; // 0 for testnet

    /// @notice Emitted on stake
    event Staked(address indexed user, uint256 amount);
    /// @notice Emitted on unstake
    event Unstaked(address indexed user, uint256 amount);
    /// @notice Emitted on reward claim
    event RewardsClaimed(address indexed user, uint256 amount);
    /// @notice Emitted on compound
    event Compounded(address indexed user, uint256 rewardAmount);
    /// @notice Emitted when reward rate changes
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);

    error InsufficientStake(uint256 staked, uint256 requested);
    error BelowMinStake(uint256 amount, uint256 min);
    error AboveMaxStake(uint256 total, uint256 max);
    error NoRewardsToClaim();
    error CooldownNotMet(uint256 remaining);
    error ZeroAmount();
    error InsufficientRewardPool();

    constructor() {
        stats.rewardRate = 1200; // 12% APR default
    }

    /**
     * @notice Stake native PROBE tokens
     */
    function stake() external payable nonReentrant whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        if (msg.value < minStake) revert BelowMinStake(msg.value, minStake);

        StakeInfo storage info = _stakes[msg.sender];
        if (info.amount + msg.value > maxStake) revert AboveMaxStake(info.amount + msg.value, maxStake);

        // Calculate pending rewards before adding new stake
        if (info.amount > 0) {
            info.pendingRewards += _calculateRewards(msg.sender);
        }

        info.amount += msg.value;
        info.stakedAt = block.timestamp;
        info.lastClaimAt = block.timestamp;

        stats.totalStaked += msg.value;

        if (!_isStaker[msg.sender]) {
            _isStaker[msg.sender] = true;
            _stakers.push(msg.sender);
            stats.totalStakers++;
        }

        emit Staked(msg.sender, msg.value);
    }

    /**
     * @notice Unstake tokens
     * @param amount The amount to unstake
     */
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        StakeInfo storage info = _stakes[msg.sender];
        if (info.amount < amount) revert InsufficientStake(info.amount, amount);

        if (cooldownPeriod > 0 && block.timestamp < info.stakedAt + cooldownPeriod) {
            revert CooldownNotMet(info.stakedAt + cooldownPeriod - block.timestamp);
        }

        // Calculate pending rewards
        info.pendingRewards += _calculateRewards(msg.sender);
        info.lastClaimAt = block.timestamp;

        info.amount -= amount;
        stats.totalStaked -= amount;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Unstake transfer failed");

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Claim accumulated rewards
     */
    function claimRewards() external nonReentrant whenNotPaused {
        StakeInfo storage info = _stakes[msg.sender];
        uint256 pending = info.pendingRewards + _calculateRewards(msg.sender);
        if (pending == 0) revert NoRewardsToClaim();
        if (pending > address(this).balance - stats.totalStaked) revert InsufficientRewardPool();

        info.pendingRewards = 0;
        info.lastClaimAt = block.timestamp;
        info.totalClaimed += pending;
        stats.totalRewardsPaid += pending;

        (bool success, ) = msg.sender.call{value: pending}("");
        require(success, "Reward transfer failed");

        emit RewardsClaimed(msg.sender, pending);
    }

    /**
     * @notice Compound rewards back into staking position
     */
    function compound() external nonReentrant whenNotPaused {
        StakeInfo storage info = _stakes[msg.sender];
        uint256 pending = info.pendingRewards + _calculateRewards(msg.sender);
        if (pending == 0) revert NoRewardsToClaim();

        info.pendingRewards = 0;
        info.lastClaimAt = block.timestamp;
        info.amount += pending;
        stats.totalStaked += pending;

        emit Compounded(msg.sender, pending);
    }

    /**
     * @notice Get stake info for a user
     * @param user The user address
     * @return info The stake info with updated pending rewards
     */
    function getStakeInfo(address user) external view returns (StakeInfo memory info) {
        info = _stakes[user];
        info.pendingRewards += _calculateRewards(user);
        return info;
    }

    /**
     * @notice Calculate pending rewards for a user
     * @param user The user address
     * @return rewards The pending reward amount
     */
    function pendingReward(address user) external view returns (uint256 rewards) {
        return _stakes[user].pendingRewards + _calculateRewards(user);
    }

    /**
     * @notice Get current APR
     * @return apr The annual percentage rate in basis points
     */
    function getAPR() external view returns (uint256 apr) {
        return stats.rewardRate;
    }

    /**
     * @dev Calculate rewards based on time and stake
     * @param user The user address
     * @return reward The calculated reward
     */
    function _calculateRewards(address user) private view returns (uint256 reward) {
        StakeInfo storage info = _stakes[user];
        if (info.amount == 0 || info.lastClaimAt == 0) return 0;

        uint256 elapsed = block.timestamp - info.lastClaimAt;
        // reward = staked * rate * elapsed / (365 days * 10000)
        reward = (info.amount * stats.rewardRate * elapsed) / (365 days * 10000);
    }

    /// @notice Fund the reward pool
    function fundRewardPool() external payable onlyOwner {
        require(msg.value > 0, "Must fund > 0");
    }

    /// @notice Set reward rate (APR in basis points)
    function setRewardRate(uint256 rate) external onlyOwner {
        require(rate <= 50000, "Max 500% APR");
        uint256 old = stats.rewardRate;
        stats.rewardRate = rate;
        emit RewardRateUpdated(old, rate);
    }

    /// @notice Set min/max stake
    function setStakeLimits(uint256 min, uint256 max) external onlyOwner {
        require(min < max, "Min must be < max");
        minStake = min;
        maxStake = max;
    }

    /// @notice Set cooldown period
    function setCooldownPeriod(uint256 period) external onlyOwner { cooldownPeriod = period; }

    /// @notice Get total stakers count
    function getStakerCount() external view returns (uint256) { return stats.totalStakers; }

    receive() external payable {}
}
