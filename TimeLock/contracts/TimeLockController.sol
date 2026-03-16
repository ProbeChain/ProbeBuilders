// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TimeLockController
 * @author ProbeChain
 * @notice Timelock controller with proposer/executor roles and min/max delay constraints
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() { _status = _NOT_ENTERED; }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract TimeLockController is Ownable, ReentrancyGuard {
    /// @notice Operation status
    enum OperationStatus { None, Scheduled, Ready, Executed, Cancelled }

    /// @notice Scheduled operation
    struct Operation {
        bytes32 id;
        address target;
        uint256 value;
        bytes data;
        uint256 scheduledAt;
        uint256 executeAfter;
        OperationStatus status;
        address proposer;
    }

    /// @dev Minimum delay in seconds
    uint256 public minDelay;

    /// @dev Maximum delay in seconds
    uint256 public maxDelay;

    /// @dev Operation ID => Operation
    mapping(bytes32 => Operation) private _operations;

    /// @dev All operation IDs
    bytes32[] private _operationIds;

    /// @dev Proposer role
    mapping(address => bool) public proposers;

    /// @dev Executor role
    mapping(address => bool) public executors;

    /// @dev Total operations scheduled
    uint256 public totalOperations;

    // ───────── Events ─────────

    /// @notice Emitted when an operation is scheduled
    event OperationScheduled(bytes32 indexed operationId, address indexed target, uint256 value, uint256 delay, address indexed proposer);

    /// @notice Emitted when an operation is executed
    event OperationExecuted(bytes32 indexed operationId, address indexed target, address indexed executor);

    /// @notice Emitted when an operation is cancelled
    event OperationCancelled(bytes32 indexed operationId, address indexed canceller);

    /// @notice Emitted when a role is granted
    event RoleGranted(address indexed account, string role);

    /// @notice Emitted when a role is revoked
    event RoleRevoked(address indexed account, string role);

    /// @notice Emitted when delay bounds are updated
    event DelayUpdated(uint256 minDelay, uint256 maxDelay);

    /// @notice Emitted when PROBE is deposited
    event Deposited(address indexed sender, uint256 amount);

    // ───────── Constructor ─────────

    /// @param _minDelay Minimum delay in seconds
    /// @param _maxDelay Maximum delay in seconds
    constructor(uint256 _minDelay, uint256 _maxDelay) {
        require(_minDelay <= _maxDelay, "TimeLock: min > max");
        minDelay = _minDelay;
        maxDelay = _maxDelay;

        // Owner gets both roles by default
        proposers[msg.sender] = true;
        executors[msg.sender] = true;
    }

    /// @notice Receive PROBE
    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    // ───────── Admin ─────────

    /// @notice Grant proposer role
    function grantProposer(address account) external onlyOwner {
        require(account != address(0), "TimeLock: zero address");
        proposers[account] = true;
        emit RoleGranted(account, "proposer");
    }

    /// @notice Revoke proposer role
    function revokeProposer(address account) external onlyOwner {
        proposers[account] = false;
        emit RoleRevoked(account, "proposer");
    }

    /// @notice Grant executor role
    function grantExecutor(address account) external onlyOwner {
        require(account != address(0), "TimeLock: zero address");
        executors[account] = true;
        emit RoleGranted(account, "executor");
    }

    /// @notice Revoke executor role
    function revokeExecutor(address account) external onlyOwner {
        executors[account] = false;
        emit RoleRevoked(account, "executor");
    }

    /// @notice Update delay bounds
    function updateDelay(uint256 _minDelay, uint256 _maxDelay) external onlyOwner {
        require(_minDelay <= _maxDelay, "TimeLock: min > max");
        minDelay = _minDelay;
        maxDelay = _maxDelay;
        emit DelayUpdated(_minDelay, _maxDelay);
    }

    // ───────── Core Functions ─────────

    /// @notice Schedule an operation with a time delay
    /// @param target Target contract address
    /// @param value PROBE value to send
    /// @param data Calldata to execute
    /// @param delay Delay in seconds before execution
    /// @return operationId The operation hash ID
    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        uint256 delay
    ) external returns (bytes32 operationId) {
        require(proposers[msg.sender], "TimeLock: not proposer");
        require(target != address(0), "TimeLock: zero target");
        require(delay >= minDelay, "TimeLock: delay too short");
        require(delay <= maxDelay, "TimeLock: delay too long");

        operationId = keccak256(abi.encodePacked(target, value, data, block.timestamp, msg.sender));
        require(_operations[operationId].status == OperationStatus.None, "TimeLock: already exists");

        uint256 executeAfter = block.timestamp + delay;

        _operations[operationId] = Operation({
            id: operationId,
            target: target,
            value: value,
            data: data,
            scheduledAt: block.timestamp,
            executeAfter: executeAfter,
            status: OperationStatus.Scheduled,
            proposer: msg.sender
        });

        _operationIds.push(operationId);
        totalOperations++;

        emit OperationScheduled(operationId, target, value, delay, msg.sender);
    }

    /// @notice Execute a scheduled operation after delay has passed
    /// @param operationId The operation to execute
    function execute(bytes32 operationId) external nonReentrant {
        require(executors[msg.sender], "TimeLock: not executor");

        Operation storage op = _operations[operationId];
        require(op.status == OperationStatus.Scheduled, "TimeLock: not scheduled");
        require(block.timestamp >= op.executeAfter, "TimeLock: too early");

        op.status = OperationStatus.Executed;

        (bool success, ) = op.target.call{value: op.value}(op.data);
        require(success, "TimeLock: execution failed");

        emit OperationExecuted(operationId, op.target, msg.sender);
    }

    /// @notice Cancel a scheduled operation
    /// @param operationId The operation to cancel
    function cancel(bytes32 operationId) external {
        Operation storage op = _operations[operationId];
        require(op.status == OperationStatus.Scheduled, "TimeLock: not scheduled");
        require(
            msg.sender == op.proposer || msg.sender == owner(),
            "TimeLock: not authorized"
        );

        op.status = OperationStatus.Cancelled;
        emit OperationCancelled(operationId, msg.sender);
    }

    // ───────── View Functions ─────────

    /// @notice Get operation details
    function getOperation(bytes32 operationId) external view returns (Operation memory) {
        require(_operations[operationId].scheduledAt > 0, "TimeLock: not found");
        return _operations[operationId];
    }

    /// @notice Check if operation is ready for execution
    function isReady(bytes32 operationId) external view returns (bool) {
        Operation memory op = _operations[operationId];
        return op.status == OperationStatus.Scheduled && block.timestamp >= op.executeAfter;
    }

    /// @notice Get all operation IDs
    function getOperationIds() external view returns (bytes32[] memory) {
        return _operationIds;
    }

    /// @notice Get pending operations
    function getPendingOperations() external view returns (bytes32[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < _operationIds.length; i++) {
            if (_operations[_operationIds[i]].status == OperationStatus.Scheduled) count++;
        }
        bytes32[] memory result = new bytes32[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < _operationIds.length; i++) {
            if (_operations[_operationIds[i]].status == OperationStatus.Scheduled) {
                result[j++] = _operationIds[i];
            }
        }
        return result;
    }

    /// @notice Get contract balance
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
