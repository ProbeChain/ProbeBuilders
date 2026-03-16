// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TreasuryManager
 * @author ProbeChain Team
 * @notice Multi-sig treasury management with council-approved spending on ProbeChain
 * @dev Deposit, propose, approve, and execute treasury spending with budget tracking
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

contract TreasuryManager is Ownable, ReentrancyGuard, Pausable {
    enum SpendStatus { Proposed, Approved, Executed, Rejected }

    /// @notice Spending proposal
    struct SpendProposal {
        uint256 id;
        address proposer;
        address recipient;
        uint256 amount;
        string reason;
        SpendStatus status;
        uint256 approvals;
        uint256 createdAt;
        uint256 executedAt;
    }

    /// @notice Budget period
    struct Budget {
        uint256 totalAllocated;
        uint256 totalSpent;
        uint256 periodStart;
        uint256 periodEnd;
    }

    mapping(uint256 => SpendProposal) private _proposals;
    mapping(uint256 => mapping(address => bool)) private _hasApproved;
    mapping(address => bool) private _councilMembers;
    mapping(address => uint256) private _deposits;

    uint256 private _nextProposalId = 1;
    uint256 public councilSize;
    uint256 public requiredApprovals = 2;
    uint256 public totalDeposited;
    uint256 public totalSpent;
    Budget public currentBudget;

    /// @notice Emitted on deposit
    event Deposited(address indexed depositor, uint256 amount);
    /// @notice Emitted when spend is proposed
    event SpendProposed(uint256 indexed spendId, address indexed recipient, uint256 amount, string reason);
    /// @notice Emitted when spend is approved
    event SpendApproved(uint256 indexed spendId, address indexed approver);
    /// @notice Emitted when spend is executed
    event SpendExecuted(uint256 indexed spendId, address indexed recipient, uint256 amount);
    /// @notice Emitted when spend is rejected
    event SpendRejected(uint256 indexed spendId);
    /// @notice Emitted when council member is updated
    event CouncilMemberUpdated(address indexed member, bool active);
    /// @notice Emitted when budget is set
    event BudgetSet(uint256 totalAllocated, uint256 periodStart, uint256 periodEnd);

    error NotCouncilMember(address caller);
    error ProposalNotFound(uint256 spendId);
    error ProposalNotApproved(uint256 spendId);
    error ProposalNotProposed(uint256 spendId);
    error AlreadyApproved(address approver, uint256 spendId);
    error InsufficientBalance(uint256 available, uint256 required);
    error BudgetExceeded(uint256 remaining, uint256 requested);
    error ZeroAmount();

    modifier onlyCouncil() {
        if (!_councilMembers[msg.sender] && msg.sender != owner()) revert NotCouncilMember(msg.sender);
        _;
    }

    constructor() {
        _councilMembers[msg.sender] = true;
        councilSize = 1;
    }

    /**
     * @notice Deposit funds into the treasury
     */
    function deposit() external payable whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        _deposits[msg.sender] += msg.value;
        totalDeposited += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @notice Propose a treasury spend
     * @param recipient The spending recipient
     * @param amount The amount to spend
     * @param reason The reason for spending
     * @return spendId The proposal ID
     */
    function proposeSpend(
        address recipient,
        uint256 amount,
        string calldata reason
    ) external whenNotPaused onlyCouncil returns (uint256 spendId) {
        if (amount == 0) revert ZeroAmount();
        if (amount > address(this).balance) revert InsufficientBalance(address(this).balance, amount);

        // Check budget if set
        if (currentBudget.periodEnd > block.timestamp) {
            uint256 remaining = currentBudget.totalAllocated - currentBudget.totalSpent;
            if (amount > remaining) revert BudgetExceeded(remaining, amount);
        }

        spendId = _nextProposalId++;
        _proposals[spendId] = SpendProposal({
            id: spendId,
            proposer: msg.sender,
            recipient: recipient,
            amount: amount,
            reason: reason,
            status: SpendStatus.Proposed,
            approvals: 0,
            createdAt: block.timestamp,
            executedAt: 0
        });

        emit SpendProposed(spendId, recipient, amount, reason);
    }

    /**
     * @notice Approve a spending proposal (council members)
     * @param spendId The proposal to approve
     */
    function approveSpend(uint256 spendId) external whenNotPaused onlyCouncil {
        SpendProposal storage p = _proposals[spendId];
        if (p.id == 0) revert ProposalNotFound(spendId);
        if (p.status != SpendStatus.Proposed) revert ProposalNotProposed(spendId);
        if (_hasApproved[spendId][msg.sender]) revert AlreadyApproved(msg.sender, spendId);

        _hasApproved[spendId][msg.sender] = true;
        p.approvals++;

        if (p.approvals >= requiredApprovals) {
            p.status = SpendStatus.Approved;
        }

        emit SpendApproved(spendId, msg.sender);
    }

    /**
     * @notice Execute an approved spending proposal
     * @param spendId The proposal to execute
     */
    function executeSpend(uint256 spendId) external nonReentrant whenNotPaused onlyCouncil {
        SpendProposal storage p = _proposals[spendId];
        if (p.id == 0) revert ProposalNotFound(spendId);
        if (p.status != SpendStatus.Approved) revert ProposalNotApproved(spendId);
        if (p.amount > address(this).balance) revert InsufficientBalance(address(this).balance, p.amount);

        p.status = SpendStatus.Executed;
        p.executedAt = block.timestamp;
        totalSpent += p.amount;

        if (currentBudget.periodEnd > block.timestamp) {
            currentBudget.totalSpent += p.amount;
        }

        (bool success, ) = p.recipient.call{value: p.amount}("");
        require(success, "Transfer failed");

        emit SpendExecuted(spendId, p.recipient, p.amount);
    }

    /**
     * @notice Reject a spending proposal
     * @param spendId The proposal to reject
     */
    function rejectSpend(uint256 spendId) external onlyCouncil {
        SpendProposal storage p = _proposals[spendId];
        if (p.id == 0) revert ProposalNotFound(spendId);
        if (p.status != SpendStatus.Proposed) revert ProposalNotProposed(spendId);
        p.status = SpendStatus.Rejected;
        emit SpendRejected(spendId);
    }

    /**
     * @notice Get treasury balance
     * @return balance The current balance
     */
    function getBalance() external view returns (uint256 balance) {
        return address(this).balance;
    }

    /**
     * @notice Get current budget info
     * @return budget The current budget
     */
    function getBudget() external view returns (Budget memory budget) {
        return currentBudget;
    }

    /**
     * @notice Get proposal details
     * @param spendId The proposal ID
     * @return proposal The proposal data
     */
    function getProposal(uint256 spendId) external view returns (SpendProposal memory proposal) {
        if (_proposals[spendId].id == 0) revert ProposalNotFound(spendId);
        return _proposals[spendId];
    }

    /// @notice Set budget period
    function setBudget(uint256 totalAllocated, uint256 periodStart, uint256 periodEnd) external onlyOwner {
        currentBudget = Budget({
            totalAllocated: totalAllocated,
            totalSpent: 0,
            periodStart: periodStart,
            periodEnd: periodEnd
        });
        emit BudgetSet(totalAllocated, periodStart, periodEnd);
    }

    /// @notice Add or remove council member
    function setCouncilMember(address member, bool active) external onlyOwner {
        if (_councilMembers[member] != active) {
            _councilMembers[member] = active;
            councilSize = active ? councilSize + 1 : councilSize - 1;
            emit CouncilMemberUpdated(member, active);
        }
    }

    /// @notice Check if address is council member
    function isCouncilMember(address addr) external view returns (bool) { return _councilMembers[addr]; }

    /// @notice Set required approvals
    function setRequiredApprovals(uint256 count) external onlyOwner {
        require(count > 0 && count <= councilSize, "Invalid count");
        requiredApprovals = count;
    }

    receive() external payable {
        totalDeposited += msg.value;
        emit Deposited(msg.sender, msg.value);
    }
}
