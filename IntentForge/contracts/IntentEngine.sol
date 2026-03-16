// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IntentEngine
 * @author ProbeChain Rydberg Testnet
 * @notice Intent compiler and solver marketplace for user intents
 * @dev Users submit intents, solvers propose execution plans, dispute resolution included
 */

// ---------- Inlined Ownable ----------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
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
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
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

contract IntentEngine is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum IntentStatus { Submitted, Solved, Executed, Disputed, Refunded, Expired }

    // ---------- Structs ----------
    struct Intent {
        uint256 id;
        address user;
        bytes32 userIntent;
        uint256 maxGas;
        uint256 deadline;
        uint256 deposit;
        IntentStatus status;
        uint256 submittedAt;
        address solver;
        bytes32 executionPlan;
        uint256 solvedAt;
        uint256 executedAt;
    }

    struct Dispute {
        uint256 intentId;
        address disputer;
        bytes32 reasonHash;
        bool resolved;
        bool disputerWon;
    }

    // ---------- State ----------
    uint256 public nextIntentId;
    uint256 public solverStakeRequired;
    uint256 public disputeWindow;
    uint256 public protocolFeeBPS;

    mapping(uint256 => Intent) public intents;
    mapping(uint256 => Dispute) public disputes;
    mapping(address => bool) public registeredSolvers;
    mapping(address => uint256) public solverStakes;
    mapping(address => uint256) public solverSuccessCount;
    mapping(address => uint256) public solverDisputeCount;

    // ---------- Events ----------
    /// @notice Emitted when a user submits an intent
    event IntentSubmitted(uint256 indexed intentId, address indexed user, bytes32 userIntent, uint256 deposit, uint256 deadline);
    /// @notice Emitted when a solver proposes an execution plan
    event IntentSolved(uint256 indexed intentId, address indexed solver, bytes32 executionPlan);
    /// @notice Emitted when an intent is executed
    event IntentExecuted(uint256 indexed intentId, address indexed executor);
    /// @notice Emitted when a dispute is raised
    event DisputeRaised(uint256 indexed intentId, address indexed disputer, bytes32 reasonHash);
    /// @notice Emitted when a dispute is resolved
    event DisputeResolved(uint256 indexed intentId, bool disputerWon);
    /// @notice Emitted when a solver registers with stake
    event SolverRegistered(address indexed solver, uint256 stake);
    /// @notice Emitted when an intent is refunded
    event IntentRefunded(uint256 indexed intentId, address indexed user, uint256 amount);

    // ---------- Constructor ----------
    constructor(uint256 _solverStake, uint256 _disputeWindow, uint256 _feeBPS)
        Ownable() ReentrancyGuard() Pausable()
    {
        require(_feeBPS <= 500, "Fee too high");
        solverStakeRequired = _solverStake;
        disputeWindow = _disputeWindow;
        protocolFeeBPS = _feeBPS;
        nextIntentId = 1;
    }

    // ---------- Solver Management ----------
    /**
     * @notice Register as a solver by staking
     */
    function registerSolver() external payable whenNotPaused {
        require(!registeredSolvers[msg.sender], "Already registered");
        require(msg.value >= solverStakeRequired, "Insufficient stake");
        registeredSolvers[msg.sender] = true;
        solverStakes[msg.sender] = msg.value;
        emit SolverRegistered(msg.sender, msg.value);
    }

    // ---------- Core Functions ----------
    /**
     * @notice Submit an intent for solver execution
     * @param userIntent Hash describing the user's desired outcome
     * @param maxGas Maximum gas the user is willing to spend
     * @param deadline Timestamp after which the intent expires
     * @return intentId The created intent identifier
     */
    function submitIntent(bytes32 userIntent, uint256 maxGas, uint256 deadline)
        external
        payable
        whenNotPaused
        returns (uint256 intentId)
    {
        require(userIntent != bytes32(0), "Empty intent");
        require(deadline > block.timestamp, "Deadline in the past");
        require(msg.value > 0, "Deposit required");

        intentId = nextIntentId++;
        Intent storage i = intents[intentId];
        i.id = intentId;
        i.user = msg.sender;
        i.userIntent = userIntent;
        i.maxGas = maxGas;
        i.deadline = deadline;
        i.deposit = msg.value;
        i.status = IntentStatus.Submitted;
        i.submittedAt = block.timestamp;

        emit IntentSubmitted(intentId, msg.sender, userIntent, msg.value, deadline);
    }

    /**
     * @notice Solver proposes an execution plan for an intent
     * @param intentId The intent to solve
     * @param executionPlan Hash of the proposed execution plan
     */
    function solveIntent(uint256 intentId, bytes32 executionPlan) external whenNotPaused {
        require(registeredSolvers[msg.sender], "Not a registered solver");
        Intent storage i = intents[intentId];
        require(i.status == IntentStatus.Submitted, "Intent not solvable");
        require(block.timestamp <= i.deadline, "Intent expired");
        require(executionPlan != bytes32(0), "Empty plan");

        i.solver = msg.sender;
        i.executionPlan = executionPlan;
        i.status = IntentStatus.Solved;
        i.solvedAt = block.timestamp;

        emit IntentSolved(intentId, msg.sender, executionPlan);
    }

    /**
     * @notice Execute a solved intent
     * @param intentId The intent to execute
     */
    function executeIntent(uint256 intentId) external nonReentrant whenNotPaused {
        Intent storage i = intents[intentId];
        require(i.status == IntentStatus.Solved, "Intent not solved");
        require(msg.sender == i.solver, "Only solver can execute");
        require(block.timestamp <= i.deadline, "Intent expired");

        i.status = IntentStatus.Executed;
        i.executedAt = block.timestamp;

        uint256 fee = (i.deposit * protocolFeeBPS) / 10000;
        uint256 solverPayment = i.deposit - fee;

        (bool ok, ) = i.solver.call{value: solverPayment}("");
        require(ok, "Solver payment failed");

        solverSuccessCount[msg.sender]++;

        emit IntentExecuted(intentId, msg.sender);
    }

    /**
     * @notice Dispute a solved or executed intent
     * @param intentId The intent to dispute
     * @param reasonHash Hash of the dispute reason
     */
    function disputeSolution(uint256 intentId, bytes32 reasonHash) external whenNotPaused {
        Intent storage i = intents[intentId];
        require(
            i.status == IntentStatus.Solved || i.status == IntentStatus.Executed,
            "Cannot dispute this intent"
        );
        require(msg.sender == i.user, "Only intent user can dispute");
        require(block.timestamp <= i.executedAt + disputeWindow, "Dispute window closed");

        i.status = IntentStatus.Disputed;
        disputes[intentId] = Dispute({
            intentId: intentId,
            disputer: msg.sender,
            reasonHash: reasonHash,
            resolved: false,
            disputerWon: false
        });

        emit DisputeRaised(intentId, msg.sender, reasonHash);
    }

    /**
     * @notice Owner resolves a dispute
     * @param intentId The disputed intent
     * @param disputerWins Whether the disputer wins
     */
    function resolveDispute(uint256 intentId, bool disputerWins) external onlyOwner nonReentrant {
        Dispute storage d = disputes[intentId];
        require(!d.resolved, "Already resolved");
        Intent storage i = intents[intentId];
        require(i.status == IntentStatus.Disputed, "Not disputed");

        d.resolved = true;
        d.disputerWon = disputerWins;

        if (disputerWins) {
            i.status = IntentStatus.Refunded;
            (bool ok, ) = i.user.call{value: i.deposit}("");
            require(ok, "Refund failed");
            solverDisputeCount[i.solver]++;
            emit IntentRefunded(intentId, i.user, i.deposit);
        } else {
            i.status = IntentStatus.Executed;
        }

        emit DisputeResolved(intentId, disputerWins);
    }

    /**
     * @notice Claim refund for an expired intent
     * @param intentId The expired intent
     */
    function claimExpiredRefund(uint256 intentId) external nonReentrant {
        Intent storage i = intents[intentId];
        require(i.user == msg.sender, "Not intent owner");
        require(i.status == IntentStatus.Submitted, "Not in submitted state");
        require(block.timestamp > i.deadline, "Not expired yet");

        i.status = IntentStatus.Expired;
        (bool ok, ) = msg.sender.call{value: i.deposit}("");
        require(ok, "Refund failed");
        emit IntentRefunded(intentId, msg.sender, i.deposit);
    }

    // ---------- View Functions ----------
    /**
     * @notice Get solver reliability score (basis points)
     * @param solver The solver address
     * @return Score in basis points
     */
    function getSolverScore(address solver) external view returns (uint256) {
        uint256 total = solverSuccessCount[solver] + solverDisputeCount[solver];
        if (total == 0) return 0;
        return (solverSuccessCount[solver] * 10000) / total;
    }

    /// @notice Withdraw accumulated protocol fees
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees");
        (bool ok, ) = owner().call{value: balance}("");
        require(ok, "Withdraw failed");
    }
}
