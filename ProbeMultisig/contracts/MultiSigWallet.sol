// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MultiSigWallet
 * @author ProbeChain
 * @notice Multi-signature wallet with configurable confirmation threshold
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

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

contract MultiSigWallet is ReentrancyGuard {
    /// @notice Transaction status
    enum TxStatus { Pending, Executed, Cancelled }

    /// @notice Multi-sig transaction
    struct Transaction {
        uint256 id;
        address to;
        uint256 value;
        bytes data;
        TxStatus status;
        uint256 confirmationCount;
        uint256 submittedAt;
        address submittedBy;
    }

    /// @notice Wallet owners
    address[] public owners;

    /// @notice Required confirmations to execute
    uint256 public required;

    /// @dev Owner check mapping
    mapping(address => bool) public isOwner;

    /// @dev Transaction counter
    uint256 private _nextTxId;

    /// @dev Transaction ID => Transaction
    mapping(uint256 => Transaction) private _transactions;

    /// @dev Transaction ID => owner => confirmed
    mapping(uint256 => mapping(address => bool)) private _confirmations;

    /// @dev All transaction IDs
    uint256[] private _txIds;

    // ───────── Events ─────────

    /// @notice Emitted when a transaction is submitted
    event TransactionSubmitted(uint256 indexed txId, address indexed to, uint256 value, address indexed submitter);

    /// @notice Emitted when a transaction is confirmed
    event TransactionConfirmed(uint256 indexed txId, address indexed confirmer);

    /// @notice Emitted when a confirmation is revoked
    event ConfirmationRevoked(uint256 indexed txId, address indexed revoker);

    /// @notice Emitted when a transaction is executed
    event TransactionExecuted(uint256 indexed txId, address indexed executor);

    /// @notice Emitted when a transaction execution fails
    event TransactionFailed(uint256 indexed txId);

    /// @notice Emitted when PROBE is deposited
    event Deposited(address indexed sender, uint256 amount);

    /// @notice Emitted when an owner is added
    event OwnerAdded(address indexed owner);

    /// @notice Emitted when an owner is removed
    event OwnerRemoved(address indexed owner);

    /// @notice Emitted when required confirmations change
    event RequirementChanged(uint256 required);

    // ───────── Modifiers ─────────

    modifier onlyOwnerMod() {
        require(isOwner[msg.sender], "MultiSig: not owner");
        _;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), "MultiSig: only via multisig");
        _;
    }

    modifier txExists(uint256 txId) {
        require(_transactions[txId].submittedAt > 0, "MultiSig: tx not found");
        _;
    }

    modifier txPending(uint256 txId) {
        require(_transactions[txId].status == TxStatus.Pending, "MultiSig: not pending");
        _;
    }

    // ───────── Constructor ─────────

    /// @param _owners Array of initial owners
    /// @param _required Number of required confirmations
    constructor(address[] memory _owners, uint256 _required) {
        require(_owners.length > 0, "MultiSig: no owners");
        require(_required > 0 && _required <= _owners.length, "MultiSig: invalid required");

        for (uint256 i = 0; i < _owners.length; i++) {
            address o = _owners[i];
            require(o != address(0), "MultiSig: zero address");
            require(!isOwner[o], "MultiSig: duplicate owner");

            isOwner[o] = true;
            owners.push(o);
        }

        required = _required;
        _nextTxId = 1;
    }

    /// @notice Receive PROBE deposits
    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    // ───────── Owner Management (via multisig) ─────────

    /// @notice Add a new owner (must be called via multisig)
    function addOwner(address newOwner) external onlySelf {
        require(newOwner != address(0), "MultiSig: zero address");
        require(!isOwner[newOwner], "MultiSig: already owner");

        isOwner[newOwner] = true;
        owners.push(newOwner);
        emit OwnerAdded(newOwner);
    }

    /// @notice Remove an owner (must be called via multisig)
    function removeOwner(address ownerToRemove) external onlySelf {
        require(isOwner[ownerToRemove], "MultiSig: not owner");
        require(owners.length - 1 >= required, "MultiSig: would break threshold");

        isOwner[ownerToRemove] = false;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == ownerToRemove) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }
        emit OwnerRemoved(ownerToRemove);
    }

    /// @notice Change required confirmations (must be called via multisig)
    function changeRequirement(uint256 _required) external onlySelf {
        require(_required > 0 && _required <= owners.length, "MultiSig: invalid");
        required = _required;
        emit RequirementChanged(_required);
    }

    // ───────── Transaction Functions ─────────

    /// @notice Submit a new transaction for confirmation
    /// @param to Destination address
    /// @param value PROBE value to send
    /// @param data Calldata for the transaction
    /// @return txId The transaction ID
    function submitTransaction(
        address to,
        uint256 value,
        bytes calldata data
    ) external onlyOwnerMod returns (uint256 txId) {
        require(to != address(0), "MultiSig: zero address");

        txId = _nextTxId++;

        _transactions[txId] = Transaction({
            id: txId,
            to: to,
            value: value,
            data: data,
            status: TxStatus.Pending,
            confirmationCount: 0,
            submittedAt: block.timestamp,
            submittedBy: msg.sender
        });

        _txIds.push(txId);

        emit TransactionSubmitted(txId, to, value, msg.sender);

        // Auto-confirm by submitter
        _confirmations[txId][msg.sender] = true;
        _transactions[txId].confirmationCount = 1;
        emit TransactionConfirmed(txId, msg.sender);
    }

    /// @notice Confirm a pending transaction
    /// @param txId The transaction to confirm
    function confirmTransaction(uint256 txId) external onlyOwnerMod txExists(txId) txPending(txId) {
        require(!_confirmations[txId][msg.sender], "MultiSig: already confirmed");

        _confirmations[txId][msg.sender] = true;
        _transactions[txId].confirmationCount++;

        emit TransactionConfirmed(txId, msg.sender);
    }

    /// @notice Execute a fully confirmed transaction
    /// @param txId The transaction to execute
    function executeTransaction(uint256 txId) external onlyOwnerMod txExists(txId) txPending(txId) nonReentrant {
        Transaction storage t = _transactions[txId];
        require(t.confirmationCount >= required, "MultiSig: not enough confirmations");

        t.status = TxStatus.Executed;

        (bool success, ) = t.to.call{value: t.value}(t.data);
        if (success) {
            emit TransactionExecuted(txId, msg.sender);
        } else {
            t.status = TxStatus.Pending;
            emit TransactionFailed(txId);
        }
    }

    /// @notice Revoke a confirmation
    /// @param txId The transaction to revoke confirmation from
    function revokeConfirmation(uint256 txId) external onlyOwnerMod txExists(txId) txPending(txId) {
        require(_confirmations[txId][msg.sender], "MultiSig: not confirmed");

        _confirmations[txId][msg.sender] = false;
        _transactions[txId].confirmationCount--;

        emit ConfirmationRevoked(txId, msg.sender);
    }

    // ───────── View Functions ─────────

    /// @notice Get transaction details
    function getTransaction(uint256 txId) external view returns (Transaction memory) {
        require(_transactions[txId].submittedAt > 0, "MultiSig: not found");
        return _transactions[txId];
    }

    /// @notice Check if an owner has confirmed a transaction
    function isConfirmed(uint256 txId, address ownerAddr) external view returns (bool) {
        return _confirmations[txId][ownerAddr];
    }

    /// @notice Get all owners
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /// @notice Get transaction count
    function getTransactionCount() external view returns (uint256) {
        return _nextTxId - 1;
    }

    /// @notice Get pending transaction IDs
    function getPendingTransactions() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < _txIds.length; i++) {
            if (_transactions[_txIds[i]].status == TxStatus.Pending) count++;
        }
        uint256[] memory result = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < _txIds.length; i++) {
            if (_transactions[_txIds[i]].status == TxStatus.Pending) {
                result[j++] = _txIds[i];
            }
        }
        return result;
    }

    /// @notice Get wallet balance
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
