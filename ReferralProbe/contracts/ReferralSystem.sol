// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ReferralSystem
 * @author ProbeChain Team
 * @notice Multi-tier referral tracking and reward system
 * @dev Supports referral codes, tier-based rewards, and referral chain queries
 */
contract ReferralSystem {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "ReferralSystem: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ReferralSystem: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _guardStatus = 1;
    modifier nonReentrant() {
        require(_guardStatus == 1, "ReferralSystem: reentrant call");
        _guardStatus = 2;
        _;
        _guardStatus = 1;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "ReferralSystem: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Structs ────────────────────────────────────────────────────────
    struct Referrer {
        address wallet;
        string code;
        uint256 tier1Referrals;
        uint256 tier2Referrals;
        uint256 totalEarned;
        uint256 pendingReward;
        uint256 registeredAt;
        bool active;
    }

    struct ReferralInfo {
        address referrer;
        address referred;
        uint256 timestamp;
        uint8 tier;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public referrerCount;
    uint256 public referralCount;
    uint256 public tier1Reward = 0.01 ether;
    uint256 public tier2Reward = 0.005 ether;

    mapping(address => Referrer) public referrers;
    mapping(string => address) public codeToAddress;
    mapping(address => address) public referredBy;
    mapping(address => address[]) public directReferrals;
    mapping(uint256 => ReferralInfo) public referrals;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a new referrer registers
    event ReferrerRegistered(address indexed referrer, string code);
    /// @notice Emitted when a referral code is used
    event ReferralUsed(address indexed referred, address indexed referrer, string code, uint8 tier);
    /// @notice Emitted when referral rewards are claimed
    event RewardClaimed(address indexed referrer, uint256 amount);
    /// @notice Emitted when reward tiers are updated
    event RewardTiersUpdated(uint256 tier1Amount, uint256 tier2Amount);
    /// @notice Emitted when the contract is funded
    event ContractFunded(address indexed funder, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /// @notice Fund the contract for referral payouts
    receive() external payable {
        emit ContractFunded(msg.sender, msg.value);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register as a referrer with a unique code
     * @param code Unique referral code string
     */
    function registerReferrer(string calldata code) external whenNotPaused {
        require(bytes(code).length >= 3 && bytes(code).length <= 20, "ReferralSystem: invalid code length");
        require(codeToAddress[code] == address(0), "ReferralSystem: code taken");
        require(referrers[msg.sender].registeredAt == 0, "ReferralSystem: already registered");

        referrerCount++;
        referrers[msg.sender] = Referrer({
            wallet: msg.sender,
            code: code,
            tier1Referrals: 0,
            tier2Referrals: 0,
            totalEarned: 0,
            pendingReward: 0,
            registeredAt: block.timestamp,
            active: true
        });

        codeToAddress[code] = msg.sender;
        emit ReferrerRegistered(msg.sender, code);
    }

    /**
     * @notice Use a referral code (called by the new user)
     * @param code Referral code to use
     */
    function useReferralCode(string calldata code) external whenNotPaused {
        address referrerAddr = codeToAddress[code];
        require(referrerAddr != address(0), "ReferralSystem: invalid code");
        require(referrerAddr != msg.sender, "ReferralSystem: cannot self-refer");
        require(referredBy[msg.sender] == address(0), "ReferralSystem: already referred");

        Referrer storage ref = referrers[referrerAddr];
        require(ref.active, "ReferralSystem: referrer not active");

        // Tier 1: direct referral
        referredBy[msg.sender] = referrerAddr;
        directReferrals[referrerAddr].push(msg.sender);
        ref.tier1Referrals++;
        ref.pendingReward += tier1Reward;

        referralCount++;
        referrals[referralCount] = ReferralInfo({
            referrer: referrerAddr,
            referred: msg.sender,
            timestamp: block.timestamp,
            tier: 1
        });

        emit ReferralUsed(msg.sender, referrerAddr, code, 1);

        // Tier 2: referrer's referrer gets tier2 reward
        address tier2Referrer = referredBy[referrerAddr];
        if (tier2Referrer != address(0)) {
            Referrer storage ref2 = referrers[tier2Referrer];
            if (ref2.active) {
                ref2.tier2Referrals++;
                ref2.pendingReward += tier2Reward;

                referralCount++;
                referrals[referralCount] = ReferralInfo({
                    referrer: tier2Referrer,
                    referred: msg.sender,
                    timestamp: block.timestamp,
                    tier: 2
                });

                emit ReferralUsed(msg.sender, tier2Referrer, "", 2);
            }
        }
    }

    /**
     * @notice Claim accumulated referral rewards
     */
    function claimReferralReward() external nonReentrant whenNotPaused {
        Referrer storage ref = referrers[msg.sender];
        require(ref.pendingReward > 0, "ReferralSystem: no pending reward");
        require(address(this).balance >= ref.pendingReward, "ReferralSystem: insufficient balance");

        uint256 amount = ref.pendingReward;
        ref.pendingReward = 0;
        ref.totalEarned += amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "ReferralSystem: payment failed");

        emit RewardClaimed(msg.sender, amount);
    }

    /**
     * @notice Update reward tier amounts
     * @param _tier1Amount New tier 1 reward
     * @param _tier2Amount New tier 2 reward
     */
    function setRewardTiers(uint256 _tier1Amount, uint256 _tier2Amount) external onlyOwner {
        require(_tier1Amount > 0, "ReferralSystem: zero tier1");
        require(_tier2Amount > 0, "ReferralSystem: zero tier2");
        tier1Reward = _tier1Amount;
        tier2Reward = _tier2Amount;
        emit RewardTiersUpdated(_tier1Amount, _tier2Amount);
    }

    /**
     * @notice Get the referral chain for a user (up to 5 levels)
     * @param user User address
     * @return chain Array of referrer addresses up the chain
     */
    function getReferralChain(address user) external view returns (address[] memory chain) {
        address[] memory temp = new address[](5);
        uint256 count = 0;
        address current = referredBy[user];

        while (current != address(0) && count < 5) {
            temp[count] = current;
            count++;
            current = referredBy[current];
        }

        chain = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            chain[i] = temp[i];
        }
    }

    /**
     * @notice Get direct referrals for a referrer
     * @param referrer Referrer address
     * @return refs Array of referred addresses
     */
    function getDirectReferrals(address referrer) external view returns (address[] memory refs) {
        return directReferrals[referrer];
    }

    /**
     * @notice Deactivate a referrer
     * @param referrer Address to deactivate
     */
    function deactivateReferrer(address referrer) external onlyOwner {
        referrers[referrer].active = false;
    }
}
