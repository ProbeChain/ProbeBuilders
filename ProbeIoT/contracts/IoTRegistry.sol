// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IoTRegistry
 * @author ProbeChain
 * @notice On-chain IoT device registry for ProbeChain Rydberg Testnet
 * @dev Manages device lifecycle: registration, data reporting, verification, decommission
 */
contract IoTRegistry {
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
    enum DeviceType { Sensor, Actuator, Gateway }
    enum DeviceStatus { Active, Suspended, Decommissioned }

    struct Device {
        bytes32 deviceId;
        DeviceType deviceType;
        string firmware;
        address deviceOwner;
        DeviceStatus status;
        bool verified;
        uint256 registeredAt;
        uint256 dataCount;
    }

    struct DataReport {
        bytes32 dataHash;
        uint256 timestamp;
        address reporter;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(bytes32 => Device) public devices;
    mapping(bytes32 => DataReport[]) private _deviceData;
    mapping(address => bytes32[]) public ownerDevices;
    mapping(address => bool) public verifiers;
    uint256 public totalDevices;

    // ─── Events ─────────────────────────────────────────────────────────
    event DeviceRegistered(bytes32 indexed deviceId, DeviceType deviceType, address indexed deviceOwner);
    event DataReported(bytes32 indexed deviceId, bytes32 dataHash, uint256 timestamp);
    event DeviceVerified(bytes32 indexed deviceId, address indexed verifier);
    event DeviceDecommissioned(bytes32 indexed deviceId, address indexed by);
    event VerifierUpdated(address indexed verifier, bool status);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Admin ──────────────────────────────────────────────────────────
    /**
     * @notice Add or remove a device verifier
     * @param verifier Address of the verifier
     * @param status True to add, false to remove
     */
    function setVerifier(address verifier, bool status) external onlyOwner {
        verifiers[verifier] = status;
        emit VerifierUpdated(verifier, status);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register a new IoT device
     * @param deviceId Unique identifier for the device
     * @param deviceType Type: 0=Sensor, 1=Actuator, 2=Gateway
     * @param firmware Firmware version string
     * @param deviceOwner Address that owns the device
     */
    function registerDevice(
        bytes32 deviceId,
        DeviceType deviceType,
        string calldata firmware,
        address deviceOwner
    ) external whenNotPaused {
        require(devices[deviceId].registeredAt == 0, "Device exists");
        require(deviceOwner != address(0), "Zero owner");
        require(bytes(firmware).length > 0, "Empty firmware");

        devices[deviceId] = Device({
            deviceId: deviceId,
            deviceType: deviceType,
            firmware: firmware,
            deviceOwner: deviceOwner,
            status: DeviceStatus.Active,
            verified: false,
            registeredAt: block.timestamp,
            dataCount: 0
        });

        ownerDevices[deviceOwner].push(deviceId);
        totalDevices++;

        emit DeviceRegistered(deviceId, deviceType, deviceOwner);
    }

    /**
     * @notice Report data from a device
     * @param deviceId The device reporting data
     * @param dataHash Hash of the data payload
     * @param timestamp Off-chain timestamp of the reading
     */
    function reportData(
        bytes32 deviceId,
        bytes32 dataHash,
        uint256 timestamp
    ) external whenNotPaused {
        Device storage d = devices[deviceId];
        require(d.registeredAt != 0, "Device not found");
        require(d.status == DeviceStatus.Active, "Device not active");
        require(msg.sender == d.deviceOwner, "Not device owner");
        require(timestamp <= block.timestamp, "Future timestamp");

        _deviceData[deviceId].push(DataReport({
            dataHash: dataHash,
            timestamp: timestamp,
            reporter: msg.sender
        }));
        d.dataCount++;

        emit DataReported(deviceId, dataHash, timestamp);
    }

    /**
     * @notice Verify a device (verifier only)
     * @param deviceId The device to verify
     */
    function verifyDevice(bytes32 deviceId) external whenNotPaused {
        require(verifiers[msg.sender], "Not verifier");
        Device storage d = devices[deviceId];
        require(d.registeredAt != 0, "Device not found");
        require(d.status == DeviceStatus.Active, "Device not active");
        require(!d.verified, "Already verified");

        d.verified = true;
        emit DeviceVerified(deviceId, msg.sender);
    }

    /**
     * @notice Decommission a device
     * @param deviceId The device to decommission
     */
    function decommission(bytes32 deviceId) external whenNotPaused {
        Device storage d = devices[deviceId];
        require(d.registeredAt != 0, "Device not found");
        require(msg.sender == d.deviceOwner || msg.sender == _owner, "Not authorized");
        require(d.status != DeviceStatus.Decommissioned, "Already decommissioned");

        d.status = DeviceStatus.Decommissioned;
        emit DeviceDecommissioned(deviceId, msg.sender);
    }

    // ─── View Functions ─────────────────────────────────────────────────
    /**
     * @notice Get data reports for a device
     * @param deviceId The device to query
     * @param offset Starting index
     * @param limit Max records to return
     */
    function getDeviceData(
        bytes32 deviceId,
        uint256 offset,
        uint256 limit
    ) external view returns (DataReport[] memory) {
        DataReport[] storage reports = _deviceData[deviceId];
        uint256 end = offset + limit > reports.length ? reports.length : offset + limit;
        require(offset < reports.length, "Offset out of range");
        DataReport[] memory result = new DataReport[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = reports[i];
        }
        return result;
    }

    /**
     * @notice Get all device IDs owned by an address
     * @param deviceOwner The owner address
     */
    function getOwnerDeviceIds(address deviceOwner) external view returns (bytes32[] memory) {
        return ownerDevices[deviceOwner];
    }
}
