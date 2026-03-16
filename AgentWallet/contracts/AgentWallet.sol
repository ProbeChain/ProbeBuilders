// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title AgentWallet — Budget-controlled wallet for AI agents on ProbeChain
/// @author ProbeBuilders
/// @notice Deposit funds, set daily spending limits, execute transactions with budget enforcement
/// @dev Implements ReentrancyGuard and Ownable inline. Rydberg Testnet (Chain ID 8004).
contract AgentWallet {
    // ─── ReentrancyGuard ─────────────────────────────────────────────────
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _reentrancyStatus = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_reentrancyStatus != _ENTERED, "AgentWallet: reentrant call");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    // ─── Structs ─────────────────────────────────────────────────────────
    struct WalletConfig {
        address walletOwner;
        uint256 dailyLimit;
        uint256 singleTxLimit;
        uint256 dailySpent;
        uint256 lastResetDay;
        bool frozen;
        uint256 createdAt;
    }

    struct Transaction {
        uint256 id;
        uint256 walletId;
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 executedAt;
    }

    // ─── State ───────────────────────────────────────────────────────────
    address public owner;

    uint256 private _nextWalletId = 1;
    uint256 private _nextTxId = 1;

    mapping(uint256 => WalletConfig) public wallets;
    mapping(uint256 => uint256) public walletBalances;
    mapping(address => uint256[]) private _ownerWallets;
    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => uint256[]) private _walletTransactions;

    // Authorized operators per wallet (agentId => operator => authorized)
    mapping(uint256 => mapping(address => bool)) public authorizedOperators;

    // ─── Events ──────────────────────────────────────────────────────────
    event WalletCreated(uint256 indexed walletId, address indexed walletOwner, uint256 dailyLimit);
    event Deposited(uint256 indexed walletId, address indexed depositor, uint256 amount);
    event TransactionExecuted(uint256 indexed txId, uint256 indexed walletId, address indexed to, uint256 value);
    event TransactionFailed(uint256 indexed txId, uint256 indexed walletId, string reason);
    event SpendingLimitUpdated(uint256 indexed walletId, uint256 oldDailyLimit, uint256 newDailyLimit);
    event SingleTxLimitUpdated(uint256 indexed walletId, uint256 oldLimit, uint256 newLimit);
    event WalletFrozen(uint256 indexed walletId, address indexed freezer);
    event WalletUnfrozen(uint256 indexed walletId, address indexed unfreezer);
    event OperatorUpdated(uint256 indexed walletId, address indexed operator, bool authorized);
    event Withdrawn(uint256 indexed walletId, address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "AgentWallet: not contract owner");
        _;
    }

    modifier onlyWalletOwner(uint256 walletId) {
        require(wallets[walletId].walletOwner == msg.sender, "AgentWallet: not wallet owner");
        _;
    }

    modifier walletExists(uint256 walletId) {
        require(wallets[walletId].createdAt != 0, "AgentWallet: wallet not found");
        _;
    }

    modifier notFrozen(uint256 walletId) {
        require(!wallets[walletId].frozen, "AgentWallet: wallet frozen");
        _;
    }

    modifier onlyAuthorized(uint256 walletId) {
        require(
            wallets[walletId].walletOwner == msg.sender || authorizedOperators[walletId][msg.sender],
            "AgentWallet: not authorized"
        );
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Wallet Management ───────────────────────────────────────────────

    /// @notice Create a new budget-controlled wallet
    /// @param dailyLimit Maximum daily spending in wei
    /// @param singleTxLimit Maximum single transaction value (0 = no per-tx limit)
    /// @return walletId The new wallet ID
    function createWallet(uint256 dailyLimit, uint256 singleTxLimit) external returns (uint256 walletId) {
        require(dailyLimit > 0, "AgentWallet: daily limit must be > 0");

        walletId = _nextWalletId++;

        wallets[walletId] = WalletConfig({
            walletOwner: msg.sender,
            dailyLimit: dailyLimit,
            singleTxLimit: singleTxLimit,
            dailySpent: 0,
            lastResetDay: block.timestamp / 1 days,
            frozen: false,
            createdAt: block.timestamp
        });

        _ownerWallets[msg.sender].push(walletId);

        emit WalletCreated(walletId, msg.sender, dailyLimit);
    }

    /// @notice Deposit funds into a wallet
    /// @param walletId The wallet to fund
    function deposit(uint256 walletId) external payable walletExists(walletId) {
        require(msg.value > 0, "AgentWallet: zero deposit");
        walletBalances[walletId] += msg.value;
        emit Deposited(walletId, msg.sender, msg.value);
    }

    /// @notice Set daily spending limit
    /// @param walletId The wallet to configure
    /// @param newDailyLimit New daily limit in wei
    function setSpendingLimit(uint256 walletId, uint256 newDailyLimit)
        external
        walletExists(walletId)
        onlyWalletOwner(walletId)
    {
        require(newDailyLimit > 0, "AgentWallet: limit must be > 0");
        uint256 old = wallets[walletId].dailyLimit;
        wallets[walletId].dailyLimit = newDailyLimit;
        emit SpendingLimitUpdated(walletId, old, newDailyLimit);
    }

    /// @notice Set per-transaction spending limit
    /// @param walletId The wallet to configure
    /// @param newLimit New single-tx limit (0 = no limit)
    function setSingleTxLimit(uint256 walletId, uint256 newLimit)
        external
        walletExists(walletId)
        onlyWalletOwner(walletId)
    {
        uint256 old = wallets[walletId].singleTxLimit;
        wallets[walletId].singleTxLimit = newLimit;
        emit SingleTxLimitUpdated(walletId, old, newLimit);
    }

    /// @notice Execute a transaction from the wallet
    /// @param walletId The wallet to spend from
    /// @param to Destination address
    /// @param value Amount in wei
    /// @param data Call data (empty for simple transfers)
    /// @return txId The transaction ID
    function executeTransaction(
        uint256 walletId,
        address to,
        uint256 value,
        bytes calldata data
    )
        external
        walletExists(walletId)
        notFrozen(walletId)
        onlyAuthorized(walletId)
        nonReentrant
        returns (uint256 txId)
    {
        require(to != address(0), "AgentWallet: zero address");
        require(value > 0, "AgentWallet: zero value");
        require(walletBalances[walletId] >= value, "AgentWallet: insufficient balance");

        WalletConfig storage w = wallets[walletId];

        // Check single tx limit
        if (w.singleTxLimit > 0) {
            require(value <= w.singleTxLimit, "AgentWallet: exceeds single tx limit");
        }

        // Reset daily counter if new day
        uint256 today = block.timestamp / 1 days;
        if (today > w.lastResetDay) {
            w.dailySpent = 0;
            w.lastResetDay = today;
        }

        // Check daily limit
        require(w.dailySpent + value <= w.dailyLimit, "AgentWallet: exceeds daily limit");

        // Execute
        walletBalances[walletId] -= value;
        w.dailySpent += value;

        txId = _nextTxId++;

        (bool success, ) = to.call{value: value}(data);

        transactions[txId] = Transaction({
            id: txId,
            walletId: walletId,
            to: to,
            value: value,
            data: data,
            executed: success,
            executedAt: block.timestamp
        });

        _walletTransactions[walletId].push(txId);

        if (success) {
            emit TransactionExecuted(txId, walletId, to, value);
        } else {
            // Revert balance changes on failure
            walletBalances[walletId] += value;
            w.dailySpent -= value;
            emit TransactionFailed(txId, walletId, "call failed");
        }
    }

    /// @notice Emergency freeze a wallet
    /// @param walletId The wallet to freeze
    function emergencyFreeze(uint256 walletId) external walletExists(walletId) onlyWalletOwner(walletId) {
        wallets[walletId].frozen = true;
        emit WalletFrozen(walletId, msg.sender);
    }

    /// @notice Unfreeze a wallet
    /// @param walletId The wallet to unfreeze
    function unfreeze(uint256 walletId) external walletExists(walletId) onlyWalletOwner(walletId) {
        wallets[walletId].frozen = false;
        emit WalletUnfrozen(walletId, msg.sender);
    }

    /// @notice Authorize or deauthorize an operator
    /// @param walletId The wallet
    /// @param operator The operator address
    /// @param authorized Whether to authorize
    function setOperator(uint256 walletId, address operator, bool authorized)
        external
        walletExists(walletId)
        onlyWalletOwner(walletId)
    {
        require(operator != address(0), "AgentWallet: zero address");
        authorizedOperators[walletId][operator] = authorized;
        emit OperatorUpdated(walletId, operator, authorized);
    }

    /// @notice Withdraw funds from wallet (owner only)
    /// @param walletId The wallet
    /// @param to Withdrawal destination
    /// @param amount Amount to withdraw
    function withdraw(uint256 walletId, address to, uint256 amount)
        external
        walletExists(walletId)
        onlyWalletOwner(walletId)
        nonReentrant
    {
        require(to != address(0), "AgentWallet: zero address");
        require(amount > 0 && amount <= walletBalances[walletId], "AgentWallet: invalid amount");

        walletBalances[walletId] -= amount;
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "AgentWallet: transfer failed");

        emit Withdrawn(walletId, to, amount);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Get remaining daily budget
    function getRemainingDailyBudget(uint256 walletId) external view walletExists(walletId) returns (uint256) {
        WalletConfig storage w = wallets[walletId];
        uint256 today = block.timestamp / 1 days;
        if (today > w.lastResetDay) return w.dailyLimit;
        if (w.dailySpent >= w.dailyLimit) return 0;
        return w.dailyLimit - w.dailySpent;
    }

    /// @notice Get wallets owned by an address
    function getOwnerWallets(address walletOwner) external view returns (uint256[] memory) {
        return _ownerWallets[walletOwner];
    }

    /// @notice Get transactions for a wallet
    function getWalletTransactions(uint256 walletId) external view returns (uint256[] memory) {
        return _walletTransactions[walletId];
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    /// @notice Admin emergency freeze (for compromised wallets)
    function adminFreeze(uint256 walletId) external onlyOwner walletExists(walletId) {
        wallets[walletId].frozen = true;
        emit WalletFrozen(walletId, msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "AgentWallet: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    receive() external payable {}
}
