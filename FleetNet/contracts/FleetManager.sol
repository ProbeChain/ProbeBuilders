// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title FleetManager
 * @author ProbeChain
 * @notice Vehicle fleet telemetry and management on ProbeChain Rydberg Testnet
 * @dev Register vehicles, report telemetry, set alerts, query history
 */
contract FleetManager {
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

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "Paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums & Structs ────────────────────────────────────────────────
    enum VehicleType { Car, Truck, Van, Bus, Motorcycle }
    enum AlertType { Speed, Fuel, Maintenance, Geofence }

    struct Vehicle {
        bytes32 vin;
        VehicleType vehicleType;
        address fleetOwner;
        bool active;
        uint256 telemetryCount;
        uint256 registeredAt;
    }

    struct TelemetryData {
        uint256 speed;
        bytes32 locationHash;
        uint256 fuelLevel;
        uint256 timestamp;
    }

    struct Alert {
        AlertType alertType;
        uint256 threshold;
        bool active;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => Vehicle) public vehicles;
    mapping(uint256 => TelemetryData[]) private _telemetry;
    mapping(uint256 => mapping(AlertType => Alert)) public alerts;
    mapping(address => uint256[]) public fleetVehicles;
    uint256 public nextVehicleId;

    // ─── Events ─────────────────────────────────────────────────────────
    event VehicleRegistered(uint256 indexed vehicleId, bytes32 indexed vin, VehicleType vehicleType, address indexed fleetOwner);
    event TelemetryReported(uint256 indexed vehicleId, uint256 speed, uint256 fuelLevel, uint256 timestamp);
    event AlertTriggered(uint256 indexed vehicleId, AlertType alertType, uint256 value, uint256 threshold);
    event AlertSet(uint256 indexed vehicleId, AlertType alertType, uint256 threshold);
    event VehicleDeactivated(uint256 indexed vehicleId);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register a vehicle in the fleet
     * @param vin Vehicle identification number hash
     * @param vehicleType Type of vehicle
     */
    function registerVehicle(bytes32 vin, VehicleType vehicleType) external whenNotPaused returns (uint256) {
        require(vin != bytes32(0), "Empty VIN");

        uint256 id = nextVehicleId++;
        vehicles[id] = Vehicle({
            vin: vin,
            vehicleType: vehicleType,
            fleetOwner: msg.sender,
            active: true,
            telemetryCount: 0,
            registeredAt: block.timestamp
        });

        fleetVehicles[msg.sender].push(id);
        emit VehicleRegistered(id, vin, vehicleType, msg.sender);
        return id;
    }

    /**
     * @notice Report vehicle telemetry data
     * @param vehicleId The vehicle reporting telemetry
     * @param speed Current speed
     * @param locationHash Hash of GPS coordinates
     * @param fuelLevel Fuel level percentage (0-100)
     * @param timestamp Off-chain timestamp of the reading
     */
    function reportTelemetry(
        uint256 vehicleId,
        uint256 speed,
        bytes32 locationHash,
        uint256 fuelLevel,
        uint256 timestamp
    ) external whenNotPaused {
        Vehicle storage v = vehicles[vehicleId];
        require(v.active, "Vehicle not active");
        require(msg.sender == v.fleetOwner, "Not fleet owner");
        require(fuelLevel <= 100, "Invalid fuel level");
        require(timestamp <= block.timestamp, "Future timestamp");

        _telemetry[vehicleId].push(TelemetryData({
            speed: speed,
            locationHash: locationHash,
            fuelLevel: fuelLevel,
            timestamp: timestamp
        }));
        v.telemetryCount++;

        emit TelemetryReported(vehicleId, speed, fuelLevel, timestamp);

        // Check speed alert
        Alert storage speedAlert = alerts[vehicleId][AlertType.Speed];
        if (speedAlert.active && speed > speedAlert.threshold) {
            emit AlertTriggered(vehicleId, AlertType.Speed, speed, speedAlert.threshold);
        }

        // Check fuel alert
        Alert storage fuelAlert = alerts[vehicleId][AlertType.Fuel];
        if (fuelAlert.active && fuelLevel < fuelAlert.threshold) {
            emit AlertTriggered(vehicleId, AlertType.Fuel, fuelLevel, fuelAlert.threshold);
        }
    }

    /**
     * @notice Set an alert for a vehicle
     * @param vehicleId The vehicle to set alert for
     * @param alertType Type of alert
     * @param threshold Threshold value
     */
    function setAlert(uint256 vehicleId, AlertType alertType, uint256 threshold) external whenNotPaused {
        Vehicle storage v = vehicles[vehicleId];
        require(msg.sender == v.fleetOwner, "Not fleet owner");
        require(v.active, "Vehicle not active");

        alerts[vehicleId][alertType] = Alert({
            alertType: alertType,
            threshold: threshold,
            active: true
        });

        emit AlertSet(vehicleId, alertType, threshold);
    }

    /**
     * @notice Deactivate an alert
     * @param vehicleId The vehicle
     * @param alertType The alert type to deactivate
     */
    function deactivateAlert(uint256 vehicleId, AlertType alertType) external {
        require(msg.sender == vehicles[vehicleId].fleetOwner, "Not fleet owner");
        alerts[vehicleId][alertType].active = false;
    }

    /**
     * @notice Get vehicle telemetry history
     * @param vehicleId The vehicle to query
     * @param offset Starting index
     * @param limit Max records to return
     */
    function getVehicleHistory(
        uint256 vehicleId,
        uint256 offset,
        uint256 limit
    ) external view returns (TelemetryData[] memory) {
        TelemetryData[] storage data = _telemetry[vehicleId];
        if (offset >= data.length) return new TelemetryData[](0);
        uint256 end = offset + limit > data.length ? data.length : offset + limit;
        TelemetryData[] memory result = new TelemetryData[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = data[i];
        }
        return result;
    }

    /**
     * @notice Get vehicle IDs for a fleet owner
     * @param fleetOwner The fleet owner address
     */
    function getFleetVehicles(address fleetOwner) external view returns (uint256[] memory) {
        return fleetVehicles[fleetOwner];
    }

    /**
     * @notice Deactivate a vehicle
     * @param vehicleId The vehicle to deactivate
     */
    function deactivateVehicle(uint256 vehicleId) external {
        require(msg.sender == vehicles[vehicleId].fleetOwner || msg.sender == _owner, "Not authorized");
        vehicles[vehicleId].active = false;
        emit VehicleDeactivated(vehicleId);
    }
}
