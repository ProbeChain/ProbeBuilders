// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SensorMarket
 * @author ProbeChain
 * @notice Decentralized sensor data marketplace on ProbeChain Rydberg Testnet
 * @dev Enables sensor registration, subscription, and data push with payments
 */
contract SensorMarket {
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
    struct Sensor {
        address sensorOwner;
        string location;
        string dataType;
        uint256 pricePerDay;
        bool active;
        uint256 readingCount;
        uint256 registeredAt;
    }

    struct Subscription {
        address subscriber;
        uint256 sensorId;
        uint256 expiresAt;
        uint256 paidAmount;
    }

    struct Reading {
        int256 value;
        uint256 timestamp;
        uint256 blockNumber;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => Sensor) public sensors;
    mapping(uint256 => Reading[]) private _readings;
    mapping(uint256 => Subscription) public subscriptions;
    mapping(address => uint256) public pendingWithdrawals;

    uint256 public nextSensorId;
    uint256 public nextSubId;
    uint256 public platformFee = 250; // 2.5% in basis points
    uint256 public constant FEE_DENOMINATOR = 10000;

    // ─── Events ─────────────────────────────────────────────────────────
    event SensorRegistered(uint256 indexed sensorId, address indexed sensorOwner, string dataType);
    event SensorSubscribed(uint256 indexed subId, uint256 indexed sensorId, address indexed subscriber, uint256 expiresAt);
    event ReadingPushed(uint256 indexed sensorId, int256 value, uint256 timestamp);
    event Withdrawn(address indexed to, uint256 amount);
    event FeeUpdated(uint256 newFee);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register a new sensor
     * @param location Human-readable location or geo-hash
     * @param dataType Type of data (temperature, humidity, etc.)
     * @param pricePerDay Price per day in wei for subscriptions
     */
    function registerSensor(
        string calldata location,
        string calldata dataType,
        uint256 pricePerDay
    ) external whenNotPaused returns (uint256) {
        require(bytes(location).length > 0, "Empty location");
        require(bytes(dataType).length > 0, "Empty dataType");
        require(pricePerDay > 0, "Zero price");

        uint256 sensorId = nextSensorId++;
        sensors[sensorId] = Sensor({
            sensorOwner: msg.sender,
            location: location,
            dataType: dataType,
            pricePerDay: pricePerDay,
            active: true,
            readingCount: 0,
            registeredAt: block.timestamp
        });

        emit SensorRegistered(sensorId, msg.sender, dataType);
        return sensorId;
    }

    /**
     * @notice Subscribe to a sensor's data feed
     * @param sensorId The sensor to subscribe to
     * @param durationDays Number of days to subscribe
     */
    function subscribeSensor(
        uint256 sensorId,
        uint256 durationDays
    ) external payable whenNotPaused nonReentrant returns (uint256) {
        Sensor storage s = sensors[sensorId];
        require(s.active, "Sensor not active");
        require(durationDays > 0, "Zero duration");

        uint256 cost = s.pricePerDay * durationDays;
        require(msg.value >= cost, "Insufficient payment");

        uint256 fee = (cost * platformFee) / FEE_DENOMINATOR;
        pendingWithdrawals[_owner] += fee;
        pendingWithdrawals[s.sensorOwner] += cost - fee;

        uint256 subId = nextSubId++;
        subscriptions[subId] = Subscription({
            subscriber: msg.sender,
            sensorId: sensorId,
            expiresAt: block.timestamp + (durationDays * 1 days),
            paidAmount: cost
        });

        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit SensorSubscribed(subId, sensorId, msg.sender, subscriptions[subId].expiresAt);
        return subId;
    }

    /**
     * @notice Push a sensor reading on-chain
     * @param sensorId The sensor providing the reading
     * @param value The sensor value (signed integer for flexibility)
     * @param timestamp Off-chain timestamp of the reading
     */
    function pushReading(
        uint256 sensorId,
        int256 value,
        uint256 timestamp
    ) external whenNotPaused {
        Sensor storage s = sensors[sensorId];
        require(s.active, "Sensor not active");
        require(msg.sender == s.sensorOwner, "Not sensor owner");
        require(timestamp <= block.timestamp, "Future timestamp");

        _readings[sensorId].push(Reading({
            value: value,
            timestamp: timestamp,
            blockNumber: block.number
        }));
        s.readingCount++;

        emit ReadingPushed(sensorId, value, timestamp);
    }

    /**
     * @notice Get paginated readings for a sensor
     * @param sensorId The sensor to query
     * @param offset Starting index
     * @param limit Max records
     */
    function getReadings(
        uint256 sensorId,
        uint256 offset,
        uint256 limit
    ) external view returns (Reading[] memory) {
        Reading[] storage readings = _readings[sensorId];
        if (offset >= readings.length) return new Reading[](0);
        uint256 end = offset + limit > readings.length ? readings.length : offset + limit;
        Reading[] memory result = new Reading[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = readings[i];
        }
        return result;
    }

    /**
     * @notice Withdraw pending earnings
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Deactivate a sensor
     * @param sensorId The sensor to deactivate
     */
    function deactivateSensor(uint256 sensorId) external {
        require(msg.sender == sensors[sensorId].sensorOwner || msg.sender == _owner, "Not authorized");
        sensors[sensorId].active = false;
    }

    /**
     * @notice Update platform fee (owner only)
     * @param newFee New fee in basis points (max 1000 = 10%)
     */
    function setFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high");
        platformFee = newFee;
        emit FeeUpdated(newFee);
    }
}
