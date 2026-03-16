// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ComputeExchange
 * @author ProbeChain
 * @notice Decentralized compute resource exchange on ProbeChain Rydberg Testnet
 * @dev List compute resources, bid/purchase, manage sessions, settle payments
 */
contract ComputeExchange {
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

    // ─── Enums & Structs ────────────────────────────────────────────────
    enum OrderStatus { Created, Active, Completed, Cancelled }

    struct ComputeListing {
        address provider;
        uint256 cpuCores;
        uint256 ramGB;
        uint256 gpuCount;
        uint256 pricePerHour;
        bool available;
        uint256 totalSessions;
        uint256 registeredAt;
    }

    struct ComputeOrder {
        uint256 listingId;
        address buyer;
        uint256 hours;
        uint256 deposited;
        uint256 startedAt;
        uint256 endedAt;
        OrderStatus status;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => ComputeListing) public listings;
    mapping(uint256 => ComputeOrder) public orders;
    mapping(address => uint256) public pendingWithdrawals;
    uint256 public nextListingId;
    uint256 public nextOrderId;
    uint256 public platformFee = 250; // 2.5%
    uint256 public constant FEE_DENOMINATOR = 10000;

    // ─── Events ─────────────────────────────────────────────────────────
    event ComputeListed(uint256 indexed listingId, address indexed provider, uint256 cpuCores, uint256 ramGB, uint256 gpuCount);
    event ComputeBid(uint256 indexed orderId, uint256 indexed listingId, address indexed buyer, uint256 hours);
    event SessionStarted(uint256 indexed orderId);
    event SessionEnded(uint256 indexed orderId, uint256 duration);
    event PaymentSettled(uint256 indexed orderId, uint256 providerPaid, uint256 refunded);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice List compute resources for sale
     * @param cpuCores Number of CPU cores
     * @param ramGB RAM in GB
     * @param gpuCount Number of GPUs
     * @param pricePerHour Price per hour in wei
     */
    function listCompute(
        uint256 cpuCores,
        uint256 ramGB,
        uint256 gpuCount,
        uint256 pricePerHour
    ) external whenNotPaused returns (uint256) {
        require(cpuCores > 0 || gpuCount > 0, "Need CPU or GPU");
        require(ramGB > 0, "Zero RAM");
        require(pricePerHour > 0, "Zero price");

        uint256 id = nextListingId++;
        listings[id] = ComputeListing({
            provider: msg.sender,
            cpuCores: cpuCores,
            ramGB: ramGB,
            gpuCount: gpuCount,
            pricePerHour: pricePerHour,
            available: true,
            totalSessions: 0,
            registeredAt: block.timestamp
        });

        emit ComputeListed(id, msg.sender, cpuCores, ramGB, gpuCount);
        return id;
    }

    /**
     * @notice Bid on compute resources
     * @param listingId The listing to purchase
     * @param hours Number of hours to reserve
     */
    function bidOnCompute(
        uint256 listingId,
        uint256 hours
    ) external payable whenNotPaused nonReentrant returns (uint256) {
        ComputeListing storage l = listings[listingId];
        require(l.available, "Not available");
        require(hours > 0, "Zero hours");

        uint256 cost = l.pricePerHour * hours;
        require(msg.value >= cost, "Insufficient payment");

        l.available = false;
        l.totalSessions++;

        uint256 orderId = nextOrderId++;
        orders[orderId] = ComputeOrder({
            listingId: listingId,
            buyer: msg.sender,
            hours: hours,
            deposited: cost,
            startedAt: 0,
            endedAt: 0,
            status: OrderStatus.Created
        });

        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit ComputeBid(orderId, listingId, msg.sender, hours);
        return orderId;
    }

    /**
     * @notice Start a compute session
     * @param orderId The order to start
     */
    function startSession(uint256 orderId) external whenNotPaused {
        ComputeOrder storage o = orders[orderId];
        require(o.status == OrderStatus.Created, "Not created");
        ComputeListing storage l = listings[o.listingId];
        require(msg.sender == l.provider, "Not provider");

        o.status = OrderStatus.Active;
        o.startedAt = block.timestamp;
        emit SessionStarted(orderId);
    }

    /**
     * @notice End a compute session
     * @param orderId The order to end
     */
    function endSession(uint256 orderId) external whenNotPaused {
        ComputeOrder storage o = orders[orderId];
        require(o.status == OrderStatus.Active, "Not active");
        require(
            msg.sender == o.buyer ||
            msg.sender == listings[o.listingId].provider ||
            msg.sender == _owner,
            "Not authorized"
        );

        o.status = OrderStatus.Completed;
        o.endedAt = block.timestamp;
        listings[o.listingId].available = true;

        uint256 duration = o.endedAt - o.startedAt;
        emit SessionEnded(orderId, duration);
    }

    /**
     * @notice Settle payment for a completed session
     * @param orderId The completed order
     */
    function settlePayment(uint256 orderId) external whenNotPaused nonReentrant {
        ComputeOrder storage o = orders[orderId];
        require(o.status == OrderStatus.Completed, "Not completed");

        ComputeListing storage l = listings[o.listingId];
        uint256 actualHours = (o.endedAt - o.startedAt) / 1 hours;
        if ((o.endedAt - o.startedAt) % 1 hours > 0) actualHours++; // round up

        uint256 actualCost = l.pricePerHour * actualHours;
        if (actualCost > o.deposited) actualCost = o.deposited;

        uint256 fee = (actualCost * platformFee) / FEE_DENOMINATOR;
        pendingWithdrawals[_owner] += fee;
        pendingWithdrawals[l.provider] += actualCost - fee;

        uint256 refund = o.deposited - actualCost;
        if (refund > 0) {
            pendingWithdrawals[o.buyer] += refund;
        }

        emit PaymentSettled(orderId, actualCost - fee, refund);
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
     * @notice Cancel an order before it starts
     */
    function cancelOrder(uint256 orderId) external nonReentrant {
        ComputeOrder storage o = orders[orderId];
        require(o.status == OrderStatus.Created, "Not cancellable");
        require(msg.sender == o.buyer, "Not buyer");

        o.status = OrderStatus.Cancelled;
        listings[o.listingId].available = true;
        payable(msg.sender).transfer(o.deposited);
    }
}
