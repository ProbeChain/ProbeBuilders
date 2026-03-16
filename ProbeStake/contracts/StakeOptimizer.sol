// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title StakeOptimizer
 * @author ProbeBuilders
 * @notice Staking optimizer with auto-compound and validator delegation for ProbeChain.
 * @dev Supports stake, unstake, claimRewards, autoCompound, and validator tracking.
 */

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: not owner");
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

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

    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function _pause() internal { _paused = true; emit Paused(msg.sender); }
    function _unpause() internal { _paused = false; emit Unpaused(msg.sender); }
}

contract StakeOptimizer is Ownable, ReentrancyGuard, Pausable {
    // ---- State ----
    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    /// @notice Reward rate per second (scaled by 1e18)
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalStaked;

    /// @notice Unstaking cooldown period
    uint256 public cooldownPeriod = 3 days;

    /// @notice Auto-compound fee (1%)
    uint256 public compoundFeeBps = 100;
    address public feeCollector;

    struct UserStake {
        uint256 amount;
        uint256 rewardPerTokenPaid;
        uint256 rewardsAccrued;
        uint256 unstakeRequestTime;
        uint256 unstakeAmount;
        uint256 validatorId;    // which validator the user delegates to
    }

    mapping(address => UserStake) public userStakes;

    struct Validator {
        uint256 id;
        string name;
        address operator;
        uint256 totalDelegated;
        uint256 commissionBps;  // validator commission
        bool isActive;
    }

    mapping(uint256 => Validator) public validators;
    uint256 public nextValidatorId;

    // ---- Events ----
    event Staked(address indexed user, uint256 amount, uint256 validatorId);
    event UnstakeRequested(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event AutoCompounded(address indexed caller, uint256 totalCompounded, uint256 fee);
    event RewardRateUpdated(uint256 newRate);
    event ValidatorAdded(uint256 indexed validatorId, string name, address operator);
    event ValidatorUpdated(uint256 indexed validatorId, bool isActive);
    event DelegationChanged(address indexed user, uint256 oldValidator, uint256 newValidator);
    event CooldownUpdated(uint256 newCooldown);

    constructor(address _stakingToken, address _rewardToken, uint256 _rewardRate, address _feeCollector) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
        feeCollector = _feeCollector;
        lastUpdateTime = block.timestamp;
    }

    // ---- Modifiers ----

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            UserStake storage us = userStakes[account];
            us.rewardsAccrued = earned(account);
            us.rewardPerTokenPaid = rewardPerTokenStored;
        }
        _;
    }

    // ---- View Functions ----

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) return rewardPerTokenStored;
        uint256 elapsed = block.timestamp - lastUpdateTime;
        return rewardPerTokenStored + (elapsed * rewardRate * 1e18) / totalStaked;
    }

    function earned(address account) public view returns (uint256) {
        UserStake storage us = userStakes[account];
        return (us.amount * (rewardPerToken() - us.rewardPerTokenPaid)) / 1e18 + us.rewardsAccrued;
    }

    // ---- Staking ----

    /// @notice Stake tokens and delegate to a validator
    function stake(uint256 amount, uint256 validatorId) external nonReentrant whenNotPaused updateReward(msg.sender) {
        require(amount > 0, "Stake: zero amount");
        require(validators[validatorId].isActive, "Stake: validator inactive");

        UserStake storage us = userStakes[msg.sender];

        // If changing validator, update delegation
        if (us.amount > 0 && us.validatorId != validatorId) {
            uint256 oldId = us.validatorId;
            validators[oldId].totalDelegated -= us.amount;
            validators[validatorId].totalDelegated += us.amount;
            emit DelegationChanged(msg.sender, oldId, validatorId);
        }

        stakingToken.transferFrom(msg.sender, address(this), amount);
        us.amount += amount;
        us.validatorId = validatorId;
        totalStaked += amount;
        validators[validatorId].totalDelegated += amount;

        emit Staked(msg.sender, amount, validatorId);
    }

    /// @notice Request unstake (starts cooldown)
    function requestUnstake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        UserStake storage us = userStakes[msg.sender];
        require(us.amount >= amount, "Stake: insufficient stake");
        require(amount > 0, "Stake: zero amount");

        us.unstakeRequestTime = block.timestamp;
        us.unstakeAmount = amount;

        emit UnstakeRequested(msg.sender, amount);
    }

    /// @notice Complete unstake after cooldown
    function unstake() external nonReentrant updateReward(msg.sender) {
        UserStake storage us = userStakes[msg.sender];
        require(us.unstakeAmount > 0, "Stake: no unstake request");
        require(block.timestamp >= us.unstakeRequestTime + cooldownPeriod, "Stake: cooldown not met");

        uint256 amount = us.unstakeAmount;
        us.amount -= amount;
        us.unstakeAmount = 0;
        us.unstakeRequestTime = 0;
        totalStaked -= amount;
        validators[us.validatorId].totalDelegated -= amount;

        stakingToken.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    /// @notice Claim accumulated rewards
    function claimRewards() external nonReentrant updateReward(msg.sender) {
        UserStake storage us = userStakes[msg.sender];
        uint256 reward = us.rewardsAccrued;
        require(reward > 0, "Stake: no rewards");

        // Apply validator commission
        uint256 commission = 0;
        Validator storage v = validators[us.validatorId];
        if (v.commissionBps > 0) {
            commission = (reward * v.commissionBps) / 10000;
            rewardToken.transfer(v.operator, commission);
        }

        us.rewardsAccrued = 0;
        uint256 userReward = reward - commission;
        rewardToken.transfer(msg.sender, userReward);

        emit RewardsClaimed(msg.sender, userReward);
    }

    /// @notice Auto-compound: claim rewards and restake for all eligible users
    /// @dev Can be called by anyone (e.g., keeper bot). Compounds for a batch of users.
    function autoCompound(address[] calldata users) external nonReentrant whenNotPaused {
        uint256 totalCompounded = 0;

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            // Update rewards
            rewardPerTokenStored = rewardPerToken();
            lastUpdateTime = block.timestamp;
            UserStake storage us = userStakes[user];
            us.rewardsAccrued = earned(user);
            us.rewardPerTokenPaid = rewardPerTokenStored;

            uint256 reward = us.rewardsAccrued;
            if (reward == 0) continue;

            us.rewardsAccrued = 0;

            // Take compound fee
            uint256 fee = (reward * compoundFeeBps) / 10000;
            uint256 compoundAmount = reward - fee;

            if (fee > 0) {
                rewardToken.transfer(feeCollector, fee);
            }

            // If staking token == reward token, restake
            if (address(stakingToken) == address(rewardToken)) {
                us.amount += compoundAmount;
                totalStaked += compoundAmount;
                validators[us.validatorId].totalDelegated += compoundAmount;
                totalCompounded += compoundAmount;
            } else {
                // Otherwise just claim to user
                rewardToken.transfer(user, compoundAmount);
                totalCompounded += compoundAmount;
            }
        }

        emit AutoCompounded(msg.sender, totalCompounded, (totalCompounded * compoundFeeBps) / (10000 - compoundFeeBps));
    }

    // ---- Validator Management ----

    function addValidator(string calldata name_, address operator, uint256 commissionBps) external onlyOwner returns (uint256 id) {
        require(commissionBps <= 3000, "Stake: commission too high"); // max 30%
        id = nextValidatorId++;
        validators[id] = Validator({
            id: id,
            name: name_,
            operator: operator,
            totalDelegated: 0,
            commissionBps: commissionBps,
            isActive: true
        });
        emit ValidatorAdded(id, name_, operator);
    }

    function setValidatorActive(uint256 validatorId, bool isActive) external onlyOwner {
        validators[validatorId].isActive = isActive;
        emit ValidatorUpdated(validatorId, isActive);
    }

    // ---- Admin ----

    function setRewardRate(uint256 _rate) external onlyOwner updateReward(address(0)) {
        rewardRate = _rate;
        emit RewardRateUpdated(_rate);
    }

    function setCooldownPeriod(uint256 _period) external onlyOwner {
        require(_period <= 30 days, "Stake: cooldown too long");
        cooldownPeriod = _period;
        emit CooldownUpdated(_period);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /// @notice Fund the contract with reward tokens
    function fundRewards(uint256 amount) external onlyOwner {
        rewardToken.transferFrom(msg.sender, address(this), amount);
    }
}
