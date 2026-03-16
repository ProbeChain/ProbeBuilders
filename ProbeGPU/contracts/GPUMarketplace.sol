// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GPUMarketplace
 * @author ProbeChain
 * @notice Decentralized GPU rental marketplace on ProbeChain Rydberg Testnet
 * @dev Register GPUs, rent by the hour, rate providers, claim earnings
 */
contract GPUMarketplace {
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
    struct GPU {
        address provider;
        string model;
        uint256 vramGB;
        uint256 computeScore;
        uint256 pricePerHour;
        bool available;
        uint256 totalRentals;
        uint256 totalRatingScore;
        uint256 ratingCount;
        uint256 registeredAt;
    }

    struct Rental {
        uint256 gpuId;
        address renter;
        uint256 hours;
        uint256 totalPaid;
        uint256 startedAt;
        uint256 endsAt;
        bool returned;
        bool rated;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => GPU) public gpus;
    mapping(uint256 => Rental) public rentals;
    mapping(address => uint256) public pendingEarnings;
    uint256 public nextGpuId;
    uint256 public nextRentalId;
    uint256 public platformFee = 300; // 3%
    uint256 public constant FEE_DENOMINATOR = 10000;

    // ─── Events ─────────────────────────────────────────────────────────
    event GPURegistered(uint256 indexed gpuId, address indexed provider, string model, uint256 vramGB);
    event GPURented(uint256 indexed rentalId, uint256 indexed gpuId, address indexed renter, uint256 hours);
    event GPUReturned(uint256 indexed rentalId, uint256 indexed gpuId);
    event ProviderRated(uint256 indexed gpuId, address indexed rater, uint256 score);
    event EarningsClaimed(address indexed provider, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register a GPU for rental
     * @param model GPU model name
     * @param vramGB VRAM in GB
     * @param computeScore Benchmark compute score
     * @param pricePerHour Price per hour in wei
     */
    function registerGPU(
        string calldata model,
        uint256 vramGB,
        uint256 computeScore,
        uint256 pricePerHour
    ) external whenNotPaused returns (uint256) {
        require(bytes(model).length > 0, "Empty model");
        require(vramGB > 0, "Zero VRAM");
        require(computeScore > 0, "Zero score");
        require(pricePerHour > 0, "Zero price");

        uint256 id = nextGpuId++;
        gpus[id] = GPU({
            provider: msg.sender,
            model: model,
            vramGB: vramGB,
            computeScore: computeScore,
            pricePerHour: pricePerHour,
            available: true,
            totalRentals: 0,
            totalRatingScore: 0,
            ratingCount: 0,
            registeredAt: block.timestamp
        });

        emit GPURegistered(id, msg.sender, model, vramGB);
        return id;
    }

    /**
     * @notice Rent a GPU
     * @param gpuId The GPU to rent
     * @param hours Number of hours
     */
    function rentGPU(uint256 gpuId, uint256 hours) external payable whenNotPaused nonReentrant returns (uint256) {
        GPU storage g = gpus[gpuId];
        require(g.available, "GPU not available");
        require(hours > 0, "Zero hours");

        uint256 cost = g.pricePerHour * hours;
        require(msg.value >= cost, "Insufficient payment");

        g.available = false;
        g.totalRentals++;

        uint256 fee = (cost * platformFee) / FEE_DENOMINATOR;
        pendingEarnings[_owner] += fee;
        pendingEarnings[g.provider] += cost - fee;

        uint256 rentalId = nextRentalId++;
        rentals[rentalId] = Rental({
            gpuId: gpuId,
            renter: msg.sender,
            hours: hours,
            totalPaid: cost,
            startedAt: block.timestamp,
            endsAt: block.timestamp + (hours * 1 hours),
            returned: false,
            rated: false
        });

        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit GPURented(rentalId, gpuId, msg.sender, hours);
        return rentalId;
    }

    /**
     * @notice Return a rented GPU
     * @param rentalId The rental to return
     */
    function returnGPU(uint256 rentalId) external whenNotPaused {
        Rental storage r = rentals[rentalId];
        require(!r.returned, "Already returned");
        require(msg.sender == r.renter || msg.sender == gpus[r.gpuId].provider || msg.sender == _owner, "Not authorized");

        r.returned = true;
        gpus[r.gpuId].available = true;
        emit GPUReturned(rentalId, r.gpuId);
    }

    /**
     * @notice Rate a GPU provider after rental
     * @param rentalId The rental to rate
     * @param score Rating score (1-5)
     */
    function rateProvider(uint256 rentalId, uint256 score) external whenNotPaused {
        Rental storage r = rentals[rentalId];
        require(msg.sender == r.renter, "Not renter");
        require(r.returned, "Not returned");
        require(!r.rated, "Already rated");
        require(score >= 1 && score <= 5, "Score 1-5");

        r.rated = true;
        GPU storage g = gpus[r.gpuId];
        g.totalRatingScore += score;
        g.ratingCount++;

        emit ProviderRated(r.gpuId, msg.sender, score);
    }

    /**
     * @notice Claim pending earnings
     */
    function claimEarnings() external nonReentrant {
        uint256 amount = pendingEarnings[msg.sender];
        require(amount > 0, "No earnings");
        pendingEarnings[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit EarningsClaimed(msg.sender, amount);
    }

    /**
     * @notice Get average rating for a GPU
     * @param gpuId The GPU to query
     */
    function getAverageRating(uint256 gpuId) external view returns (uint256 avgScore, uint256 count) {
        GPU storage g = gpus[gpuId];
        count = g.ratingCount;
        avgScore = count > 0 ? (g.totalRatingScore * 100) / count : 0; // scaled by 100
    }

    /**
     * @notice Update GPU availability
     */
    function setGPUAvailability(uint256 gpuId, bool available) external {
        require(msg.sender == gpus[gpuId].provider, "Not provider");
        gpus[gpuId].available = available;
    }
}
