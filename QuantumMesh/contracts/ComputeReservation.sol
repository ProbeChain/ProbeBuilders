// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ComputeReservation
 * @author ProbeChain Rydberg Testnet
 * @notice Future compute capacity reservation marketplace
 * @dev Reserve, activate, cancel, and extend compute capacity reservations
 */

// ---------- Inlined Ownable ----------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: caller is not the owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner); _owner = newOwner;
    }
}

// ---------- Inlined ReentrancyGuard ----------
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

// ---------- Inlined Pausable ----------
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

contract ComputeReservation is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum ComputeType { CPU, GPU, TPU, FPGA, Quantum }
    enum ReservationStatus { Reserved, Active, Completed, Cancelled, Extended }

    // ---------- Structs ----------
    struct Reservation {
        uint256 id;
        address reserver;
        ComputeType computeType;
        uint256 amount;
        uint256 startDate;
        uint256 endDate;
        uint256 deposit;
        ReservationStatus status;
        uint256 createdAt;
        uint256 activatedAt;
        uint256 extensions;
    }

    struct Provider {
        address addr;
        uint256 totalCapacity;
        uint256 reservedCapacity;
        bool active;
        uint256 ratePerUnitPerDay;
    }

    // ---------- State ----------
    uint256 public nextReservationId;
    uint256 public nextProviderId;
    uint256 public cancellationPenaltyBPS;
    uint256 public protocolFeeBPS;

    mapping(uint256 => Reservation) public reservations;
    mapping(uint256 => Provider) public providers;
    mapping(address => uint256[]) public userReservations;
    mapping(ComputeType => uint256) public typeBaseRate;
    mapping(address => uint256) public providerEarnings;

    // ---------- Events ----------
    /// @notice Emitted when compute capacity is reserved
    event CapacityReserved(uint256 indexed reservationId, address indexed reserver, ComputeType computeType, uint256 amount, uint256 startDate, uint256 endDate);
    /// @notice Emitted when a reservation is activated
    event ReservationActivated(uint256 indexed reservationId, uint256 activatedAt);
    /// @notice Emitted when a reservation is cancelled
    event ReservationCancelled(uint256 indexed reservationId, uint256 refundAmount, uint256 penalty);
    /// @notice Emitted when a reservation is extended
    event ReservationExtended(uint256 indexed reservationId, uint256 newEndDate, uint256 additionalDeposit);
    /// @notice Emitted when a reservation completes
    event ReservationCompleted(uint256 indexed reservationId);
    /// @notice Emitted when a provider is registered
    event ProviderRegistered(uint256 indexed providerId, address indexed provider, uint256 capacity);
    /// @notice Emitted when a provider claims earnings
    event EarningsClaimed(address indexed provider, uint256 amount);

    // ---------- Constructor ----------
    constructor(uint256 _cancellationPenaltyBPS, uint256 _protocolFeeBPS)
        Ownable() ReentrancyGuard() Pausable()
    {
        require(_cancellationPenaltyBPS <= 5000, "Penalty too high");
        require(_protocolFeeBPS <= 500, "Fee too high");
        cancellationPenaltyBPS = _cancellationPenaltyBPS;
        protocolFeeBPS = _protocolFeeBPS;
        nextReservationId = 1;
        nextProviderId = 1;

        typeBaseRate[ComputeType.CPU] = 0.001 ether;
        typeBaseRate[ComputeType.GPU] = 0.01 ether;
        typeBaseRate[ComputeType.TPU] = 0.02 ether;
        typeBaseRate[ComputeType.FPGA] = 0.015 ether;
        typeBaseRate[ComputeType.Quantum] = 0.1 ether;
    }

    /**
     * @notice Register a compute provider
     * @param capacity Total capacity units offered
     * @param ratePerUnitPerDay Price per unit per day
     */
    function registerProvider(uint256 capacity, uint256 ratePerUnitPerDay) external whenNotPaused returns (uint256 providerId) {
        require(capacity > 0, "Zero capacity");
        require(ratePerUnitPerDay > 0, "Zero rate");

        providerId = nextProviderId++;
        providers[providerId] = Provider({
            addr: msg.sender,
            totalCapacity: capacity,
            reservedCapacity: 0,
            active: true,
            ratePerUnitPerDay: ratePerUnitPerDay
        });

        emit ProviderRegistered(providerId, msg.sender, capacity);
    }

    /**
     * @notice Reserve future compute capacity
     * @param computeType Type of compute resource
     * @param amount Number of units to reserve
     * @param startDate Reservation start timestamp
     * @param endDate Reservation end timestamp
     * @return reservationId The reservation identifier
     */
    function reserveCapacity(ComputeType computeType, uint256 amount, uint256 startDate, uint256 endDate)
        external
        payable
        whenNotPaused
        returns (uint256 reservationId)
    {
        require(amount > 0, "Zero amount");
        require(startDate >= block.timestamp, "Start in the past");
        require(endDate > startDate, "End must be after start");
        uint256 durationDays = (endDate - startDate) / 1 days;
        require(durationDays >= 1, "Min 1 day");
        require(durationDays <= 365, "Max 365 days");

        uint256 cost = typeBaseRate[computeType] * amount * durationDays;
        require(msg.value >= cost, "Insufficient payment");

        reservationId = nextReservationId++;
        Reservation storage r = reservations[reservationId];
        r.id = reservationId;
        r.reserver = msg.sender;
        r.computeType = computeType;
        r.amount = amount;
        r.startDate = startDate;
        r.endDate = endDate;
        r.deposit = msg.value;
        r.status = ReservationStatus.Reserved;
        r.createdAt = block.timestamp;

        userReservations[msg.sender].push(reservationId);
        emit CapacityReserved(reservationId, msg.sender, computeType, amount, startDate, endDate);
    }

    /**
     * @notice Activate a reservation when start date arrives
     * @param reservationId The reservation to activate
     */
    function activateReservation(uint256 reservationId) external whenNotPaused {
        Reservation storage r = reservations[reservationId];
        require(r.reserver == msg.sender || msg.sender == owner(), "Not authorized");
        require(r.status == ReservationStatus.Reserved || r.status == ReservationStatus.Extended, "Cannot activate");
        require(block.timestamp >= r.startDate, "Start date not reached");

        r.status = ReservationStatus.Active;
        r.activatedAt = block.timestamp;
        emit ReservationActivated(reservationId, block.timestamp);
    }

    /**
     * @notice Cancel a reservation and receive partial refund
     * @param reservationId The reservation to cancel
     */
    function cancelReservation(uint256 reservationId) external nonReentrant whenNotPaused {
        Reservation storage r = reservations[reservationId];
        require(r.reserver == msg.sender, "Not reserver");
        require(r.status == ReservationStatus.Reserved || r.status == ReservationStatus.Extended, "Cannot cancel");

        uint256 penalty = (r.deposit * cancellationPenaltyBPS) / 10000;
        uint256 refund = r.deposit - penalty;
        r.status = ReservationStatus.Cancelled;

        if (refund > 0) {
            (bool ok, ) = msg.sender.call{value: refund}("");
            require(ok, "Refund failed");
        }

        emit ReservationCancelled(reservationId, refund, penalty);
    }

    /**
     * @notice Extend an existing reservation
     * @param reservationId The reservation to extend
     * @param newEndDate The new end date (must be after current end date)
     */
    function extendReservation(uint256 reservationId, uint256 newEndDate)
        external
        payable
        whenNotPaused
    {
        Reservation storage r = reservations[reservationId];
        require(r.reserver == msg.sender, "Not reserver");
        require(r.status == ReservationStatus.Reserved || r.status == ReservationStatus.Active || r.status == ReservationStatus.Extended, "Cannot extend");
        require(newEndDate > r.endDate, "New end must be later");

        uint256 extraDays = (newEndDate - r.endDate) / 1 days;
        require(extraDays >= 1, "Min 1 day extension");
        uint256 extraCost = typeBaseRate[r.computeType] * r.amount * extraDays;
        require(msg.value >= extraCost, "Insufficient payment for extension");

        r.endDate = newEndDate;
        r.deposit += msg.value;
        r.extensions++;
        if (r.status == ReservationStatus.Reserved) {
            r.status = ReservationStatus.Extended;
        }

        emit ReservationExtended(reservationId, newEndDate, msg.value);
    }

    /**
     * @notice Mark a reservation as completed (owner only)
     * @param reservationId The reservation to complete
     */
    function completeReservation(uint256 reservationId) external onlyOwner {
        Reservation storage r = reservations[reservationId];
        require(r.status == ReservationStatus.Active, "Not active");
        require(block.timestamp >= r.endDate, "Not yet ended");
        r.status = ReservationStatus.Completed;
        emit ReservationCompleted(reservationId);
    }

    // ---------- View Functions ----------
    /**
     * @notice Get all reservations for a user
     * @param user The user address
     * @return Array of reservation IDs
     */
    function getUserReservations(address user) external view returns (uint256[] memory) {
        return userReservations[user];
    }

    /**
     * @notice Calculate cost for a reservation
     * @param computeType Type of compute
     * @param amount Units
     * @param durationDays Duration in days
     * @return cost Total cost in wei
     */
    function calculateCost(ComputeType computeType, uint256 amount, uint256 durationDays)
        external view returns (uint256 cost)
    {
        cost = typeBaseRate[computeType] * amount * durationDays;
    }

    /// @notice Set base rate for a compute type
    function setBaseRate(ComputeType computeType, uint256 rate) external onlyOwner {
        typeBaseRate[computeType] = rate;
    }

    /// @notice Withdraw protocol fees
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "No balance");
        (bool ok, ) = owner().call{value: bal}("");
        require(ok, "Withdraw failed");
    }
}
