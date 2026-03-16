// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AdvancedScheduler
 * @author ProbeChain Team
 * @notice Advanced task scheduler with one-time and recurring execution on ProbeChain
 * @dev Supports keeper-based execution with payment, cancellation, and recurring scheduling
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

contract AdvancedScheduler is Ownable, ReentrancyGuard, Pausable {
    enum ScheduleType { Once, Recurring }
    enum ScheduleStatus { Active, Executed, Cancelled }

    /// @notice Schedule entry
    struct Schedule {
        uint256 id;
        address creator;
        address target;
        bytes callData;
        ScheduleType scheduleType;
        ScheduleStatus status;
        uint256 executeAfter;
        uint256 interval;
        uint256 maxExecutions;
        uint256 executionCount;
        uint256 payment;
        uint256 createdAt;
        uint256 lastExecutedAt;
    }

    mapping(uint256 => Schedule) private _schedules;
    mapping(address => uint256[]) private _creatorSchedules;
    mapping(address => bool) private _keepers;

    uint256 private _nextScheduleId = 1;
    uint256 public keeperRewardBps = 500; // 5% of payment
    uint256 public minPayment = 0.001 ether;

    /// @notice Emitted when a schedule is created
    event ScheduleCreated(uint256 indexed scheduleId, address indexed creator, ScheduleType scheduleType);
    /// @notice Emitted when a schedule is executed
    event ScheduleExecuted(uint256 indexed scheduleId, address indexed keeper, bool success, bytes result);
    /// @notice Emitted when a schedule is cancelled
    event ScheduleCancelled(uint256 indexed scheduleId);
    /// @notice Emitted when a keeper is registered/removed
    event KeeperUpdated(address indexed keeper, bool active);

    error ScheduleNotFound(uint256 scheduleId);
    error ScheduleNotActive(uint256 scheduleId);
    error TooEarlyToExecute(uint256 scheduleId, uint256 executeAfter);
    error MaxExecutionsReached(uint256 scheduleId);
    error InsufficientPayment(uint256 sent, uint256 required);
    error NotKeeperOrOwner(address caller);
    error NotCreatorOrOwner(address caller);
    error InvalidInterval();
    error InvalidCount();

    modifier onlyKeeper() {
        if (!_keepers[msg.sender] && msg.sender != owner()) revert NotKeeperOrOwner(msg.sender);
        _;
    }

    /**
     * @notice Schedule a one-time execution
     * @param target The contract to call
     * @param callData The encoded function call
     * @param executeAfter Timestamp after which execution is allowed
     * @return scheduleId The schedule identifier
     */
    function scheduleOnce(
        address target,
        bytes calldata callData,
        uint256 executeAfter
    ) external payable whenNotPaused returns (uint256 scheduleId) {
        if (msg.value < minPayment) revert InsufficientPayment(msg.value, minPayment);

        scheduleId = _nextScheduleId++;
        _schedules[scheduleId] = Schedule({
            id: scheduleId,
            creator: msg.sender,
            target: target,
            callData: callData,
            scheduleType: ScheduleType.Once,
            status: ScheduleStatus.Active,
            executeAfter: executeAfter,
            interval: 0,
            maxExecutions: 1,
            executionCount: 0,
            payment: msg.value,
            createdAt: block.timestamp,
            lastExecutedAt: 0
        });

        _creatorSchedules[msg.sender].push(scheduleId);
        emit ScheduleCreated(scheduleId, msg.sender, ScheduleType.Once);
    }

    /**
     * @notice Schedule a recurring execution
     * @param target The contract to call
     * @param callData The encoded function call
     * @param interval Time between executions in seconds
     * @param count Maximum number of executions
     * @return scheduleId The schedule identifier
     */
    function scheduleRecurring(
        address target,
        bytes calldata callData,
        uint256 interval,
        uint256 count
    ) external payable whenNotPaused returns (uint256 scheduleId) {
        if (msg.value < minPayment * count) revert InsufficientPayment(msg.value, minPayment * count);
        if (interval < 60) revert InvalidInterval();
        if (count == 0) revert InvalidCount();

        scheduleId = _nextScheduleId++;
        _schedules[scheduleId] = Schedule({
            id: scheduleId,
            creator: msg.sender,
            target: target,
            callData: callData,
            scheduleType: ScheduleType.Recurring,
            status: ScheduleStatus.Active,
            executeAfter: block.timestamp + interval,
            interval: interval,
            maxExecutions: count,
            executionCount: 0,
            payment: msg.value,
            createdAt: block.timestamp,
            lastExecutedAt: 0
        });

        _creatorSchedules[msg.sender].push(scheduleId);
        emit ScheduleCreated(scheduleId, msg.sender, ScheduleType.Recurring);
    }

    /**
     * @notice Cancel an active schedule and refund remaining payment
     * @param scheduleId The schedule to cancel
     */
    function cancelSchedule(uint256 scheduleId) external nonReentrant whenNotPaused {
        Schedule storage sched = _schedules[scheduleId];
        if (sched.id == 0) revert ScheduleNotFound(scheduleId);
        if (sched.creator != msg.sender && msg.sender != owner()) revert NotCreatorOrOwner(msg.sender);
        if (sched.status != ScheduleStatus.Active) revert ScheduleNotActive(scheduleId);

        sched.status = ScheduleStatus.Cancelled;

        // Refund remaining payment proportionally
        uint256 remaining = sched.maxExecutions > 0
            ? sched.payment * (sched.maxExecutions - sched.executionCount) / sched.maxExecutions
            : 0;

        if (remaining > 0) {
            (bool success, ) = sched.creator.call{value: remaining}("");
            require(success, "Refund failed");
        }

        emit ScheduleCancelled(scheduleId);
    }

    /**
     * @notice Execute a scheduled task (keeper function)
     * @param scheduleId The schedule to execute
     */
    function executeSchedule(uint256 scheduleId) external nonReentrant whenNotPaused onlyKeeper {
        Schedule storage sched = _schedules[scheduleId];
        if (sched.id == 0) revert ScheduleNotFound(scheduleId);
        if (sched.status != ScheduleStatus.Active) revert ScheduleNotActive(scheduleId);
        if (block.timestamp < sched.executeAfter) revert TooEarlyToExecute(scheduleId, sched.executeAfter);
        if (sched.executionCount >= sched.maxExecutions) revert MaxExecutionsReached(scheduleId);

        sched.executionCount++;
        sched.lastExecutedAt = block.timestamp;

        // Pay keeper reward
        uint256 perExecution = sched.payment / sched.maxExecutions;
        uint256 keeperReward = perExecution * keeperRewardBps / 10000;
        if (keeperReward > 0) {
            (bool paid, ) = msg.sender.call{value: keeperReward}("");
            require(paid, "Keeper payment failed");
        }

        // Execute the scheduled call
        (bool success, bytes memory result) = sched.target.call(sched.callData);

        // Update schedule for recurring
        if (sched.scheduleType == ScheduleType.Recurring && sched.executionCount < sched.maxExecutions) {
            sched.executeAfter = block.timestamp + sched.interval;
        } else {
            sched.status = ScheduleStatus.Executed;
        }

        emit ScheduleExecuted(scheduleId, msg.sender, success, result);
    }

    /**
     * @notice Get schedule details
     * @param scheduleId The schedule to query
     * @return schedule The schedule data
     */
    function getSchedule(uint256 scheduleId) external view returns (Schedule memory schedule) {
        if (_schedules[scheduleId].id == 0) revert ScheduleNotFound(scheduleId);
        return _schedules[scheduleId];
    }

    /**
     * @notice Get all schedules for a creator
     * @param creator The creator address
     * @return ids Array of schedule IDs
     */
    function getCreatorSchedules(address creator) external view returns (uint256[] memory ids) {
        return _creatorSchedules[creator];
    }

    /// @notice Register or remove a keeper
    function setKeeper(address keeper, bool active) external onlyOwner {
        _keepers[keeper] = active;
        emit KeeperUpdated(keeper, active);
    }

    /// @notice Check if address is a keeper
    function isKeeper(address addr) external view returns (bool) { return _keepers[addr]; }

    /// @notice Update keeper reward basis points
    function setKeeperRewardBps(uint256 bps) external onlyOwner {
        require(bps <= 2000, "Max 20%");
        keeperRewardBps = bps;
    }

    /// @notice Update minimum payment
    function setMinPayment(uint256 amount) external onlyOwner { minPayment = amount; }

    receive() external payable {}
}
