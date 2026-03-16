// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title StakeRouter
 * @author ProbeChain Labs
 * @notice Multi-validator staking router that tracks delegation, supports
 *         rebalancing and reward compounding across multiple validators.
 * @dev Designed for ProbeChain Rydberg Testnet (Chain ID 8004, EVM London).
 */

// ---------------------------------------------------------------------------
// Inline: Ownable
// ---------------------------------------------------------------------------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }
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
    constructor() { _status = _NOT_ENTERED; }
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED; _; _status = _NOT_ENTERED;
    }
}

// ---------------------------------------------------------------------------
// Inline: Pausable
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Main Contract
// ---------------------------------------------------------------------------
contract StakeRouter is Ownable, ReentrancyGuard, Pausable {
    struct Delegation {
        uint256 amount;
        uint256 rewardDebt;
        uint256 delegatedAt;
    }

    struct ValidatorInfo {
        address validator;
        uint256 totalDelegated;
        uint256 rewardPool;
        bool active;
    }

    /// @notice Whitelisted validators.
    mapping(address => ValidatorInfo) public validators;
    address[] public validatorList;

    /// @notice user => validator => Delegation
    mapping(address => mapping(address => Delegation)) public delegations;

    /// @notice user => list of validators they delegated to
    mapping(address => address[]) public userValidators;

    /// @notice Total staked across all validators.
    uint256 public totalStaked;

    // ---- Events ----------------------------------------------------------
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event StakeDelegated(address indexed user, address indexed validator, uint256 amount);
    event StakeUndelegated(address indexed user, address indexed validator, uint256 amount);
    event Rebalanced(address indexed user, address indexed fromValidator, address indexed toValidator, uint256 amount);
    event RewardsCompounded(address indexed user, address indexed validator, uint256 reward);
    event RewardsDeposited(address indexed validator, uint256 amount);

    // ---- Admin -----------------------------------------------------------

    /// @notice Add a validator to the whitelist.
    function addValidator(address validator) external onlyOwner {
        require(validator != address(0), "Zero address");
        require(!validators[validator].active, "Already active");
        validators[validator] = ValidatorInfo({
            validator: validator,
            totalDelegated: 0,
            rewardPool: 0,
            active: true
        });
        validatorList.push(validator);
        emit ValidatorAdded(validator);
    }

    /// @notice Remove a validator from the whitelist.
    function removeValidator(address validator) external onlyOwner {
        require(validators[validator].active, "Not active");
        validators[validator].active = false;
        emit ValidatorRemoved(validator);
    }

    /// @notice Deposit rewards for a specific validator.
    function depositRewards(address validator) external payable onlyOwner {
        require(validators[validator].active, "Validator not active");
        require(msg.value > 0, "Zero deposit");
        validators[validator].rewardPool += msg.value;
        emit RewardsDeposited(validator, msg.value);
    }

    // ---- Core Functions --------------------------------------------------

    /**
     * @notice Delegate stake across multiple validators in one call.
     * @param _validators Array of validator addresses.
     * @param amounts     Corresponding stake amounts.
     */
    function delegateStake(
        address[] calldata _validators,
        uint256[] calldata amounts
    ) external payable nonReentrant whenNotPaused {
        require(_validators.length == amounts.length, "Length mismatch");
        require(_validators.length > 0, "Empty arrays");

        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        require(msg.value == totalAmount, "Incorrect PROBE sent");

        for (uint256 i = 0; i < _validators.length; i++) {
            address v = _validators[i];
            uint256 amt = amounts[i];
            require(validators[v].active, "Validator not active");
            require(amt > 0, "Zero amount");

            Delegation storage d = delegations[msg.sender][v];
            if (d.amount == 0) {
                userValidators[msg.sender].push(v);
                d.delegatedAt = block.timestamp;
            }
            d.amount += amt;
            validators[v].totalDelegated += amt;
            totalStaked += amt;

            emit StakeDelegated(msg.sender, v, amt);
        }
    }

    /**
     * @notice Undelegate stake from a single validator.
     * @param validator The validator to undelegate from.
     * @param amount    Amount to withdraw.
     */
    function undelegateStake(
        address validator,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        Delegation storage d = delegations[msg.sender][validator];
        require(d.amount >= amount, "Insufficient delegation");
        require(amount > 0, "Zero amount");

        d.amount -= amount;
        validators[validator].totalDelegated -= amount;
        totalStaked -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");

        emit StakeUndelegated(msg.sender, validator, amount);
    }

    /**
     * @notice Rebalance: move stake from one validator to another.
     * @param fromValidator Source validator.
     * @param toValidator   Destination validator.
     * @param amount        Amount to move.
     */
    function rebalance(
        address fromValidator,
        address toValidator,
        uint256 amount
    ) external whenNotPaused {
        require(validators[toValidator].active, "Target not active");
        require(amount > 0, "Zero amount");

        Delegation storage fromDel = delegations[msg.sender][fromValidator];
        require(fromDel.amount >= amount, "Insufficient delegation");

        fromDel.amount -= amount;
        validators[fromValidator].totalDelegated -= amount;

        Delegation storage toDel = delegations[msg.sender][toValidator];
        if (toDel.amount == 0) {
            userValidators[msg.sender].push(toValidator);
            toDel.delegatedAt = block.timestamp;
        }
        toDel.amount += amount;
        validators[toValidator].totalDelegated += amount;

        emit Rebalanced(msg.sender, fromValidator, toValidator, amount);
    }

    /**
     * @notice Compound rewards — claims proportional share of validator reward pool
     *         and re-delegates it.
     * @param validator The validator whose rewards to compound.
     */
    function compoundRewards(address validator) external nonReentrant whenNotPaused {
        ValidatorInfo storage vi = validators[validator];
        require(vi.active, "Validator not active");

        Delegation storage d = delegations[msg.sender][validator];
        require(d.amount > 0, "No delegation");
        require(vi.rewardPool > 0, "No rewards");

        uint256 share = (d.amount * vi.rewardPool) / vi.totalDelegated;
        require(share > 0, "Share is zero");

        vi.rewardPool -= share;
        d.amount += share;
        vi.totalDelegated += share;
        totalStaked += share;

        emit RewardsCompounded(msg.sender, validator, share);
    }

    // ---- Views -----------------------------------------------------------

    function getUserValidators(address user) external view returns (address[] memory) {
        return userValidators[user];
    }

    function getDelegation(address user, address validator) external view returns (uint256 amount, uint256 rewardDebt, uint256 delegatedAt) {
        Delegation memory d = delegations[user][validator];
        return (d.amount, d.rewardDebt, d.delegatedAt);
    }

    function getValidatorCount() external view returns (uint256) {
        return validatorList.length;
    }

    receive() external payable {}
}
