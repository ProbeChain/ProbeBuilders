// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title InsurancePool
 * @author ProbeBuilders
 * @notice DeFi insurance protocol for ProbeChain Rydberg Testnet.
 * @dev Supports policy creation, premium payments, claims, and oracle/agent-based resolution.
 */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
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

contract InsurancePool is Ownable, ReentrancyGuard, Pausable {
    // ---- Types ----
    enum PolicyStatus { Active, Claimed, Resolved, Expired, Cancelled }
    enum ClaimVerdict { Pending, Approved, Denied }

    struct PolicyType {
        uint256 id;
        string name;            // e.g., "Smart Contract Hack", "Stablecoin Depeg"
        uint256 premiumBps;     // annual premium in basis points of coverage
        uint256 maxCoverage;    // max coverage per policy
        uint256 minDuration;    // minimum coverage duration in seconds
        uint256 maxDuration;    // maximum coverage duration in seconds
        bool isActive;
    }

    struct Policy {
        uint256 id;
        uint256 policyTypeId;
        address holder;
        address paymentToken;
        uint256 coverageAmount;
        uint256 premiumPaid;
        uint256 startTime;
        uint256 endTime;
        PolicyStatus status;
    }

    struct Claim {
        uint256 id;
        uint256 policyId;
        address claimant;
        uint256 claimAmount;
        string evidence;        // IPFS hash or description
        uint256 filedAt;
        ClaimVerdict verdict;
        address resolvedBy;
    }

    // ---- State ----
    mapping(uint256 => PolicyType) public policyTypes;
    uint256 public nextPolicyTypeId;

    mapping(uint256 => Policy) public policies;
    uint256 public nextPolicyId;

    mapping(uint256 => Claim) public claims;
    uint256 public nextClaimId;

    /// @notice Designated oracles/agents who can resolve claims
    mapping(address => bool) public isResolver;

    /// @notice Underwriter deposits per token
    mapping(address => uint256) public poolBalance; // token => total pool
    mapping(address => mapping(address => uint256)) public underwriterDeposits; // token => underwriter => amount

    uint256 public totalActiveCoverage;

    // ---- Events ----
    event PolicyTypeCreated(uint256 indexed typeId, string name);
    event PolicyCreated(uint256 indexed policyId, address indexed holder, uint256 coverage, uint256 premium);
    event PremiumPaid(uint256 indexed policyId, uint256 amount);
    event ClaimFiled(uint256 indexed claimId, uint256 indexed policyId, uint256 amount);
    event ClaimResolved(uint256 indexed claimId, ClaimVerdict verdict, address resolver);
    event PolicyExpired(uint256 indexed policyId);
    event UnderwriterDeposited(address indexed underwriter, address indexed token, uint256 amount);
    event UnderwriterWithdrawn(address indexed underwriter, address indexed token, uint256 amount);
    event ResolverUpdated(address indexed resolver, bool status);

    // ---- Admin ----

    function addPolicyType(
        string calldata name_,
        uint256 premiumBps_,
        uint256 maxCoverage_,
        uint256 minDuration_,
        uint256 maxDuration_
    ) external onlyOwner returns (uint256 typeId) {
        typeId = nextPolicyTypeId++;
        policyTypes[typeId] = PolicyType({
            id: typeId,
            name: name_,
            premiumBps: premiumBps_,
            maxCoverage: maxCoverage_,
            minDuration: minDuration_,
            maxDuration: maxDuration_,
            isActive: true
        });
        emit PolicyTypeCreated(typeId, name_);
    }

    function setResolver(address resolver, bool status) external onlyOwner {
        isResolver[resolver] = status;
        emit ResolverUpdated(resolver, status);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ---- Underwriter Functions ----

    /// @notice Deposit funds into the insurance pool
    function depositToPool(address token, uint256 amount) external nonReentrant {
        require(amount > 0, "Insurance: zero amount");
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        poolBalance[token] += amount;
        underwriterDeposits[token][msg.sender] += amount;
        emit UnderwriterDeposited(msg.sender, token, amount);
    }

    /// @notice Withdraw from the insurance pool (if sufficient free capital)
    function withdrawFromPool(address token, uint256 amount) external nonReentrant {
        require(underwriterDeposits[token][msg.sender] >= amount, "Insurance: insufficient deposit");
        // Ensure pool remains solvent
        require(poolBalance[token] - amount >= totalActiveCoverage, "Insurance: would make pool insolvent");
        underwriterDeposits[token][msg.sender] -= amount;
        poolBalance[token] -= amount;
        IERC20(token).transfer(msg.sender, amount);
        emit UnderwriterWithdrawn(msg.sender, token, amount);
    }

    // ---- Policy Lifecycle ----

    /// @notice Create and pay for an insurance policy
    function createPolicy(
        uint256 policyTypeId,
        address paymentToken,
        uint256 coverageAmount,
        uint256 duration
    ) external nonReentrant whenNotPaused returns (uint256 policyId) {
        PolicyType storage pt = policyTypes[policyTypeId];
        require(pt.isActive, "Insurance: type inactive");
        require(coverageAmount > 0 && coverageAmount <= pt.maxCoverage, "Insurance: invalid coverage");
        require(duration >= pt.minDuration && duration <= pt.maxDuration, "Insurance: invalid duration");

        // Calculate premium
        uint256 annualPremium = (coverageAmount * pt.premiumBps) / 10000;
        uint256 premium = (annualPremium * duration) / 365 days;
        require(premium > 0, "Insurance: zero premium");

        // Ensure pool can cover
        require(poolBalance[paymentToken] >= coverageAmount, "Insurance: insufficient pool");

        // Collect premium
        IERC20(paymentToken).transferFrom(msg.sender, address(this), premium);
        poolBalance[paymentToken] += premium;

        policyId = nextPolicyId++;
        policies[policyId] = Policy({
            id: policyId,
            policyTypeId: policyTypeId,
            holder: msg.sender,
            paymentToken: paymentToken,
            coverageAmount: coverageAmount,
            premiumPaid: premium,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            status: PolicyStatus.Active
        });

        totalActiveCoverage += coverageAmount;
        emit PolicyCreated(policyId, msg.sender, coverageAmount, premium);
        emit PremiumPaid(policyId, premium);
    }

    /// @notice File a claim against an active policy
    function claimPolicy(uint256 policyId, uint256 claimAmount, string calldata evidence) external nonReentrant returns (uint256 claimId) {
        Policy storage pol = policies[policyId];
        require(pol.holder == msg.sender, "Insurance: not holder");
        require(pol.status == PolicyStatus.Active, "Insurance: not active");
        require(block.timestamp <= pol.endTime, "Insurance: expired");
        require(claimAmount > 0 && claimAmount <= pol.coverageAmount, "Insurance: invalid claim amount");

        pol.status = PolicyStatus.Claimed;

        claimId = nextClaimId++;
        claims[claimId] = Claim({
            id: claimId,
            policyId: policyId,
            claimant: msg.sender,
            claimAmount: claimAmount,
            evidence: evidence,
            filedAt: block.timestamp,
            verdict: ClaimVerdict.Pending,
            resolvedBy: address(0)
        });

        emit ClaimFiled(claimId, policyId, claimAmount);
    }

    /// @notice Resolve a claim (designated oracle/agent only)
    function resolveClaim(uint256 claimId, ClaimVerdict verdict) external nonReentrant {
        require(isResolver[msg.sender], "Insurance: not a resolver");
        Claim storage c = claims[claimId];
        require(c.verdict == ClaimVerdict.Pending, "Insurance: already resolved");

        c.verdict = verdict;
        c.resolvedBy = msg.sender;

        Policy storage pol = policies[c.policyId];

        if (verdict == ClaimVerdict.Approved) {
            pol.status = PolicyStatus.Resolved;
            totalActiveCoverage -= pol.coverageAmount;
            // Pay out claim
            require(poolBalance[pol.paymentToken] >= c.claimAmount, "Insurance: insufficient pool");
            poolBalance[pol.paymentToken] -= c.claimAmount;
            IERC20(pol.paymentToken).transfer(c.claimant, c.claimAmount);
        } else {
            pol.status = PolicyStatus.Active; // reactivate
        }

        emit ClaimResolved(claimId, verdict, msg.sender);
    }

    /// @notice Mark expired policies
    function expirePolicy(uint256 policyId) external {
        Policy storage pol = policies[policyId];
        require(pol.status == PolicyStatus.Active, "Insurance: not active");
        require(block.timestamp > pol.endTime, "Insurance: not expired yet");
        pol.status = PolicyStatus.Expired;
        totalActiveCoverage -= pol.coverageAmount;
        emit PolicyExpired(policyId);
    }
}
