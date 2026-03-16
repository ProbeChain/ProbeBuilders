// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GoldReserveTracker
 * @author ProbeChain Team
 * @notice Gold reserve tracking contract for ProbeChain's gold-backed system
 * @dev Updates reserve data with verifier signatures, calculates decay and reward multipliers
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender); _; }
    function owner() public view virtual returns (address) { return _owner; }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner); _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardReentrantCall();
        _status = _ENTERED; _; _status = _NOT_ENTERED;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    error ExpectedPause();
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    modifier whenPaused() { if (!_paused) revert ExpectedPause(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

contract GoldReserveTracker is Ownable, ReentrancyGuard, Pausable {
    /// @notice Reserve snapshot
    struct ReserveSnapshot {
        uint256 totalOZ;         // total ounces of gold
        uint256 timestamp;
        address verifier;
        bytes32 signatureHash;
        uint256 blockNumber;
    }

    /// @notice Reserve statistics
    struct ReserveStats {
        uint256 currentOZ;
        uint256 peakOZ;
        uint256 lastUpdate;
        uint256 updateCount;
        uint256 averageOZ;
    }

    /// @notice Decay calculation result
    struct DecayResult {
        uint256 currentOZ;
        uint256 targetOZ;
        uint256 decayAmount;
        uint256 decayPercentBps;  // basis points
        bool isDeficit;
    }

    ReserveSnapshot[] private _snapshots;
    mapping(address => bool) private _verifiers;
    ReserveStats public stats;

    uint256 public targetReserve = 1000000; // target OZ (1M oz)
    uint256 public baseRewardMultiplier = 10000; // 1x in bps
    uint256 public maxRewardMultiplier = 30000;  // 3x in bps
    uint256 public minRewardMultiplier = 5000;   // 0.5x in bps
    uint256 public decayRatePerDay = 10;         // 0.1% per day in bps

    /// @notice Emitted when reserve is updated
    event ReserveUpdated(uint256 totalOZ, address indexed verifier, uint256 timestamp);
    /// @notice Emitted when decay is calculated
    event DecayCalculated(uint256 currentOZ, uint256 targetOZ, uint256 decayAmount);
    /// @notice Emitted when reward multiplier changes
    event RewardMultiplierUpdated(uint256 multiplier);
    /// @notice Emitted when verifier is updated
    event VerifierUpdated(address indexed verifier, bool active);
    /// @notice Emitted when target reserve is updated
    event TargetReserveUpdated(uint256 oldTarget, uint256 newTarget);

    error NotVerifier(address caller);
    error InvalidSignature();
    error StaleTimestamp(uint256 provided, uint256 lastUpdate);
    error ZeroAmount();
    error NoSnapshots();

    modifier onlyVerifier() {
        if (!_verifiers[msg.sender] && msg.sender != owner()) revert NotVerifier(msg.sender);
        _;
    }

    constructor() {
        _verifiers[msg.sender] = true;
    }

    /**
     * @notice Update the gold reserve amount with verifier signature
     * @param totalOZ The total ounces of gold in reserve
     * @param verifierSignature The verifier's signature hash
     * @param timestamp The timestamp of the verification
     */
    function updateReserve(
        uint256 totalOZ,
        bytes32 verifierSignature,
        uint256 timestamp
    ) external whenNotPaused onlyVerifier {
        if (totalOZ == 0) revert ZeroAmount();
        if (verifierSignature == bytes32(0)) revert InvalidSignature();
        if (stats.lastUpdate > 0 && timestamp <= stats.lastUpdate) {
            revert StaleTimestamp(timestamp, stats.lastUpdate);
        }

        _snapshots.push(ReserveSnapshot({
            totalOZ: totalOZ,
            timestamp: timestamp,
            verifier: msg.sender,
            signatureHash: verifierSignature,
            blockNumber: block.number
        }));

        // Update stats
        stats.currentOZ = totalOZ;
        stats.lastUpdate = timestamp;
        stats.updateCount++;
        if (totalOZ > stats.peakOZ) stats.peakOZ = totalOZ;

        // Calculate running average
        if (stats.updateCount == 1) {
            stats.averageOZ = totalOZ;
        } else {
            stats.averageOZ = (stats.averageOZ * (stats.updateCount - 1) + totalOZ) / stats.updateCount;
        }

        emit ReserveUpdated(totalOZ, msg.sender, timestamp);
    }

    /**
     * @notice Get current reserve data
     * @return totalOZ The current total ounces
     * @return lastUpdate The last update timestamp
     */
    function getReserve() external view returns (uint256 totalOZ, uint256 lastUpdate) {
        return (stats.currentOZ, stats.lastUpdate);
    }

    /**
     * @notice Calculate decay between current and target reserve
     * @param currentOZ The current reserve amount
     * @param targetOZ The target reserve amount
     * @return result The decay calculation result
     */
    function calculateDecay(
        uint256 currentOZ,
        uint256 targetOZ
    ) external view returns (DecayResult memory result) {
        result.currentOZ = currentOZ;
        result.targetOZ = targetOZ;

        if (currentOZ >= targetOZ) {
            result.decayAmount = 0;
            result.decayPercentBps = 0;
            result.isDeficit = false;
        } else {
            result.decayAmount = targetOZ - currentOZ;
            result.decayPercentBps = (result.decayAmount * 10000) / targetOZ;
            result.isDeficit = true;
        }

        // Apply time-based decay if reserve hasn't been updated recently
        if (stats.lastUpdate > 0) {
            uint256 daysSinceUpdate = (block.timestamp - stats.lastUpdate) / 1 days;
            if (daysSinceUpdate > 0) {
                uint256 timeDecay = (currentOZ * decayRatePerDay * daysSinceUpdate) / 10000;
                result.decayAmount += timeDecay;
                result.decayPercentBps += (timeDecay * 10000) / (targetOZ > 0 ? targetOZ : 1);
            }
        }

        emit DecayCalculated(currentOZ, targetOZ, result.decayAmount);
    }

    /**
     * @notice Get the current reward multiplier based on reserve health
     * @return multiplier The reward multiplier in basis points (10000 = 1x)
     */
    function getRewardMultiplier() external view returns (uint256 multiplier) {
        if (stats.currentOZ == 0 || targetReserve == 0) return baseRewardMultiplier;

        uint256 ratio = (stats.currentOZ * 10000) / targetReserve;

        if (ratio >= 12000) {
            // 120%+ reserve: max multiplier
            multiplier = maxRewardMultiplier;
        } else if (ratio >= 10000) {
            // 100-120%: linearly scale between base and max
            multiplier = baseRewardMultiplier +
                ((ratio - 10000) * (maxRewardMultiplier - baseRewardMultiplier)) / 2000;
        } else if (ratio >= 5000) {
            // 50-100%: linearly scale between min and base
            multiplier = minRewardMultiplier +
                ((ratio - 5000) * (baseRewardMultiplier - minRewardMultiplier)) / 5000;
        } else {
            // Below 50%: minimum
            multiplier = minRewardMultiplier;
        }
    }

    /**
     * @notice Get historical snapshots
     * @param startIndex The start index
     * @param count Number of snapshots to return
     * @return snapshots Array of reserve snapshots
     */
    function getSnapshots(
        uint256 startIndex,
        uint256 count
    ) external view returns (ReserveSnapshot[] memory snapshots) {
        if (_snapshots.length == 0) revert NoSnapshots();

        uint256 end = startIndex + count;
        if (end > _snapshots.length) end = _snapshots.length;
        uint256 length = end - startIndex;

        snapshots = new ReserveSnapshot[](length);
        for (uint256 i = 0; i < length; i++) {
            snapshots[i] = _snapshots[startIndex + i];
        }
    }

    /**
     * @notice Get total snapshot count
     * @return count Number of snapshots
     */
    function getSnapshotCount() external view returns (uint256 count) {
        return _snapshots.length;
    }

    /**
     * @notice Get reserve statistics
     * @return reserveStats The current reserve statistics
     */
    function getStats() external view returns (ReserveStats memory reserveStats) {
        return stats;
    }

    /// @notice Set verifier status
    function setVerifier(address verifier, bool active) external onlyOwner {
        _verifiers[verifier] = active;
        emit VerifierUpdated(verifier, active);
    }

    /// @notice Check if address is verifier
    function isVerifier(address addr) external view returns (bool) { return _verifiers[addr]; }

    /// @notice Update target reserve
    function setTargetReserve(uint256 target) external onlyOwner {
        uint256 old = targetReserve;
        targetReserve = target;
        emit TargetReserveUpdated(old, target);
    }

    /// @notice Update reward multiplier bounds
    function setRewardBounds(uint256 min, uint256 base, uint256 max) external onlyOwner {
        require(min <= base && base <= max, "Invalid bounds");
        minRewardMultiplier = min;
        baseRewardMultiplier = base;
        maxRewardMultiplier = max;
    }

    /// @notice Update decay rate
    function setDecayRate(uint256 rate) external onlyOwner {
        require(rate <= 1000, "Max 10% per day");
        decayRatePerDay = rate;
    }
}
