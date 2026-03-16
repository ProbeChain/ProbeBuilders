// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MineMonitor
 * @author ProbeChain
 * @notice Mining production monitoring and verification on ProbeChain Rydberg Testnet
 * @dev Register mines, report production, auditor verification, production history
 */
contract MineMonitor {
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

    // ─── Structs ────────────────────────────────────────────────────────
    struct Mine {
        bytes32 mineId;
        address mineOwner;
        string location;
        string mineralType;
        bool active;
        uint256 totalProduction;
        uint256 verifiedProduction;
        uint256 registeredAt;
    }

    struct ProductionReport {
        uint256 amount;
        uint256 grade; // quality grade in basis points (0-10000)
        uint256 timestamp;
        bool verified;
        address verifier;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(bytes32 => Mine) public mines;
    mapping(bytes32 => ProductionReport[]) private _productionHistory;
    mapping(address => bool) public auditors;
    mapping(address => bytes32[]) public ownerMines;
    uint256 public totalMines;

    // ─── Events ─────────────────────────────────────────────────────────
    event MineRegistered(bytes32 indexed mineId, address indexed mineOwner, string mineralType);
    event ProductionReported(bytes32 indexed mineId, uint256 amount, uint256 grade, uint256 timestamp);
    event ProductionVerified(bytes32 indexed mineId, uint256 reportIndex, address indexed auditor);
    event AuditorUpdated(address indexed auditor, bool status);
    event MineDeactivated(bytes32 indexed mineId);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Admin ──────────────────────────────────────────────────────────
    function setAuditor(address auditor, bool status) external onlyOwner {
        auditors[auditor] = status;
        emit AuditorUpdated(auditor, status);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register a mine
     * @param mineId Unique mine identifier
     * @param location Mine location
     * @param mineralType Type of mineral being extracted
     */
    function registerMine(
        bytes32 mineId,
        string calldata location,
        string calldata mineralType
    ) external whenNotPaused {
        require(mines[mineId].registeredAt == 0, "Mine exists");
        require(bytes(location).length > 0, "Empty location");
        require(bytes(mineralType).length > 0, "Empty mineral type");

        mines[mineId] = Mine({
            mineId: mineId,
            mineOwner: msg.sender,
            location: location,
            mineralType: mineralType,
            active: true,
            totalProduction: 0,
            verifiedProduction: 0,
            registeredAt: block.timestamp
        });

        ownerMines[msg.sender].push(mineId);
        totalMines++;

        emit MineRegistered(mineId, msg.sender, mineralType);
    }

    /**
     * @notice Report production data
     * @param mineId The mine reporting production
     * @param amount Amount produced (in smallest unit)
     * @param grade Quality grade in basis points (0-10000)
     * @param timestamp Off-chain timestamp of production
     */
    function reportProduction(
        bytes32 mineId,
        uint256 amount,
        uint256 grade,
        uint256 timestamp
    ) external whenNotPaused {
        Mine storage m = mines[mineId];
        require(m.active, "Mine not active");
        require(msg.sender == m.mineOwner, "Not mine owner");
        require(amount > 0, "Zero amount");
        require(grade <= 10000, "Invalid grade");
        require(timestamp <= block.timestamp, "Future timestamp");

        _productionHistory[mineId].push(ProductionReport({
            amount: amount,
            grade: grade,
            timestamp: timestamp,
            verified: false,
            verifier: address(0)
        }));

        m.totalProduction += amount;
        emit ProductionReported(mineId, amount, grade, timestamp);
    }

    /**
     * @notice Verify a production report (auditor only)
     * @param mineId The mine to verify
     * @param reportIndex Index of the production report
     */
    function verifyProduction(bytes32 mineId, uint256 reportIndex) external whenNotPaused {
        require(auditors[msg.sender], "Not auditor");
        ProductionReport[] storage reports = _productionHistory[mineId];
        require(reportIndex < reports.length, "Invalid index");
        require(!reports[reportIndex].verified, "Already verified");

        reports[reportIndex].verified = true;
        reports[reportIndex].verifier = msg.sender;
        mines[mineId].verifiedProduction += reports[reportIndex].amount;

        emit ProductionVerified(mineId, reportIndex, msg.sender);
    }

    /**
     * @notice Get production history for a mine
     * @param mineId The mine to query
     * @param offset Starting index
     * @param limit Max records
     */
    function getProductionHistory(
        bytes32 mineId,
        uint256 offset,
        uint256 limit
    ) external view returns (ProductionReport[] memory) {
        ProductionReport[] storage reports = _productionHistory[mineId];
        if (offset >= reports.length) return new ProductionReport[](0);
        uint256 end = offset + limit > reports.length ? reports.length : offset + limit;
        ProductionReport[] memory result = new ProductionReport[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = reports[i];
        }
        return result;
    }

    /**
     * @notice Get mine IDs owned by an address
     */
    function getOwnerMines(address mineOwner) external view returns (bytes32[] memory) {
        return ownerMines[mineOwner];
    }

    /**
     * @notice Deactivate a mine
     */
    function deactivateMine(bytes32 mineId) external {
        require(msg.sender == mines[mineId].mineOwner || msg.sender == _owner, "Not authorized");
        mines[mineId].active = false;
        emit MineDeactivated(mineId);
    }
}
