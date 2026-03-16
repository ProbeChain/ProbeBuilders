// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title EnergyMarket
 * @author ProbeChain
 * @notice Peer-to-peer energy trading on ProbeChain Rydberg Testnet
 * @dev Producers list energy, consumers purchase, with generation/consumption tracking
 */
contract EnergyMarket {
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
    enum EnergyType { Solar, Wind, Hydro, Biomass, Geothermal }

    struct Producer {
        address producerAddr;
        EnergyType energyType;
        uint256 capacityKwh;
        uint256 totalGenerated;
        bool active;
        uint256 registeredAt;
    }

    struct Listing {
        uint256 producerId;
        uint256 amountKwh;
        uint256 pricePerKwh;
        uint256 remainingKwh;
        bool active;
        uint256 createdAt;
    }

    struct Purchase {
        uint256 listingId;
        address buyer;
        uint256 amountKwh;
        uint256 totalPaid;
        uint256 purchasedAt;
    }

    struct ConsumptionReport {
        address consumer;
        uint256 amountKwh;
        uint256 timestamp;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => Producer) public producers;
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Purchase) public purchases;
    mapping(address => uint256) public pendingWithdrawals;
    ConsumptionReport[] public consumptionReports;

    uint256 public nextProducerId;
    uint256 public nextListingId;
    uint256 public nextPurchaseId;
    uint256 public platformFee = 200; // 2%
    uint256 public constant FEE_DENOMINATOR = 10000;

    // ─── Events ─────────────────────────────────────────────────────────
    event ProducerRegistered(uint256 indexed producerId, address indexed producer, EnergyType energyType);
    event EnergyListed(uint256 indexed listingId, uint256 indexed producerId, uint256 amountKwh, uint256 pricePerKwh);
    event EnergyPurchased(uint256 indexed purchaseId, uint256 indexed listingId, address indexed buyer, uint256 amountKwh);
    event GenerationReported(uint256 indexed producerId, uint256 amountKwh);
    event ConsumptionReported(address indexed consumer, uint256 amountKwh);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register as an energy producer
     * @param energyType Type of energy produced
     * @param capacityKwh Maximum generation capacity in kWh
     */
    function registerProducer(EnergyType energyType, uint256 capacityKwh) external whenNotPaused returns (uint256) {
        require(capacityKwh > 0, "Zero capacity");

        uint256 id = nextProducerId++;
        producers[id] = Producer({
            producerAddr: msg.sender,
            energyType: energyType,
            capacityKwh: capacityKwh,
            totalGenerated: 0,
            active: true,
            registeredAt: block.timestamp
        });

        emit ProducerRegistered(id, msg.sender, energyType);
        return id;
    }

    /**
     * @notice List energy for sale
     * @param producerId The producer's ID
     * @param amountKwh Amount in kWh to sell
     * @param pricePerKwh Price per kWh in wei
     */
    function listEnergy(uint256 producerId, uint256 amountKwh, uint256 pricePerKwh) external whenNotPaused returns (uint256) {
        Producer storage p = producers[producerId];
        require(msg.sender == p.producerAddr, "Not producer");
        require(p.active, "Producer not active");
        require(amountKwh > 0 && pricePerKwh > 0, "Zero values");

        uint256 id = nextListingId++;
        listings[id] = Listing({
            producerId: producerId,
            amountKwh: amountKwh,
            pricePerKwh: pricePerKwh,
            remainingKwh: amountKwh,
            active: true,
            createdAt: block.timestamp
        });

        emit EnergyListed(id, producerId, amountKwh, pricePerKwh);
        return id;
    }

    /**
     * @notice Purchase energy from a listing
     * @param listingId The listing to purchase from
     * @param amountKwh Amount in kWh to buy
     */
    function purchaseEnergy(uint256 listingId, uint256 amountKwh) external payable whenNotPaused nonReentrant returns (uint256) {
        Listing storage l = listings[listingId];
        require(l.active, "Listing not active");
        require(amountKwh > 0 && amountKwh <= l.remainingKwh, "Invalid amount");

        uint256 cost = l.pricePerKwh * amountKwh;
        require(msg.value >= cost, "Insufficient payment");

        l.remainingKwh -= amountKwh;
        if (l.remainingKwh == 0) l.active = false;

        uint256 fee = (cost * platformFee) / FEE_DENOMINATOR;
        Producer storage p = producers[l.producerId];
        pendingWithdrawals[_owner] += fee;
        pendingWithdrawals[p.producerAddr] += cost - fee;

        uint256 purchaseId = nextPurchaseId++;
        purchases[purchaseId] = Purchase({
            listingId: listingId,
            buyer: msg.sender,
            amountKwh: amountKwh,
            totalPaid: cost,
            purchasedAt: block.timestamp
        });

        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit EnergyPurchased(purchaseId, listingId, msg.sender, amountKwh);
        return purchaseId;
    }

    /**
     * @notice Report energy generation
     * @param producerId The producer reporting
     * @param amountKwh Amount generated in kWh
     */
    function reportGeneration(uint256 producerId, uint256 amountKwh) external whenNotPaused {
        Producer storage p = producers[producerId];
        require(msg.sender == p.producerAddr, "Not producer");
        require(p.active, "Producer not active");
        p.totalGenerated += amountKwh;
        emit GenerationReported(producerId, amountKwh);
    }

    /**
     * @notice Report energy consumption
     * @param amountKwh Amount consumed in kWh
     */
    function reportConsumption(uint256 amountKwh) external whenNotPaused {
        require(amountKwh > 0, "Zero amount");
        consumptionReports.push(ConsumptionReport({
            consumer: msg.sender,
            amountKwh: amountKwh,
            timestamp: block.timestamp
        }));
        emit ConsumptionReported(msg.sender, amountKwh);
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
}
