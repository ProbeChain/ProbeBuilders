// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CoverageProtocol
 * @author ProbeChain
 * @notice Decentralized wireless coverage network on ProbeChain Rydberg Testnet
 * @dev Hotspot registration, coverage reporting, verification, and reward distribution
 */
contract CoverageProtocol {
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
    enum SignalType { WiFi, LTE, FiveG, LoRa, Bluetooth }

    struct Hotspot {
        address hotspotOwner;
        bytes32 locationHash;
        SignalType signalType;
        uint256 bandwidthMbps;
        bool verified;
        bool active;
        uint256 totalUsersServed;
        uint256 totalUptime;
        uint256 pendingReward;
        uint256 registeredAt;
    }

    struct CoverageReport {
        uint256 usersServed;
        uint256 uptimeSeconds;
        uint256 timestamp;
        address reporter;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => Hotspot) public hotspots;
    mapping(uint256 => CoverageReport[]) private _coverageReports;
    mapping(address => bool) public verifiers;
    uint256 public nextHotspotId;
    uint256 public rewardPerUserServed = 1e15; // 0.001 ETH per user
    uint256 public rewardPool;

    // ─── Events ─────────────────────────────────────────────────────────
    event HotspotRegistered(uint256 indexed hotspotId, address indexed hotspotOwner, SignalType signalType);
    event CoverageReported(uint256 indexed hotspotId, uint256 usersServed, uint256 uptimeSeconds);
    event HotspotVerified(uint256 indexed hotspotId, address indexed verifier);
    event RewardClaimed(uint256 indexed hotspotId, address indexed hotspotOwner, uint256 amount);
    event VerifierUpdated(address indexed verifier, bool status);
    event RewardPoolFunded(address indexed funder, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     * @notice Fund the reward pool
     */
    receive() external payable {
        rewardPool += msg.value;
        emit RewardPoolFunded(msg.sender, msg.value);
    }

    // ─── Admin ──────────────────────────────────────────────────────────
    function setVerifier(address verifier, bool status) external onlyOwner {
        verifiers[verifier] = status;
        emit VerifierUpdated(verifier, status);
    }

    function setRewardRate(uint256 rate) external onlyOwner {
        rewardPerUserServed = rate;
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register a wireless hotspot
     * @param locationHash Geohash or location identifier
     * @param signalType Type of wireless signal
     * @param bandwidthMbps Available bandwidth in Mbps
     */
    function registerHotspot(
        bytes32 locationHash,
        SignalType signalType,
        uint256 bandwidthMbps
    ) external whenNotPaused returns (uint256) {
        require(locationHash != bytes32(0), "Empty location");
        require(bandwidthMbps > 0, "Zero bandwidth");

        uint256 id = nextHotspotId++;
        hotspots[id] = Hotspot({
            hotspotOwner: msg.sender,
            locationHash: locationHash,
            signalType: signalType,
            bandwidthMbps: bandwidthMbps,
            verified: false,
            active: true,
            totalUsersServed: 0,
            totalUptime: 0,
            pendingReward: 0,
            registeredAt: block.timestamp
        });

        emit HotspotRegistered(id, msg.sender, signalType);
        return id;
    }

    /**
     * @notice Report coverage provided by a hotspot
     * @param hotspotId The hotspot reporting coverage
     * @param usersServed Number of users served in this period
     * @param uptimeSeconds Uptime in seconds for this period
     */
    function reportCoverage(
        uint256 hotspotId,
        uint256 usersServed,
        uint256 uptimeSeconds
    ) external whenNotPaused {
        Hotspot storage h = hotspots[hotspotId];
        require(h.active, "Hotspot not active");
        require(msg.sender == h.hotspotOwner, "Not hotspot owner");

        _coverageReports[hotspotId].push(CoverageReport({
            usersServed: usersServed,
            uptimeSeconds: uptimeSeconds,
            timestamp: block.timestamp,
            reporter: msg.sender
        }));

        h.totalUsersServed += usersServed;
        h.totalUptime += uptimeSeconds;

        if (h.verified) {
            h.pendingReward += usersServed * rewardPerUserServed;
        }

        emit CoverageReported(hotspotId, usersServed, uptimeSeconds);
    }

    /**
     * @notice Verify a hotspot (verifier only)
     * @param hotspotId The hotspot to verify
     */
    function verifyHotspot(uint256 hotspotId) external whenNotPaused {
        require(verifiers[msg.sender], "Not verifier");
        Hotspot storage h = hotspots[hotspotId];
        require(h.active, "Hotspot not active");
        require(!h.verified, "Already verified");

        h.verified = true;
        emit HotspotVerified(hotspotId, msg.sender);
    }

    /**
     * @notice Claim pending rewards for a hotspot
     * @param hotspotId The hotspot to claim rewards for
     */
    function claimReward(uint256 hotspotId) external whenNotPaused nonReentrant {
        Hotspot storage h = hotspots[hotspotId];
        require(msg.sender == h.hotspotOwner, "Not hotspot owner");
        require(h.verified, "Not verified");
        require(h.pendingReward > 0, "No rewards");
        require(rewardPool >= h.pendingReward, "Pool insufficient");

        uint256 amount = h.pendingReward;
        h.pendingReward = 0;
        rewardPool -= amount;

        payable(msg.sender).transfer(amount);
        emit RewardClaimed(hotspotId, msg.sender, amount);
    }

    /**
     * @notice Deactivate a hotspot
     * @param hotspotId The hotspot to deactivate
     */
    function deactivateHotspot(uint256 hotspotId) external {
        require(msg.sender == hotspots[hotspotId].hotspotOwner || msg.sender == _owner, "Not authorized");
        hotspots[hotspotId].active = false;
    }

    /**
     * @notice Get coverage reports for a hotspot
     */
    function getCoverageReports(uint256 hotspotId, uint256 offset, uint256 limit)
        external view returns (CoverageReport[] memory)
    {
        CoverageReport[] storage reports = _coverageReports[hotspotId];
        if (offset >= reports.length) return new CoverageReport[](0);
        uint256 end = offset + limit > reports.length ? reports.length : offset + limit;
        CoverageReport[] memory result = new CoverageReport[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = reports[i];
        }
        return result;
    }
}
