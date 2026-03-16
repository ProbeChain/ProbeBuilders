// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title BandwidthExchange
 * @author ProbeChain
 * @notice Decentralized bandwidth sharing marketplace on ProbeChain Rydberg Testnet
 * @dev Providers share bandwidth, buyers purchase sessions, usage tracked on-chain
 */
contract BandwidthExchange {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() { require(msg.sender == _owner, "Not owner"); _; }
    event OwnershipTransferred(address indexed prev, address indexed next_);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _locked = 1;
    modifier nonReentrant() { require(_locked == 1, "Reentrant"); _locked = 2; _; _locked = 1; }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "Paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Structs ────────────────────────────────────────────────────────
    struct Provider {
        address providerAddr;
        uint256 bandwidthMbps;
        uint256 pricePerGB;
        uint256 totalServed;
        bool active;
        uint256 registeredAt;
    }

    struct Session {
        uint256 providerId;
        address buyer;
        uint256 purchasedGB;
        uint256 usedBytes;
        uint256 deposited;
        uint256 startedAt;
        bool settled;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => Provider) public providers;
    mapping(uint256 => Session) public sessions;
    mapping(address => uint256) public pendingWithdrawals;
    uint256 public nextProviderId;
    uint256 public nextSessionId;
    uint256 public platformFee = 300; // 3%
    uint256 public constant FEE_DENOMINATOR = 10000;

    // ─── Events ─────────────────────────────────────────────────────────
    event ProviderRegistered(uint256 indexed providerId, address indexed provider, uint256 bandwidthMbps);
    event BandwidthPurchased(uint256 indexed sessionId, uint256 indexed providerId, address indexed buyer, uint256 amountGB);
    event UsageReported(uint256 indexed sessionId, uint256 bytesUsed);
    event SessionSettled(uint256 indexed sessionId, uint256 paidAmount, uint256 refunded);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register as a bandwidth provider
     * @param bandwidthMbps Available bandwidth in Mbps
     * @param pricePerGB Price per GB in wei
     */
    function registerProvider(uint256 bandwidthMbps, uint256 pricePerGB) external whenNotPaused returns (uint256) {
        require(bandwidthMbps > 0, "Zero bandwidth");
        require(pricePerGB > 0, "Zero price");

        uint256 id = nextProviderId++;
        providers[id] = Provider({
            providerAddr: msg.sender,
            bandwidthMbps: bandwidthMbps,
            pricePerGB: pricePerGB,
            totalServed: 0,
            active: true,
            registeredAt: block.timestamp
        });

        emit ProviderRegistered(id, msg.sender, bandwidthMbps);
        return id;
    }

    /**
     * @notice Purchase bandwidth from a provider
     * @param providerId The provider to purchase from
     * @param amountGB Amount of data in GB to purchase
     */
    function purchaseBandwidth(
        uint256 providerId,
        uint256 amountGB
    ) external payable whenNotPaused nonReentrant returns (uint256) {
        Provider storage p = providers[providerId];
        require(p.active, "Provider not active");
        require(amountGB > 0, "Zero amount");

        uint256 cost = p.pricePerGB * amountGB;
        require(msg.value >= cost, "Insufficient payment");

        uint256 sessionId = nextSessionId++;
        sessions[sessionId] = Session({
            providerId: providerId,
            buyer: msg.sender,
            purchasedGB: amountGB,
            usedBytes: 0,
            deposited: cost,
            startedAt: block.timestamp,
            settled: false
        });

        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit BandwidthPurchased(sessionId, providerId, msg.sender, amountGB);
        return sessionId;
    }

    /**
     * @notice Report bandwidth usage for a session
     * @param sessionId The session to report usage for
     * @param bytesUsed Total bytes used so far
     */
    function reportUsage(uint256 sessionId, uint256 bytesUsed) external whenNotPaused {
        Session storage s = sessions[sessionId];
        require(!s.settled, "Already settled");
        Provider storage p = providers[s.providerId];
        require(msg.sender == p.providerAddr || msg.sender == s.buyer, "Not authorized");
        require(bytesUsed >= s.usedBytes, "Cannot decrease usage");

        s.usedBytes = bytesUsed;
        emit UsageReported(sessionId, bytesUsed);
    }

    /**
     * @notice Settle a session and distribute payment
     * @param sessionId The session to settle
     */
    function settleSession(uint256 sessionId) external whenNotPaused nonReentrant {
        Session storage s = sessions[sessionId];
        require(!s.settled, "Already settled");
        require(msg.sender == s.buyer || msg.sender == providers[s.providerId].providerAddr || msg.sender == _owner, "Not authorized");

        s.settled = true;
        Provider storage p = providers[s.providerId];

        uint256 usedGB = s.usedBytes / (1024 * 1024 * 1024);
        if (s.usedBytes % (1024 * 1024 * 1024) > 0) usedGB++; // round up

        uint256 actualCost = usedGB > s.purchasedGB ? s.deposited : (p.pricePerGB * usedGB);
        if (actualCost > s.deposited) actualCost = s.deposited;

        uint256 fee = (actualCost * platformFee) / FEE_DENOMINATOR;
        pendingWithdrawals[_owner] += fee;
        pendingWithdrawals[p.providerAddr] += actualCost - fee;

        uint256 refund = s.deposited - actualCost;
        if (refund > 0) {
            pendingWithdrawals[s.buyer] += refund;
        }

        p.totalServed += s.usedBytes;
        emit SessionSettled(sessionId, actualCost, refund);
    }

    /**
     * @notice Withdraw pending balance
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Deactivate provider listing
     * @param providerId The provider to deactivate
     */
    function deactivateProvider(uint256 providerId) external {
        require(msg.sender == providers[providerId].providerAddr || msg.sender == _owner, "Not authorized");
        providers[providerId].active = false;
    }

    /**
     * @notice Update platform fee
     * @param newFee Fee in basis points (max 1000)
     */
    function setFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high");
        platformFee = newFee;
    }
}
