// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CronScheduler
 * @author ProbeChain Rydberg Testnet
 * @notice Decentralized cron job scheduler with keeper incentives for automated contract calls
 * @dev Create recurring jobs with intervals, keepers execute and earn rewards
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

contract CronScheduler is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum JobStatus { Active, Paused, Completed, Cancelled }

    // ---------- Structs ----------
    struct Job {
        uint256 id;
        address creator;
        address target;
        bytes callData;
        uint256 interval;
        uint256 startTime;
        uint256 maxExecutions;
        uint256 executionCount;
        uint256 lastExecutedAt;
        uint256 nextExecutionAt;
        uint256 deposit;
        uint256 rewardPerExecution;
        JobStatus status;
        uint256 createdAt;
    }

    struct KeeperInfo {
        address keeper;
        uint256 totalExecutions;
        uint256 totalEarned;
        uint256 lastActive;
        bool registered;
    }

    // ---------- State ----------
    uint256 public nextJobId;
    uint256 public minInterval;
    uint256 public maxInterval;
    uint256 public minRewardPerExecution;
    uint256 public keeperStakeRequired;

    mapping(uint256 => Job) public jobs;
    mapping(address => uint256[]) public creatorJobs;
    mapping(address => KeeperInfo) public keepers;
    mapping(address => uint256) public keeperStakes;
    mapping(uint256 => address) public lastExecutor;

    uint256 public totalActiveJobs;
    uint256 public totalExecutions;

    // ---------- Events ----------
    /// @notice Emitted when a job is created
    event JobCreated(uint256 indexed jobId, address indexed creator, address target, uint256 interval, uint256 maxExecutions);
    /// @notice Emitted when a job is executed by a keeper
    event JobExecuted(uint256 indexed jobId, address indexed keeper, uint256 executionCount, bool success);
    /// @notice Emitted when a job is paused
    event JobPaused(uint256 indexed jobId);
    /// @notice Emitted when a job is resumed
    event JobResumed(uint256 indexed jobId);
    /// @notice Emitted when a job is cancelled
    event JobCancelled(uint256 indexed jobId, uint256 refund);
    /// @notice Emitted when a keeper registers
    event KeeperRegistered(address indexed keeper, uint256 stake);
    /// @notice Emitted when a keeper is rewarded
    event KeeperRewarded(address indexed keeper, uint256 amount);

    // ---------- Constructor ----------
    constructor(
        uint256 _minInterval,
        uint256 _maxInterval,
        uint256 _minReward,
        uint256 _keeperStake
    )
        Ownable() ReentrancyGuard() Pausable()
    {
        require(_minInterval >= 60, "Min interval 60s");
        require(_maxInterval >= _minInterval, "Max must >= min");
        minInterval = _minInterval;
        maxInterval = _maxInterval;
        minRewardPerExecution = _minReward;
        keeperStakeRequired = _keeperStake;
        nextJobId = 1;
    }

    /**
     * @notice Register as a keeper with a stake
     */
    function registerKeeper() external payable whenNotPaused {
        require(!keepers[msg.sender].registered, "Already registered");
        require(msg.value >= keeperStakeRequired, "Insufficient stake");

        keepers[msg.sender] = KeeperInfo({
            keeper: msg.sender,
            totalExecutions: 0,
            totalEarned: 0,
            lastActive: block.timestamp,
            registered: true
        });
        keeperStakes[msg.sender] = msg.value;

        emit KeeperRegistered(msg.sender, msg.value);
    }

    /**
     * @notice Create a scheduled job
     * @param target Contract to call
     * @param callData Encoded function call data
     * @param interval Seconds between executions
     * @param startTime When the job should first execute
     * @param maxExecutions Maximum number of executions (0 = unlimited)
     * @return jobId The created job ID
     */
    function createJob(
        address target,
        bytes calldata callData,
        uint256 interval,
        uint256 startTime,
        uint256 maxExecutions
    )
        external
        payable
        whenNotPaused
        returns (uint256 jobId)
    {
        require(target != address(0), "Zero target");
        require(callData.length > 0, "Empty calldata");
        require(interval >= minInterval && interval <= maxInterval, "Interval out of range");
        require(startTime >= block.timestamp, "Start in the past");
        require(msg.value > 0, "Deposit required");

        uint256 rewardPerExec;
        if (maxExecutions > 0) {
            rewardPerExec = msg.value / maxExecutions;
            require(rewardPerExec >= minRewardPerExecution, "Reward per execution too low");
        } else {
            rewardPerExec = minRewardPerExecution;
            require(msg.value >= rewardPerExec * 10, "Min deposit for 10 executions");
        }

        jobId = nextJobId++;
        Job storage j = jobs[jobId];
        j.id = jobId;
        j.creator = msg.sender;
        j.target = target;
        j.callData = callData;
        j.interval = interval;
        j.startTime = startTime;
        j.maxExecutions = maxExecutions;
        j.nextExecutionAt = startTime;
        j.deposit = msg.value;
        j.rewardPerExecution = rewardPerExec;
        j.status = JobStatus.Active;
        j.createdAt = block.timestamp;

        creatorJobs[msg.sender].push(jobId);
        totalActiveJobs++;

        emit JobCreated(jobId, msg.sender, target, interval, maxExecutions);
    }

    /**
     * @notice Execute a job (keeper only)
     * @param jobId The job to execute
     */
    function executeJob(uint256 jobId) external nonReentrant whenNotPaused {
        require(keepers[msg.sender].registered, "Not a registered keeper");

        Job storage j = jobs[jobId];
        require(j.status == JobStatus.Active, "Job not active");
        require(block.timestamp >= j.nextExecutionAt, "Not yet due");
        require(j.deposit >= j.rewardPerExecution, "Insufficient job funds");

        if (j.maxExecutions > 0) {
            require(j.executionCount < j.maxExecutions, "Max executions reached");
        }

        // Execute the call
        (bool success, ) = j.target.call(j.callData);

        j.executionCount++;
        j.lastExecutedAt = block.timestamp;
        j.nextExecutionAt = block.timestamp + j.interval;
        j.deposit -= j.rewardPerExecution;
        lastExecutor[jobId] = msg.sender;
        totalExecutions++;

        // Update keeper stats
        KeeperInfo storage ki = keepers[msg.sender];
        ki.totalExecutions++;
        ki.totalEarned += j.rewardPerExecution;
        ki.lastActive = block.timestamp;

        // Pay keeper
        (bool paid, ) = msg.sender.call{value: j.rewardPerExecution}("");
        require(paid, "Keeper payment failed");

        // Check if job completed
        if (j.maxExecutions > 0 && j.executionCount >= j.maxExecutions) {
            j.status = JobStatus.Completed;
            totalActiveJobs--;
            // Refund remaining deposit
            if (j.deposit > 0) {
                uint256 refund = j.deposit;
                j.deposit = 0;
                (bool ok, ) = j.creator.call{value: refund}("");
                require(ok, "Refund failed");
            }
        }

        emit JobExecuted(jobId, msg.sender, j.executionCount, success);
        emit KeeperRewarded(msg.sender, j.rewardPerExecution);
    }

    /**
     * @notice Pause a job
     * @param jobId The job to pause
     */
    function pauseJob(uint256 jobId) external {
        Job storage j = jobs[jobId];
        require(j.creator == msg.sender || msg.sender == owner(), "Not authorized");
        require(j.status == JobStatus.Active, "Not active");
        j.status = JobStatus.Paused;
        totalActiveJobs--;
        emit JobPaused(jobId);
    }

    /**
     * @notice Resume a paused job
     * @param jobId The job to resume
     */
    function resumeJob(uint256 jobId) external {
        Job storage j = jobs[jobId];
        require(j.creator == msg.sender || msg.sender == owner(), "Not authorized");
        require(j.status == JobStatus.Paused, "Not paused");
        j.status = JobStatus.Active;
        j.nextExecutionAt = block.timestamp + j.interval;
        totalActiveJobs++;
        emit JobResumed(jobId);
    }

    /**
     * @notice Cancel a job and refund remaining deposit
     * @param jobId The job to cancel
     */
    function cancelJob(uint256 jobId) external nonReentrant {
        Job storage j = jobs[jobId];
        require(j.creator == msg.sender, "Not job creator");
        require(j.status == JobStatus.Active || j.status == JobStatus.Paused, "Cannot cancel");

        if (j.status == JobStatus.Active) totalActiveJobs--;
        j.status = JobStatus.Cancelled;

        uint256 refund = j.deposit;
        j.deposit = 0;
        if (refund > 0) {
            (bool ok, ) = msg.sender.call{value: refund}("");
            require(ok, "Refund failed");
        }

        emit JobCancelled(jobId, refund);
    }

    /**
     * @notice Top up a job's deposit
     * @param jobId The job to fund
     */
    function topUpJob(uint256 jobId) external payable {
        Job storage j = jobs[jobId];
        require(j.status == JobStatus.Active || j.status == JobStatus.Paused, "Job not fundable");
        require(msg.value > 0, "Zero amount");
        j.deposit += msg.value;
    }

    /**
     * @notice Check if a job is due for execution
     * @param jobId The job to check
     * @return due Whether the job is ready
     * @return nextExec Next execution timestamp
     */
    function isJobDue(uint256 jobId) external view returns (bool due, uint256 nextExec) {
        Job storage j = jobs[jobId];
        nextExec = j.nextExecutionAt;
        due = (j.status == JobStatus.Active && block.timestamp >= j.nextExecutionAt && j.deposit >= j.rewardPerExecution);
        if (j.maxExecutions > 0 && j.executionCount >= j.maxExecutions) due = false;
    }

    // ---------- View ----------
    function getCreatorJobs(address creator) external view returns (uint256[] memory) {
        return creatorJobs[creator];
    }

    function getKeeperInfo(address keeper) external view returns (KeeperInfo memory) {
        return keepers[keeper];
    }

    function setMinReward(uint256 _min) external onlyOwner { minRewardPerExecution = _min; }
    function setKeeperStake(uint256 _stake) external onlyOwner { keeperStakeRequired = _stake; }
}
