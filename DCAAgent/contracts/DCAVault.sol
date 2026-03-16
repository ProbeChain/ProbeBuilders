// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title DCAVault
 * @author ProbeBuilders
 * @notice Dollar-cost averaging agent vault for ProbeChain Rydberg Testnet.
 *         Users create recurring buy plans; authorized keepers execute them on schedule.
 * @dev Inline Ownable, ReentrancyGuard, Pausable. EVM London compatible.
 */

/* ───────── Minimal Interfaces ───────── */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/* ───────── Abstract helpers (inlined) ───────── */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed prev, address indexed next_);
    error OwnableUnauthorized();
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorized(); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardLocked();
    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardLocked();
        _status = 2;
        _;
        _status = 1;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();
    modifier whenNotPaused() { if (_paused) revert ContractPaused(); _; }
    modifier whenPaused() { if (!_paused) revert ContractNotPaused(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

/* ───────── Main Contract ───────── */

contract DCAVault is Ownable, ReentrancyGuard, Pausable {

    /* ── Structs ── */

    /// @notice A dollar-cost averaging plan
    struct Plan {
        address creator;
        address token;          // ERC-20 token to purchase
        uint256 amountPerCycle; // spend amount in native currency per cycle
        uint256 interval;       // seconds between executions
        uint256 totalCycles;    // total number of cycles
        uint256 executedCycles; // cycles already executed
        uint256 lastExecution;  // timestamp of last execution
        bool    active;
    }

    /// @notice Execution record
    struct Execution {
        uint256 timestamp;
        uint256 amountSpent;
        uint256 tokensReceived;
    }

    /* ── State ── */

    uint256 public nextPlanId;
    mapping(uint256 => Plan) public plans;
    mapping(uint256 => Execution[]) private _history;
    mapping(address => bool) public keepers;
    mapping(address => uint256[]) private _userPlans;

    /* ── Events ── */

    /// @notice Emitted when a new DCA plan is created
    event PlanCreated(uint256 indexed planId, address indexed creator, address token, uint256 amountPerCycle, uint256 interval, uint256 totalCycles);
    /// @notice Emitted when a DCA cycle is executed
    event DCAExecuted(uint256 indexed planId, uint256 cycle, uint256 amountSpent, uint256 tokensReceived);
    /// @notice Emitted when a plan is cancelled
    event PlanCancelled(uint256 indexed planId);
    /// @notice Emitted when remaining funds are withdrawn
    event FundsWithdrawn(uint256 indexed planId, uint256 amount);
    /// @notice Emitted when a keeper is added or removed
    event KeeperUpdated(address indexed keeper, bool status);

    /* ── Errors ── */

    error NotKeeper();
    error PlanNotActive();
    error TooEarly();
    error CyclesComplete();
    error NotPlanOwner();
    error InsufficientDeposit();
    error TransferFailed();

    /* ── Modifiers ── */

    modifier onlyKeeper() {
        if (!keepers[msg.sender] && msg.sender != owner()) revert NotKeeper();
        _;
    }

    /* ── Constructor ── */

    constructor() Ownable() {
        keepers[msg.sender] = true;
    }

    /* ── Keeper management ── */

    /// @notice Add or remove a keeper address
    /// @param keeper The address to update
    /// @param status true to authorize, false to revoke
    function setKeeper(address keeper, bool status) external onlyOwner {
        keepers[keeper] = status;
        emit KeeperUpdated(keeper, status);
    }

    /* ── Core functions ── */

    /**
     * @notice Create a new DCA plan. Deposit native currency to fund the plan.
     * @param token ERC-20 token address to purchase
     * @param amountPerCycle Amount of native currency to spend per cycle
     * @param interval Seconds between cycles
     * @param totalCycles Total number of buy cycles
     * @return planId The ID of the newly created plan
     */
    function createPlan(
        address token,
        uint256 amountPerCycle,
        uint256 interval,
        uint256 totalCycles
    ) external payable whenNotPaused returns (uint256 planId) {
        require(token != address(0), "zero token");
        require(amountPerCycle > 0, "zero amount");
        require(interval >= 60, "interval too short");
        require(totalCycles > 0, "zero cycles");

        uint256 totalRequired = amountPerCycle * totalCycles;
        if (msg.value < totalRequired) revert InsufficientDeposit();

        planId = nextPlanId++;
        plans[planId] = Plan({
            creator: msg.sender,
            token: token,
            amountPerCycle: amountPerCycle,
            interval: interval,
            totalCycles: totalCycles,
            executedCycles: 0,
            lastExecution: 0,
            active: true
        });

        _userPlans[msg.sender].push(planId);

        // refund excess
        if (msg.value > totalRequired) {
            (bool ok, ) = msg.sender.call{value: msg.value - totalRequired}("");
            if (!ok) revert TransferFailed();
        }

        emit PlanCreated(planId, msg.sender, token, amountPerCycle, interval, totalCycles);
    }

    /**
     * @notice Execute the next DCA cycle for a plan. Called by keepers.
     * @dev In production this would swap via a DEX; here we simulate by
     *      transferring tokens from the vault's token balance to the plan creator.
     * @param planId The plan to execute
     */
    function executeDCA(uint256 planId) external onlyKeeper nonReentrant whenNotPaused {
        Plan storage plan = plans[planId];
        if (!plan.active) revert PlanNotActive();
        if (plan.executedCycles >= plan.totalCycles) revert CyclesComplete();
        if (plan.lastExecution != 0 && block.timestamp < plan.lastExecution + plan.interval) revert TooEarly();

        plan.executedCycles++;
        plan.lastExecution = block.timestamp;

        // Simulate swap: transfer tokens held by this contract to the creator.
        // In production, integrate with ProSwap or another DEX router.
        uint256 tokenBalance = IERC20(plan.token).balanceOf(address(this));
        uint256 tokensOut = tokenBalance > 0 ? _min(plan.amountPerCycle, tokenBalance) : 0;

        if (tokensOut > 0) {
            bool ok = IERC20(plan.token).transfer(plan.creator, tokensOut);
            if (!ok) revert TransferFailed();
        }

        _history[planId].push(Execution({
            timestamp: block.timestamp,
            amountSpent: plan.amountPerCycle,
            tokensReceived: tokensOut
        }));

        if (plan.executedCycles == plan.totalCycles) {
            plan.active = false;
        }

        emit DCAExecuted(planId, plan.executedCycles, plan.amountPerCycle, tokensOut);
    }

    /**
     * @notice Cancel an active plan
     * @param planId The plan to cancel
     */
    function cancelPlan(uint256 planId) external whenNotPaused {
        Plan storage plan = plans[planId];
        if (plan.creator != msg.sender && msg.sender != owner()) revert NotPlanOwner();
        if (!plan.active) revert PlanNotActive();
        plan.active = false;
        emit PlanCancelled(planId);
    }

    /**
     * @notice Withdraw remaining funds from a cancelled or completed plan
     * @param planId The plan to withdraw from
     */
    function withdrawFunds(uint256 planId) external nonReentrant {
        Plan storage plan = plans[planId];
        if (plan.creator != msg.sender) revert NotPlanOwner();
        if (plan.active) revert PlanNotActive(); // must cancel first

        uint256 remaining = (plan.totalCycles - plan.executedCycles) * plan.amountPerCycle;
        if (remaining == 0) return;

        // zero out to prevent re-withdrawal
        plan.totalCycles = plan.executedCycles;

        (bool ok, ) = msg.sender.call{value: remaining}("");
        if (!ok) revert TransferFailed();

        emit FundsWithdrawn(planId, remaining);
    }

    /* ── View helpers ── */

    /// @notice Get execution history for a plan
    function getHistory(uint256 planId) external view returns (Execution[] memory) {
        return _history[planId];
    }

    /// @notice Get all plan IDs for a user
    function getUserPlans(address user) external view returns (uint256[] memory) {
        return _userPlans[user];
    }

    /// @notice Get remaining cycles for a plan
    function remainingCycles(uint256 planId) external view returns (uint256) {
        Plan storage p = plans[planId];
        return p.active ? p.totalCycles - p.executedCycles : 0;
    }

    /* ── Internal ── */

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Allow contract to receive native currency
    receive() external payable {}
}
