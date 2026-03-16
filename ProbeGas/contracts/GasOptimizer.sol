// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GasOptimizer
 * @author ProbeChain Team
 * @notice Gas estimation and optimization utility for ProbeChain Rydberg Testnet
 * @dev Provides gas estimation, batched transactions, and refund mechanisms
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
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
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

contract GasOptimizer is Ownable, ReentrancyGuard, Pausable {
    /// @notice Gas estimation record
    struct GasEstimate {
        address target;
        uint256 estimatedGas;
        uint256 timestamp;
        bool success;
    }

    /// @notice Batch execution result
    struct BatchResult {
        bool success;
        bytes returnData;
        uint256 gasUsed;
    }

    /// @notice Refund tracking
    struct RefundRecord {
        address user;
        uint256 deposited;
        uint256 used;
        uint256 refunded;
    }

    mapping(address => GasEstimate[]) private _estimates;
    mapping(address => RefundRecord) private _refunds;
    mapping(address => uint256) private _deposits;

    uint256 public gasPriceMultiplier = 110; // 110% of base
    uint256 public maxBatchSize = 20;
    uint256 public totalGasSaved;

    /// @notice Emitted when gas is estimated
    event GasEstimated(address indexed target, uint256 estimatedGas, bool success);
    /// @notice Emitted when a batch is executed
    event BatchExecuted(address indexed sender, uint256 txCount, uint256 totalGasUsed);
    /// @notice Emitted when gas is refunded
    event GasRefunded(address indexed user, uint256 amount);
    /// @notice Emitted when deposit is received
    event Deposited(address indexed user, uint256 amount);

    error EmptyBatch();
    error BatchTooLarge(uint256 size, uint256 max);
    error ArrayLengthMismatch();
    error InsufficientDeposit(uint256 available, uint256 required);
    error NoRefundAvailable();
    error CallFailed(uint256 index, bytes reason);
    error ZeroAddress();

    /**
     * @notice Estimate gas for a call to a target contract
     * @param target The target contract address
     * @param callData The encoded function call
     * @return estimatedGas The estimated gas for the call
     * @return success Whether the estimation succeeded
     */
    function estimateGas(
        address target,
        bytes calldata callData
    ) external whenNotPaused returns (uint256 estimatedGas, bool success) {
        if (target == address(0)) revert ZeroAddress();

        uint256 gasBefore = gasleft();
        (success, ) = target.staticcall(callData);
        uint256 gasAfter = gasleft();

        estimatedGas = gasBefore - gasAfter;

        _estimates[target].push(GasEstimate({
            target: target,
            estimatedGas: estimatedGas,
            timestamp: block.timestamp,
            success: success
        }));

        emit GasEstimated(target, estimatedGas, success);
    }

    /**
     * @notice Suggest optimal gas parameters for a target call
     * @param target The target contract address
     * @return gasLimit Suggested gas limit
     * @return gasPrice Suggested gas price in wei
     */
    function suggestOptimalGas(
        address target
    ) external view returns (uint256 gasLimit, uint256 gasPrice) {
        GasEstimate[] storage estimates = _estimates[target];
        if (estimates.length == 0) {
            return (200000, tx.gasprice);
        }

        // Average of last 5 estimates with buffer
        uint256 total;
        uint256 count;
        uint256 startIdx = estimates.length > 5 ? estimates.length - 5 : 0;
        for (uint256 i = startIdx; i < estimates.length; i++) {
            if (estimates[i].success) {
                total += estimates[i].estimatedGas;
                count++;
            }
        }

        gasLimit = count > 0 ? (total / count) * gasPriceMultiplier / 100 : 200000;
        gasPrice = tx.gasprice * gasPriceMultiplier / 100;
    }

    /**
     * @notice Execute multiple transactions in a single batch
     * @param targets Array of target contract addresses
     * @param calldatas Array of encoded function calls
     * @return results Array of batch execution results
     */
    function batchTransactions(
        address[] calldata targets,
        bytes[] calldata calldatas
    ) external payable nonReentrant whenNotPaused returns (BatchResult[] memory results) {
        if (targets.length == 0) revert EmptyBatch();
        if (targets.length != calldatas.length) revert ArrayLengthMismatch();
        if (targets.length > maxBatchSize) revert BatchTooLarge(targets.length, maxBatchSize);

        results = new BatchResult[](targets.length);
        uint256 totalGasUsed;
        uint256 gasBefore;

        for (uint256 i = 0; i < targets.length; i++) {
            gasBefore = gasleft();
            (bool success, bytes memory returnData) = targets[i].call(calldatas[i]);
            uint256 gasUsed = gasBefore - gasleft();

            results[i] = BatchResult({
                success: success,
                returnData: returnData,
                gasUsed: gasUsed
            });
            totalGasUsed += gasUsed;
        }

        totalGasSaved += totalGasUsed / 10; // Estimate 10% savings from batching
        emit BatchExecuted(msg.sender, targets.length, totalGasUsed);
    }

    /**
     * @notice Deposit ETH for gas refund tracking
     */
    function deposit() external payable whenNotPaused {
        require(msg.value > 0, "Must deposit > 0");
        _deposits[msg.sender] += msg.value;

        RefundRecord storage record = _refunds[msg.sender];
        record.user = msg.sender;
        record.deposited += msg.value;

        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @notice Refund unused gas to a user
     */
    function refundUnusedGas() external nonReentrant whenNotPaused {
        RefundRecord storage record = _refunds[msg.sender];
        uint256 available = record.deposited - record.used - record.refunded;
        if (available == 0) revert NoRefundAvailable();

        record.refunded += available;
        _deposits[msg.sender] = 0;

        (bool success, ) = msg.sender.call{value: available}("");
        require(success, "Refund transfer failed");

        emit GasRefunded(msg.sender, available);
    }

    /**
     * @notice Record gas usage for a user
     * @param user The user address
     * @param amount The gas cost to record
     */
    function recordUsage(address user, uint256 amount) external onlyOwner {
        _refunds[user].used += amount;
    }

    /**
     * @notice Get gas estimates for a target
     * @param target The target address
     * @return estimates Array of gas estimates
     */
    function getEstimates(address target) external view returns (GasEstimate[] memory estimates) {
        return _estimates[target];
    }

    /**
     * @notice Get refund record for a user
     * @param user The user address
     * @return record The refund record
     */
    function getRefundRecord(address user) external view returns (RefundRecord memory record) {
        return _refunds[user];
    }

    /**
     * @notice Update gas price multiplier
     * @param newMultiplier New multiplier (100 = 1x)
     */
    function setGasPriceMultiplier(uint256 newMultiplier) external onlyOwner {
        require(newMultiplier >= 100 && newMultiplier <= 300, "Multiplier out of range");
        gasPriceMultiplier = newMultiplier;
    }

    /**
     * @notice Update max batch size
     * @param newMax New maximum batch size
     */
    function setMaxBatchSize(uint256 newMax) external onlyOwner {
        require(newMax > 0 && newMax <= 100, "Invalid batch size");
        maxBatchSize = newMax;
    }

    /// @notice Allow contract to receive ETH
    receive() external payable {}
}
