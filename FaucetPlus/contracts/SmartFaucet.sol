// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title SmartFaucet
 * @author ProbeBuilders
 * @notice Smart faucet with anti-sybil protection, cooldowns, and whitelist tiers
 * @dev Verified developers get higher claim amounts; banning and claim history tracking
 */

abstract contract Ownable {
    address private _owner;
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert OwnableInvalidOwner(address(0));
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender);
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardReentrantCall();
        _status = 2;
        _;
        _status = 1;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
}

/// @title SmartFaucet — Anti-sybil faucet with tiered claims
contract SmartFaucet is Ownable, ReentrancyGuard, Pausable {

    /// @notice Claim record
    struct ClaimRecord {
        uint64 lastClaimTime;
        uint256 totalClaimed;
        uint32 claimCount;
    }

    /// @notice Tier levels for claim amounts
    enum Tier { Standard, Verified, Premium }

    /// @notice Base claim amount for standard users
    uint256 public standardClaimAmount = 0.1 ether;
    /// @notice Multiplier for verified developers (2x)
    uint256 public verifiedMultiplier = 2;
    /// @notice Multiplier for premium users (5x)
    uint256 public premiumMultiplier = 5;
    /// @notice Cooldown period between claims
    uint64 public cooldownPeriod = 24 hours;
    /// @notice Maximum daily claims across all users
    uint256 public dailyGlobalLimit = 100 ether;
    /// @notice Current day's distributed amount
    uint256 public dailyDistributed;
    /// @notice Day tracker for resetting daily limit
    uint256 public currentDay;
    /// @notice Total claims made
    uint256 public totalClaimsMade;

    /// @notice Per-address claim records
    mapping(address => ClaimRecord) public claimRecords;
    /// @notice Whitelist tiers: address => Tier
    mapping(address => Tier) public addressTier;
    /// @notice Banned addresses
    mapping(address => bool) public banned;

    event TokensClaimed(address indexed claimer, uint256 amount, Tier tier, uint256 totalClaimed);
    event ClaimAmountUpdated(uint256 newAmount);
    event CooldownUpdated(uint64 newCooldown);
    event AddressWhitelisted(address indexed addr, Tier tier);
    event AddressBanned(address indexed addr, bool isBanned);
    event DailyLimitUpdated(uint256 newLimit);
    event FaucetFunded(address indexed funder, uint256 amount);
    event FaucetDrained(address indexed owner, uint256 amount);

    error CooldownNotExpired(uint256 remainingSeconds);
    error AddressIsBanned();
    error DailyLimitReached();
    error InsufficientFaucetBalance();
    error TransferFailed();

    constructor() Ownable(msg.sender) {
        currentDay = block.timestamp / 1 days;
    }

    /// @notice Claim tokens from the faucet
    function claimTokens() external whenNotPaused nonReentrant {
        if (banned[msg.sender]) revert AddressIsBanned();

        _resetDailyIfNeeded();

        ClaimRecord storage record = claimRecords[msg.sender];
        if (record.lastClaimTime > 0) {
            uint256 elapsed = block.timestamp - record.lastClaimTime;
            if (elapsed < cooldownPeriod) {
                revert CooldownNotExpired(cooldownPeriod - uint64(elapsed));
            }
        }

        uint256 amount = _getClaimAmount(msg.sender);
        if (dailyDistributed + amount > dailyGlobalLimit) revert DailyLimitReached();
        if (address(this).balance < amount) revert InsufficientFaucetBalance();

        record.lastClaimTime = uint64(block.timestamp);
        record.totalClaimed += amount;
        record.claimCount++;
        dailyDistributed += amount;
        totalClaimsMade++;

        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit TokensClaimed(msg.sender, amount, addressTier[msg.sender], record.totalClaimed);
    }

    /// @notice Get the claim amount for an address based on tier
    /// @param addr Address to check
    /// @return amount Claim amount in wei
    function _getClaimAmount(address addr) internal view returns (uint256 amount) {
        Tier t = addressTier[addr];
        if (t == Tier.Premium) {
            amount = standardClaimAmount * premiumMultiplier;
        } else if (t == Tier.Verified) {
            amount = standardClaimAmount * verifiedMultiplier;
        } else {
            amount = standardClaimAmount;
        }
    }

    /// @notice Reset daily counter if new day
    function _resetDailyIfNeeded() internal {
        uint256 today = block.timestamp / 1 days;
        if (today > currentDay) {
            currentDay = today;
            dailyDistributed = 0;
        }
    }

    /// @notice Check how much an address can claim
    function getClaimAmount(address addr) external view returns (uint256) {
        return _getClaimAmount(addr);
    }

    /// @notice Check time remaining before next claim
    /// @param addr Address to check
    /// @return remaining Seconds until next claim (0 if ready)
    function timeUntilNextClaim(address addr) external view returns (uint256 remaining) {
        ClaimRecord storage record = claimRecords[addr];
        if (record.lastClaimTime == 0) return 0;
        uint256 elapsed = block.timestamp - record.lastClaimTime;
        if (elapsed >= cooldownPeriod) return 0;
        return cooldownPeriod - elapsed;
    }

    // ============ Admin Functions ============

    /// @notice Set the base claim amount
    function setClaimAmount(uint256 newAmount) external onlyOwner {
        require(newAmount > 0, "Amount must be > 0");
        standardClaimAmount = newAmount;
        emit ClaimAmountUpdated(newAmount);
    }

    /// @notice Set cooldown period
    function setCooldownPeriod(uint64 newCooldown) external onlyOwner {
        require(newCooldown >= 1 hours, "Min 1 hour cooldown");
        cooldownPeriod = newCooldown;
        emit CooldownUpdated(newCooldown);
    }

    /// @notice Add address to whitelist with tier
    function addToWhitelist(address addr, Tier tier) external onlyOwner {
        require(addr != address(0), "Invalid address");
        addressTier[addr] = tier;
        emit AddressWhitelisted(addr, tier);
    }

    /// @notice Batch whitelist addresses
    function batchWhitelist(address[] calldata addrs, Tier tier) external onlyOwner {
        for (uint256 i = 0; i < addrs.length; i++) {
            addressTier[addrs[i]] = tier;
            emit AddressWhitelisted(addrs[i], tier);
        }
    }

    /// @notice Ban or unban an address
    function banAddress(address addr, bool isBanned) external onlyOwner {
        banned[addr] = isBanned;
        emit AddressBanned(addr, isBanned);
    }

    /// @notice Set daily global limit
    function setDailyGlobalLimit(uint256 newLimit) external onlyOwner {
        dailyGlobalLimit = newLimit;
        emit DailyLimitUpdated(newLimit);
    }

    /// @notice Set tier multipliers
    function setMultipliers(uint256 verified, uint256 premium) external onlyOwner {
        require(verified > 0 && premium > 0, "Must be > 0");
        verifiedMultiplier = verified;
        premiumMultiplier = premium;
    }

    /// @notice Drain faucet (emergency, owner only)
    function drain() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "Nothing to drain");
        (bool ok, ) = payable(owner()).call{value: balance}("");
        if (!ok) revert TransferFailed();
        emit FaucetDrained(owner(), balance);
    }

    /// @notice Fund the faucet
    receive() external payable {
        emit FaucetFunded(msg.sender, msg.value);
    }

    /// @notice Get faucet balance
    function faucetBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
