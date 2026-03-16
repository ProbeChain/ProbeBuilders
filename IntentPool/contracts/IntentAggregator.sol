// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IntentAggregator
 * @author ProbeChain Rydberg Testnet
 * @notice Intent aggregation and batch execution for gas-efficient intent settlement
 * @dev Aggregates multiple intents into batches, solvers execute batches for efficiency
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

contract IntentAggregator is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum IntentType { Swap, Bridge, Stake, Lend, Custom }
    enum IntentStatus { Pending, Batched, Executed, Settled, Refunded }
    enum BatchStatus { Open, Closed, Executed, Settled }

    // ---------- Structs ----------
    struct Intent {
        uint256 id;
        address user;
        IntentType intentType;
        bytes32 params;
        uint256 maxCost;
        uint256 deposit;
        IntentStatus status;
        uint256 batchId;
        uint256 submittedAt;
    }

    struct Batch {
        uint256 id;
        uint256[] intentIds;
        BatchStatus status;
        address solver;
        bytes32 solution;
        uint256 totalDeposit;
        uint256 createdAt;
        uint256 executedAt;
        uint256 settledAt;
    }

    // ---------- State ----------
    uint256 public nextIntentId;
    uint256 public nextBatchId;
    uint256 public minBatchSize;
    uint256 public maxBatchSize;
    uint256 public solverFeeBPS;

    mapping(uint256 => Intent) public intents;
    mapping(uint256 => Batch) public batches;
    mapping(address => uint256[]) public userIntents;
    mapping(address => bool) public registeredSolvers;
    mapping(address => uint256) public solverBonded;

    // ---------- Events ----------
    /// @notice Emitted when an intent is submitted
    event IntentSubmitted(uint256 indexed intentId, address indexed user, IntentType intentType, uint256 maxCost);
    /// @notice Emitted when intents are batched together
    event IntentsBatched(uint256 indexed batchId, uint256[] intentIds, uint256 totalDeposit);
    /// @notice Emitted when a batch is executed by a solver
    event BatchExecuted(uint256 indexed batchId, address indexed solver, bytes32 solution);
    /// @notice Emitted when a batch is settled and funds distributed
    event BatchSettled(uint256 indexed batchId, uint256 solverPayment, uint256 refundTotal);
    /// @notice Emitted when a solver registers
    event SolverRegistered(address indexed solver, uint256 bond);
    /// @notice Emitted when an intent is refunded
    event IntentRefunded(uint256 indexed intentId, address indexed user, uint256 amount);

    // ---------- Constructor ----------
    constructor(uint256 _minBatch, uint256 _maxBatch, uint256 _feeBPS)
        Ownable() ReentrancyGuard() Pausable()
    {
        require(_minBatch >= 2, "Min batch must be >= 2");
        require(_maxBatch >= _minBatch, "Max batch must >= min");
        require(_feeBPS <= 1000, "Fee too high");
        minBatchSize = _minBatch;
        maxBatchSize = _maxBatch;
        solverFeeBPS = _feeBPS;
        nextIntentId = 1;
        nextBatchId = 1;
    }

    /**
     * @notice Register as a solver with a bond
     */
    function registerSolver() external payable whenNotPaused {
        require(msg.value > 0, "Bond required");
        require(!registeredSolvers[msg.sender], "Already registered");
        registeredSolvers[msg.sender] = true;
        solverBonded[msg.sender] = msg.value;
        emit SolverRegistered(msg.sender, msg.value);
    }

    /**
     * @notice Submit an intent for aggregation
     * @param intentType The type of intent
     * @param params Encoded parameters hash
     * @param maxCost Maximum cost the user accepts
     * @return intentId The created intent ID
     */
    function submitIntent(IntentType intentType, bytes32 params, uint256 maxCost)
        external
        payable
        whenNotPaused
        returns (uint256 intentId)
    {
        require(params != bytes32(0), "Empty params");
        require(msg.value > 0, "Deposit required");
        require(msg.value <= maxCost, "Deposit exceeds maxCost");

        intentId = nextIntentId++;
        Intent storage i = intents[intentId];
        i.id = intentId;
        i.user = msg.sender;
        i.intentType = intentType;
        i.params = params;
        i.maxCost = maxCost;
        i.deposit = msg.value;
        i.status = IntentStatus.Pending;
        i.submittedAt = block.timestamp;

        userIntents[msg.sender].push(intentId);
        emit IntentSubmitted(intentId, msg.sender, intentType, maxCost);
    }

    /**
     * @notice Batch multiple pending intents together
     * @param intentIds Array of intent IDs to batch
     * @return batchId The created batch ID
     */
    function batchIntents(uint256[] calldata intentIds)
        external
        onlyOwner
        whenNotPaused
        returns (uint256 batchId)
    {
        require(intentIds.length >= minBatchSize, "Below min batch size");
        require(intentIds.length <= maxBatchSize, "Exceeds max batch size");

        batchId = nextBatchId++;
        Batch storage b = batches[batchId];
        b.id = batchId;
        b.status = BatchStatus.Open;
        b.createdAt = block.timestamp;

        uint256 totalDep;
        for (uint256 j = 0; j < intentIds.length; j++) {
            Intent storage i = intents[intentIds[j]];
            require(i.status == IntentStatus.Pending, "Intent not pending");
            i.status = IntentStatus.Batched;
            i.batchId = batchId;
            totalDep += i.deposit;
        }

        b.intentIds = intentIds;
        b.totalDeposit = totalDep;

        emit IntentsBatched(batchId, intentIds, totalDep);
    }

    /**
     * @notice Solver executes a batch
     * @param batchId The batch to execute
     * @param solution Hash of the execution solution
     */
    function executeBatch(uint256 batchId, bytes32 solution) external whenNotPaused {
        require(registeredSolvers[msg.sender], "Not a solver");
        Batch storage b = batches[batchId];
        require(b.status == BatchStatus.Open, "Batch not open");
        require(solution != bytes32(0), "Empty solution");

        b.status = BatchStatus.Executed;
        b.solver = msg.sender;
        b.solution = solution;
        b.executedAt = block.timestamp;

        for (uint256 j = 0; j < b.intentIds.length; j++) {
            intents[b.intentIds[j]].status = IntentStatus.Executed;
        }

        emit BatchExecuted(batchId, msg.sender, solution);
    }

    /**
     * @notice Settle a batch, distributing payments
     * @param batchId The batch to settle
     */
    function settleBatch(uint256 batchId) external nonReentrant onlyOwner {
        Batch storage b = batches[batchId];
        require(b.status == BatchStatus.Executed, "Batch not executed");

        b.status = BatchStatus.Settled;
        b.settledAt = block.timestamp;

        uint256 solverPayment = (b.totalDeposit * solverFeeBPS) / 10000;
        uint256 remaining = b.totalDeposit - solverPayment;

        // Pay solver
        (bool ok, ) = b.solver.call{value: solverPayment}("");
        require(ok, "Solver payment failed");

        // Refund remaining proportionally
        uint256 refundTotal;
        for (uint256 j = 0; j < b.intentIds.length; j++) {
            Intent storage i = intents[b.intentIds[j]];
            uint256 refund = (i.deposit * remaining) / b.totalDeposit;
            i.status = IntentStatus.Settled;
            if (refund > 0) {
                refundTotal += refund;
                (bool ok2, ) = i.user.call{value: refund}("");
                require(ok2, "Refund failed");
            }
        }

        emit BatchSettled(batchId, solverPayment, refundTotal);
    }

    /**
     * @notice Cancel a pending intent and refund
     * @param intentId The intent to cancel
     */
    function cancelIntent(uint256 intentId) external nonReentrant {
        Intent storage i = intents[intentId];
        require(i.user == msg.sender, "Not intent owner");
        require(i.status == IntentStatus.Pending, "Cannot cancel");

        i.status = IntentStatus.Refunded;
        (bool ok, ) = msg.sender.call{value: i.deposit}("");
        require(ok, "Refund failed");
        emit IntentRefunded(intentId, msg.sender, i.deposit);
    }

    // ---------- View Functions ----------
    /**
     * @notice Get intents in a batch
     * @param batchId The batch to query
     * @return Array of intent IDs
     */
    function getBatchIntents(uint256 batchId) external view returns (uint256[] memory) {
        return batches[batchId].intentIds;
    }

    /**
     * @notice Get user's intents
     * @param user The user address
     * @return Array of intent IDs
     */
    function getUserIntents(address user) external view returns (uint256[] memory) {
        return userIntents[user];
    }

    /// @notice Update solver fee
    function setSolverFeeBPS(uint256 _feeBPS) external onlyOwner {
        require(_feeBPS <= 1000, "Fee too high");
        solverFeeBPS = _feeBPS;
    }
}
