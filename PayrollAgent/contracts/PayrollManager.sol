// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title PayrollManager
 * @author ProbeChain Labs
 * @notice Crypto payroll system with batch payments, multi-token support,
 *         and configurable pay frequencies.
 * @dev Designed for ProbeChain Rydberg Testnet (Chain ID 8004, EVM London).
 */

// ---------------------------------------------------------------------------
// Inline: Ownable
// ---------------------------------------------------------------------------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ---------------------------------------------------------------------------
// Inline: ReentrancyGuard
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Inline: Pausable
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Minimal ERC-20 interface
// ---------------------------------------------------------------------------
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

// ---------------------------------------------------------------------------
// Main Contract
// ---------------------------------------------------------------------------
contract PayrollManager is Ownable, ReentrancyGuard, Pausable {
    enum PayFrequency { Weekly, Biweekly, Monthly }

    struct Employee {
        uint256 id;
        address wallet;
        uint256 salary;            // per-period amount
        address token;             // address(0) = native PROBE
        PayFrequency payFrequency;
        uint256 lastPaidAt;
        bool active;
        uint256 addedAt;
    }

    struct PayrollBatch {
        uint256 batchId;
        uint256[] employeeIds;
        uint256 totalPaid;
        uint256 processedAt;
    }

    uint256 private _nextEmployeeId;
    uint256 private _nextBatchId;

    mapping(uint256 => Employee) public employees;
    mapping(address => uint256) public walletToEmployeeId;
    mapping(uint256 => PayrollBatch) public batches;

    uint256 public totalEmployees;
    uint256 public activeEmployees;

    // ---- Events ----------------------------------------------------------
    event EmployeeAdded(uint256 indexed employeeId, address indexed wallet, uint256 salary, address token, PayFrequency payFrequency);
    event EmployeeRemoved(uint256 indexed employeeId, address indexed wallet);
    event SalaryUpdated(uint256 indexed employeeId, uint256 oldSalary, uint256 newSalary);
    event PayrollProcessed(uint256 indexed batchId, uint256 employeeCount, uint256 totalPaid);
    event EmployeePaid(uint256 indexed batchId, uint256 indexed employeeId, address indexed wallet, uint256 amount, address token);

    constructor() {
        _nextEmployeeId = 1;
        _nextBatchId = 1;
    }

    // ---- Employee Management ---------------------------------------------

    /**
     * @notice Add a new employee to the payroll.
     * @param wallet       Employee wallet address.
     * @param salary       Salary amount per pay period.
     * @param token        Payment token (address(0) for native PROBE).
     * @param payFrequency Payment frequency enum.
     * @return employeeId  The new employee identifier.
     */
    function addEmployee(
        address wallet,
        uint256 salary,
        address token,
        PayFrequency payFrequency
    ) external onlyOwner whenNotPaused returns (uint256 employeeId) {
        require(wallet != address(0), "Zero address");
        require(salary > 0, "Zero salary");
        require(walletToEmployeeId[wallet] == 0, "Already registered");

        employeeId = _nextEmployeeId++;
        employees[employeeId] = Employee({
            id: employeeId,
            wallet: wallet,
            salary: salary,
            token: token,
            payFrequency: payFrequency,
            lastPaidAt: block.timestamp,
            active: true,
            addedAt: block.timestamp
        });

        walletToEmployeeId[wallet] = employeeId;
        totalEmployees++;
        activeEmployees++;

        emit EmployeeAdded(employeeId, wallet, salary, token, payFrequency);
    }

    /**
     * @notice Remove an employee from the payroll.
     * @param employeeId The employee to remove.
     */
    function removeEmployee(uint256 employeeId) external onlyOwner {
        Employee storage e = employees[employeeId];
        require(e.id != 0, "Employee not found");
        require(e.active, "Already removed");

        e.active = false;
        activeEmployees--;

        emit EmployeeRemoved(employeeId, e.wallet);
    }

    /**
     * @notice Update an employee's salary.
     * @param employeeId The employee to update.
     * @param newSalary  The new salary amount.
     */
    function updateSalary(uint256 employeeId, uint256 newSalary) external onlyOwner {
        Employee storage e = employees[employeeId];
        require(e.id != 0 && e.active, "Invalid employee");
        require(newSalary > 0, "Zero salary");

        uint256 oldSalary = e.salary;
        e.salary = newSalary;

        emit SalaryUpdated(employeeId, oldSalary, newSalary);
    }

    // ---- Payroll Processing ----------------------------------------------

    /**
     * @notice Process payroll for a batch of employees.
     * @param employeeIds Array of employee IDs to pay.
     */
    function processPayroll(
        uint256[] calldata employeeIds
    ) external payable onlyOwner nonReentrant whenNotPaused {
        require(employeeIds.length > 0, "Empty batch");

        uint256 batchId = _nextBatchId++;
        uint256 totalPaid;

        for (uint256 i = 0; i < employeeIds.length; i++) {
            Employee storage e = employees[employeeIds[i]];
            require(e.id != 0 && e.active, "Invalid employee in batch");
            require(_isPaymentDue(e), "Payment not due");

            e.lastPaidAt = block.timestamp;

            if (e.token == address(0)) {
                // Native PROBE payment
                (bool success, ) = payable(e.wallet).call{value: e.salary}("");
                require(success, "Native transfer failed");
            } else {
                // ERC-20 payment (contract must hold tokens)
                bool ok = IERC20(e.token).transfer(e.wallet, e.salary);
                require(ok, "Token transfer failed");
            }

            totalPaid += e.salary;
            emit EmployeePaid(batchId, e.id, e.wallet, e.salary, e.token);
        }

        batches[batchId] = PayrollBatch({
            batchId: batchId,
            employeeIds: employeeIds,
            totalPaid: totalPaid,
            processedAt: block.timestamp
        });

        emit PayrollProcessed(batchId, employeeIds.length, totalPaid);
    }

    // ---- Internal --------------------------------------------------------

    function _isPaymentDue(Employee storage e) internal view returns (bool) {
        uint256 interval;
        if (e.payFrequency == PayFrequency.Weekly) {
            interval = 7 days;
        } else if (e.payFrequency == PayFrequency.Biweekly) {
            interval = 14 days;
        } else {
            interval = 30 days;
        }
        return block.timestamp >= e.lastPaidAt + interval;
    }

    // ---- Views -----------------------------------------------------------

    function getEmployee(uint256 employeeId) external view returns (Employee memory) {
        require(employees[employeeId].id != 0, "Not found");
        return employees[employeeId];
    }

    function getBatch(uint256 batchId) external view returns (uint256, uint256[] memory, uint256, uint256) {
        PayrollBatch memory b = batches[batchId];
        return (b.batchId, b.employeeIds, b.totalPaid, b.processedAt);
    }

    function isPaymentDue(uint256 employeeId) external view returns (bool) {
        Employee storage e = employees[employeeId];
        require(e.id != 0 && e.active, "Invalid employee");
        return _isPaymentDue(e);
    }

    // ---- Funding ---------------------------------------------------------

    /// @notice Fund the contract for native PROBE payroll.
    receive() external payable {}

    /// @notice Owner withdraws excess funds.
    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Withdraw failed");
    }
}
