// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GasAnalytics
 * @author ProbeChain Rydberg Testnet
 * @notice On-chain gas price analytics with historical data, averages, and predictions
 * @dev Records gas prices per block, computes averages, provides time-based predictions
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

contract GasAnalytics is Ownable, ReentrancyGuard, Pausable {
    // ---------- Structs ----------
    struct GasRecord {
        uint256 blockNumber;
        uint256 baseFee;
        uint256 priorityFee;
        uint256 totalGas;
        uint256 timestamp;
        address reporter;
    }

    struct GasStats {
        uint256 avgBaseFee;
        uint256 avgPriorityFee;
        uint256 minBaseFee;
        uint256 maxBaseFee;
        uint256 sampleCount;
    }

    struct TimeSlot {
        uint256 totalBaseFee;
        uint256 totalPriorityFee;
        uint256 count;
        uint256 minBaseFee;
        uint256 maxBaseFee;
    }

    // ---------- State ----------
    uint256 public totalRecords;
    uint256 public latestRecordedBlock;
    uint256 public constant MAX_BLOCK_RANGE = 1000;

    mapping(uint256 => GasRecord) public gasRecords;
    mapping(uint256 => bool) public blockRecorded;
    mapping(address => bool) public authorizedReporters;

    // Hourly time-slot aggregation (hour-of-day 0-23)
    mapping(uint256 => TimeSlot) public hourlySlots;

    // Running averages
    uint256 public runningBaseFeeSum;
    uint256 public runningPriorityFeeSum;
    uint256 public runningCount;

    // ---------- Events ----------
    /// @notice Emitted when a gas price is recorded
    event GasPriceRecorded(uint256 indexed blockNumber, uint256 baseFee, uint256 priorityFee, address indexed reporter);
    /// @notice Emitted when a reporter is authorized
    event ReporterAuthorized(address indexed reporter);
    /// @notice Emitted when a reporter is revoked
    event ReporterRevoked(address indexed reporter);
    /// @notice Emitted when gas stats are queried (off-chain event log)
    event GasStatsQueried(uint256 fromBlock, uint256 toBlock, uint256 avgBaseFee);

    // ---------- Constructor ----------
    constructor() Ownable() ReentrancyGuard() Pausable() {}

    /**
     * @notice Authorize a gas reporter
     * @param reporter Address to authorize
     */
    function authorizeReporter(address reporter) external onlyOwner {
        require(reporter != address(0), "Zero address");
        authorizedReporters[reporter] = true;
        emit ReporterAuthorized(reporter);
    }

    /**
     * @notice Revoke a gas reporter
     * @param reporter Address to revoke
     */
    function revokeReporter(address reporter) external onlyOwner {
        authorizedReporters[reporter] = false;
        emit ReporterRevoked(reporter);
    }

    /**
     * @notice Record gas price data for a block
     * @param blockNumber The block number
     * @param baseFee The base fee in wei
     * @param priorityFee The priority fee in wei
     */
    function recordGasPrice(uint256 blockNumber, uint256 baseFee, uint256 priorityFee)
        external
        whenNotPaused
    {
        require(authorizedReporters[msg.sender] || msg.sender == owner(), "Not authorized");
        require(blockNumber <= block.number, "Future block");
        require(!blockRecorded[blockNumber], "Block already recorded");
        require(baseFee > 0, "Zero base fee");

        blockRecorded[blockNumber] = true;
        GasRecord storage rec = gasRecords[blockNumber];
        rec.blockNumber = blockNumber;
        rec.baseFee = baseFee;
        rec.priorityFee = priorityFee;
        rec.totalGas = baseFee + priorityFee;
        rec.timestamp = block.timestamp;
        rec.reporter = msg.sender;

        totalRecords++;
        if (blockNumber > latestRecordedBlock) {
            latestRecordedBlock = blockNumber;
        }

        // Update running averages
        runningBaseFeeSum += baseFee;
        runningPriorityFeeSum += priorityFee;
        runningCount++;

        // Update hourly slot
        uint256 hour = (block.timestamp / 3600) % 24;
        TimeSlot storage slot = hourlySlots[hour];
        slot.totalBaseFee += baseFee;
        slot.totalPriorityFee += priorityFee;
        slot.count++;
        if (slot.minBaseFee == 0 || baseFee < slot.minBaseFee) {
            slot.minBaseFee = baseFee;
        }
        if (baseFee > slot.maxBaseFee) {
            slot.maxBaseFee = baseFee;
        }

        emit GasPriceRecorded(blockNumber, baseFee, priorityFee, msg.sender);
    }

    /**
     * @notice Record multiple gas prices in batch
     * @param blockNumbers Array of block numbers
     * @param baseFees Array of base fees
     * @param priorityFees Array of priority fees
     */
    function batchRecordGasPrice(
        uint256[] calldata blockNumbers,
        uint256[] calldata baseFees,
        uint256[] calldata priorityFees
    ) external whenNotPaused {
        require(authorizedReporters[msg.sender] || msg.sender == owner(), "Not authorized");
        require(blockNumbers.length == baseFees.length && baseFees.length == priorityFees.length, "Length mismatch");
        require(blockNumbers.length <= 100, "Batch too large");

        for (uint256 i = 0; i < blockNumbers.length; i++) {
            if (!blockRecorded[blockNumbers[i]] && baseFees[i] > 0 && blockNumbers[i] <= block.number) {
                blockRecorded[blockNumbers[i]] = true;
                GasRecord storage rec = gasRecords[blockNumbers[i]];
                rec.blockNumber = blockNumbers[i];
                rec.baseFee = baseFees[i];
                rec.priorityFee = priorityFees[i];
                rec.totalGas = baseFees[i] + priorityFees[i];
                rec.timestamp = block.timestamp;
                rec.reporter = msg.sender;

                totalRecords++;
                runningBaseFeeSum += baseFees[i];
                runningPriorityFeeSum += priorityFees[i];
                runningCount++;

                if (blockNumbers[i] > latestRecordedBlock) {
                    latestRecordedBlock = blockNumbers[i];
                }

                emit GasPriceRecorded(blockNumbers[i], baseFees[i], priorityFees[i], msg.sender);
            }
        }
    }

    /**
     * @notice Get average gas over a block range
     * @param fromBlock Start block
     * @param toBlock End block
     * @return stats Gas statistics for the range
     */
    function getAverageGas(uint256 fromBlock, uint256 toBlock)
        external
        view
        returns (GasStats memory stats)
    {
        require(toBlock >= fromBlock, "Invalid range");
        require(toBlock - fromBlock <= MAX_BLOCK_RANGE, "Range too large");

        uint256 sumBase;
        uint256 sumPriority;
        uint256 count;
        uint256 minBase = type(uint256).max;
        uint256 maxBase;

        for (uint256 b = fromBlock; b <= toBlock; b++) {
            if (blockRecorded[b]) {
                GasRecord storage rec = gasRecords[b];
                sumBase += rec.baseFee;
                sumPriority += rec.priorityFee;
                count++;
                if (rec.baseFee < minBase) minBase = rec.baseFee;
                if (rec.baseFee > maxBase) maxBase = rec.baseFee;
            }
        }

        if (count > 0) {
            stats.avgBaseFee = sumBase / count;
            stats.avgPriorityFee = sumPriority / count;
            stats.minBaseFee = minBase;
            stats.maxBaseFee = maxBase;
            stats.sampleCount = count;
        }
    }

    /**
     * @notice Predict gas for a target block based on hourly patterns
     * @param targetBlock The target block number
     * @return estimatedBaseFee Estimated base fee
     * @return estimatedPriorityFee Estimated priority fee
     */
    function predictGas(uint256 targetBlock)
        external
        view
        returns (uint256 estimatedBaseFee, uint256 estimatedPriorityFee)
    {
        require(targetBlock > block.number, "Must be future block");
        require(runningCount > 0, "No data available");

        // Estimate future hour based on block time (~2s per block on ProbeChain)
        uint256 blocksAhead = targetBlock - block.number;
        uint256 secondsAhead = blocksAhead * 2;
        uint256 futureTime = block.timestamp + secondsAhead;
        uint256 hour = (futureTime / 3600) % 24;

        TimeSlot storage slot = hourlySlots[hour];
        if (slot.count > 0) {
            estimatedBaseFee = slot.totalBaseFee / slot.count;
            estimatedPriorityFee = slot.totalPriorityFee / slot.count;
        } else {
            // Fallback to global average
            estimatedBaseFee = runningBaseFeeSum / runningCount;
            estimatedPriorityFee = runningPriorityFeeSum / runningCount;
        }
    }

    /**
     * @notice Get the best time (hour of day) to transact for a given max gas price
     * @param maxGasWilling Maximum total gas price willing to pay
     * @return bestHour The hour of day (0-23) with lowest average gas
     * @return avgGasAtBestHour Average total gas at that hour
     */
    function getBestTime(uint256 maxGasWilling)
        external
        view
        returns (uint256 bestHour, uint256 avgGasAtBestHour)
    {
        uint256 lowestAvg = type(uint256).max;
        bestHour = 0;

        for (uint256 h = 0; h < 24; h++) {
            TimeSlot storage slot = hourlySlots[h];
            if (slot.count > 0) {
                uint256 avgTotal = (slot.totalBaseFee + slot.totalPriorityFee) / slot.count;
                if (avgTotal < lowestAvg && avgTotal <= maxGasWilling) {
                    lowestAvg = avgTotal;
                    bestHour = h;
                }
            }
        }

        avgGasAtBestHour = (lowestAvg == type(uint256).max) ? 0 : lowestAvg;
    }

    /**
     * @notice Get global running averages
     * @return avgBaseFee Global average base fee
     * @return avgPriorityFee Global average priority fee
     */
    function getGlobalAverages() external view returns (uint256 avgBaseFee, uint256 avgPriorityFee) {
        if (runningCount == 0) return (0, 0);
        avgBaseFee = runningBaseFeeSum / runningCount;
        avgPriorityFee = runningPriorityFeeSum / runningCount;
    }
}
