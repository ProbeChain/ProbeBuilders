// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title ParametricInsurance
 * @author ProbeChain Labs
 * @notice Parametric insurance that auto-executes payouts when an oracle
 *         reports that a threshold condition has been met.
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
contract ParametricInsurance is Ownable, ReentrancyGuard, Pausable {

    enum PolicyStatus { Active, Triggered, Claimed, Expired }

    struct Policy {
        uint256 id;
        address policyholder;
        string eventType;         // e.g. "earthquake", "flood", "drought"
        uint256 threshold;        // oracle value that triggers payout
        uint256 premium;          // premium paid by policyholder
        uint256 payout;           // payout amount if triggered
        uint256 duration;         // policy duration in seconds
        uint256 createdAt;
        uint256 expiresAt;
        PolicyStatus status;
        uint256 oracleValue;      // recorded oracle value when triggered
        uint256 triggeredAt;
    }

    uint256 private _nextPolicyId;
    mapping(uint256 => Policy) public policies;
    mapping(address => uint256[]) public userPolicies;
    mapping(address => bool) public authorizedOracles;

    uint256 public totalPremiums;
    uint256 public totalPayouts;
    uint256 public activePolicyCount;

    // ---- Events ----------------------------------------------------------
    event PolicyCreated(uint256 indexed policyId, address indexed policyholder, string eventType, uint256 threshold, uint256 premium, uint256 payout, uint256 duration);
    event PolicyTriggered(uint256 indexed policyId, uint256 oracleValue, address indexed oracle);
    event PayoutClaimed(uint256 indexed policyId, address indexed policyholder, uint256 amount);
    event PolicyExpired(uint256 indexed policyId);
    event OracleAuthorized(address indexed oracle);
    event OracleRevoked(address indexed oracle);

    constructor() {
        _nextPolicyId = 1;
    }

    // ---- Oracle Management -----------------------------------------------

    function authorizeOracle(address oracle) external onlyOwner {
        require(oracle != address(0), "Zero address");
        authorizedOracles[oracle] = true;
        emit OracleAuthorized(oracle);
    }

    function revokeOracle(address oracle) external onlyOwner {
        authorizedOracles[oracle] = false;
        emit OracleRevoked(oracle);
    }

    // ---- Core Functions --------------------------------------------------

    /**
     * @notice Create a new insurance policy by paying the premium.
     * @param eventType  Type of insured event.
     * @param threshold  Oracle value threshold that triggers payout.
     * @param payout     Payout amount in wei.
     * @param duration   Policy duration in seconds.
     * @return policyId  The new policy identifier.
     */
    function createPolicy(
        string calldata eventType,
        uint256 threshold,
        uint256 payout,
        uint256 duration
    ) external payable whenNotPaused returns (uint256 policyId) {
        require(bytes(eventType).length > 0, "Empty event type");
        require(msg.value > 0, "Zero premium");
        require(payout > 0, "Zero payout");
        require(duration > 0, "Zero duration");
        require(payout <= address(this).balance + msg.value, "Insufficient pool for payout");

        policyId = _nextPolicyId++;
        policies[policyId] = Policy({
            id: policyId,
            policyholder: msg.sender,
            eventType: eventType,
            threshold: threshold,
            premium: msg.value,
            payout: payout,
            duration: duration,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + duration,
            status: PolicyStatus.Active,
            oracleValue: 0,
            triggeredAt: 0
        });

        userPolicies[msg.sender].push(policyId);
        totalPremiums += msg.value;
        activePolicyCount++;

        emit PolicyCreated(policyId, msg.sender, eventType, threshold, msg.value, payout, duration);
    }

    /**
     * @notice Oracle triggers a policy when the threshold condition is met.
     * @param policyId  The policy to trigger.
     * @param oracleData The observed oracle value.
     */
    function triggerPolicy(
        uint256 policyId,
        uint256 oracleData
    ) external whenNotPaused {
        require(authorizedOracles[msg.sender], "Not an authorized oracle");

        Policy storage p = policies[policyId];
        require(p.id != 0, "Policy not found");
        require(p.status == PolicyStatus.Active, "Policy not active");
        require(block.timestamp <= p.expiresAt, "Policy expired");
        require(oracleData >= p.threshold, "Threshold not met");

        p.status = PolicyStatus.Triggered;
        p.oracleValue = oracleData;
        p.triggeredAt = block.timestamp;

        emit PolicyTriggered(policyId, oracleData, msg.sender);
    }

    /**
     * @notice Policyholder claims the payout after the policy has been triggered.
     * @param policyId The triggered policy.
     */
    function claimPayout(uint256 policyId) external nonReentrant whenNotPaused {
        Policy storage p = policies[policyId];
        require(p.id != 0, "Policy not found");
        require(p.status == PolicyStatus.Triggered, "Not triggered");
        require(msg.sender == p.policyholder, "Not policyholder");
        require(address(this).balance >= p.payout, "Insufficient funds");

        p.status = PolicyStatus.Claimed;
        activePolicyCount--;
        totalPayouts += p.payout;

        (bool success, ) = payable(p.policyholder).call{value: p.payout}("");
        require(success, "Payout transfer failed");

        emit PayoutClaimed(policyId, p.policyholder, p.payout);
    }

    /**
     * @notice Mark an expired policy (anyone can call to clean up).
     * @param policyId The policy to expire.
     */
    function expirePolicy(uint256 policyId) external {
        Policy storage p = policies[policyId];
        require(p.id != 0, "Policy not found");
        require(p.status == PolicyStatus.Active, "Not active");
        require(block.timestamp > p.expiresAt, "Not yet expired");

        p.status = PolicyStatus.Expired;
        activePolicyCount--;

        emit PolicyExpired(policyId);
    }

    // ---- Views -----------------------------------------------------------

    function getPolicy(uint256 policyId) external view returns (Policy memory) {
        require(policies[policyId].id != 0, "Not found");
        return policies[policyId];
    }

    function getUserPolicyIds(address user) external view returns (uint256[] memory) {
        return userPolicies[user];
    }

    function totalPolicies() external view returns (uint256) {
        return _nextPolicyId - 1;
    }

    function poolBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // ---- Funding ---------------------------------------------------------

    /// @notice Fund the insurance pool.
    receive() external payable {}

    /// @notice Owner withdraws surplus from pool.
    function withdrawSurplus(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Withdraw failed");
    }
}
