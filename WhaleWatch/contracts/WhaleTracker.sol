// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title WhaleTracker
 * @author ProbeBuilders
 * @notice On-chain registry for tracking whale wallets and large transaction movements
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */
contract WhaleTracker {
    // ─── Ownership ───────────────────────────────────────────────────
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "WhaleTracker: not owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "WhaleTracker: zero address");
        owner = newOwner;
    }

    // ─── Pausable ────────────────────────────────────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "WhaleTracker: paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ─── Enums & Structs ─────────────────────────────────────────────

    enum TxType { Transfer, Swap, Stake, Unstake, Bridge, Mint, Burn }

    /// @notice Whale wallet profile
    struct WhaleProfile {
        string label;
        address wallet;
        uint256 totalTxCount;
        uint256 totalVolume;
        uint256 largestTx;
        uint256 firstSeenAt;
        uint256 lastActiveAt;
        bool active;
    }

    /// @notice A recorded transaction
    struct Transaction {
        address wallet;
        TxType txType;
        uint256 amount;
        uint256 timestamp;
        bytes32 txHash;        // reference hash for off-chain lookup
        address recorder;
    }

    // ─── State ───────────────────────────────────────────────────────
    uint256 public nextTxId = 1;
    uint256 public alertThreshold = 100 ether;
    uint256 public whaleCount;

    mapping(address => WhaleProfile) public whales;
    mapping(uint256 => Transaction) public transactions;
    mapping(address => uint256[]) public walletTransactions;
    mapping(address => bool) public authorizedRecorders;
    address[] public whaleList;

    // ─── Events ──────────────────────────────────────────────────────
    event WhaleRegistered(address indexed wallet, string label);
    event WhaleUpdated(address indexed wallet, string newLabel);
    event WhaleDeactivated(address indexed wallet);
    event TransactionRecorded(
        uint256 indexed txId,
        address indexed wallet,
        TxType txType,
        uint256 amount,
        uint256 timestamp
    );
    event WhaleAlert(
        address indexed wallet,
        uint256 indexed txId,
        TxType txType,
        uint256 amount,
        string label
    );
    event ThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event RecorderAuthorized(address indexed recorder);
    event RecorderRevoked(address indexed recorder);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor(uint256 initialThreshold) {
        owner = msg.sender;
        authorizedRecorders[msg.sender] = true;
        if (initialThreshold > 0) {
            alertThreshold = initialThreshold;
        }
    }

    // ─── Modifiers ───────────────────────────────────────────────────
    modifier onlyRecorder() {
        require(authorizedRecorders[msg.sender], "WhaleTracker: not authorized");
        _;
    }

    // ─── Whale Management ────────────────────────────────────────────

    /// @notice Register a whale wallet to track
    /// @param wallet The whale's wallet address
    /// @param label Human-readable label (e.g., "Binance Hot Wallet")
    function registerWhale(address wallet, string calldata label) external onlyRecorder whenNotPaused {
        require(wallet != address(0), "WhaleTracker: zero address");
        require(bytes(label).length > 0 && bytes(label).length <= 64, "WhaleTracker: invalid label");
        require(!whales[wallet].active, "WhaleTracker: already registered");

        whales[wallet] = WhaleProfile({
            label: label,
            wallet: wallet,
            totalTxCount: 0,
            totalVolume: 0,
            largestTx: 0,
            firstSeenAt: block.timestamp,
            lastActiveAt: block.timestamp,
            active: true
        });
        whaleList.push(wallet);
        whaleCount++;

        emit WhaleRegistered(wallet, label);
    }

    /// @notice Update a whale's label
    function updateWhaleLabel(address wallet, string calldata newLabel) external onlyRecorder {
        require(whales[wallet].active, "WhaleTracker: not registered");
        require(bytes(newLabel).length > 0 && bytes(newLabel).length <= 64, "WhaleTracker: invalid label");
        whales[wallet].label = newLabel;
        emit WhaleUpdated(wallet, newLabel);
    }

    /// @notice Deactivate whale tracking
    function deactivateWhale(address wallet) external onlyRecorder {
        require(whales[wallet].active, "WhaleTracker: not active");
        whales[wallet].active = false;
        whaleCount--;
        emit WhaleDeactivated(wallet);
    }

    // ─── Transaction Recording ───────────────────────────────────────

    /// @notice Record a whale transaction
    /// @param wallet The whale wallet that performed the transaction
    /// @param txType Type of transaction (0-6)
    /// @param amount Transaction amount in wei
    /// @param timestamp When the transaction occurred
    /// @param txHash Off-chain transaction hash for reference
    function recordTransaction(
        address wallet,
        TxType txType,
        uint256 amount,
        uint256 timestamp,
        bytes32 txHash
    ) external onlyRecorder whenNotPaused {
        WhaleProfile storage whale = whales[wallet];
        require(whale.active, "WhaleTracker: wallet not tracked");
        require(amount > 0, "WhaleTracker: zero amount");
        require(timestamp <= block.timestamp, "WhaleTracker: future timestamp");

        uint256 txId = nextTxId++;
        transactions[txId] = Transaction({
            wallet: wallet,
            txType: txType,
            amount: amount,
            timestamp: timestamp,
            txHash: txHash,
            recorder: msg.sender
        });
        walletTransactions[wallet].push(txId);

        whale.totalTxCount++;
        whale.totalVolume += amount;
        whale.lastActiveAt = timestamp;
        if (amount > whale.largestTx) {
            whale.largestTx = amount;
        }

        emit TransactionRecorded(txId, wallet, txType, amount, timestamp);

        // Emit alert if amount exceeds threshold
        if (amount >= alertThreshold) {
            emit WhaleAlert(wallet, txId, txType, amount, whale.label);
        }
    }

    /// @notice Record multiple transactions in a batch
    /// @param wallets Array of wallet addresses
    /// @param txTypes Array of transaction types
    /// @param amounts Array of amounts
    /// @param timestamps Array of timestamps
    /// @param txHashes Array of transaction hashes
    function batchRecordTransactions(
        address[] calldata wallets,
        TxType[] calldata txTypes,
        uint256[] calldata amounts,
        uint256[] calldata timestamps,
        bytes32[] calldata txHashes
    ) external onlyRecorder whenNotPaused {
        uint256 len = wallets.length;
        require(
            len == txTypes.length && len == amounts.length &&
            len == timestamps.length && len == txHashes.length,
            "WhaleTracker: array length mismatch"
        );
        require(len <= 50, "WhaleTracker: batch too large");

        for (uint256 i = 0; i < len; i++) {
            WhaleProfile storage whale = whales[wallets[i]];
            if (!whale.active || amounts[i] == 0) continue;

            uint256 txId = nextTxId++;
            transactions[txId] = Transaction({
                wallet: wallets[i],
                txType: txTypes[i],
                amount: amounts[i],
                timestamp: timestamps[i],
                txHash: txHashes[i],
                recorder: msg.sender
            });
            walletTransactions[wallets[i]].push(txId);

            whale.totalTxCount++;
            whale.totalVolume += amounts[i];
            whale.lastActiveAt = timestamps[i];
            if (amounts[i] > whale.largestTx) whale.largestTx = amounts[i];

            emit TransactionRecorded(txId, wallets[i], txTypes[i], amounts[i], timestamps[i]);

            if (amounts[i] >= alertThreshold) {
                emit WhaleAlert(wallets[i], txId, txTypes[i], amounts[i], whale.label);
            }
        }
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get whale activity summary
    function getWhaleActivity(address wallet)
        external
        view
        returns (
            string memory label,
            uint256 totalTxCount,
            uint256 totalVolume,
            uint256 largestTx,
            uint256 lastActiveAt,
            bool active
        )
    {
        WhaleProfile storage w = whales[wallet];
        return (w.label, w.totalTxCount, w.totalVolume, w.largestTx, w.lastActiveAt, w.active);
    }

    /// @notice Get transaction IDs for a wallet
    function getWalletTransactions(address wallet) external view returns (uint256[] memory) {
        return walletTransactions[wallet];
    }

    /// @notice Get all tracked whale addresses
    function getAllWhales() external view returns (address[] memory) {
        return whaleList;
    }

    // ─── Admin ───────────────────────────────────────────────────────

    /// @notice Set the alert threshold
    function setThreshold(uint256 minAmount) external onlyOwner {
        uint256 old = alertThreshold;
        alertThreshold = minAmount;
        emit ThresholdUpdated(old, minAmount);
    }

    function authorizeRecorder(address recorder) external onlyOwner {
        authorizedRecorders[recorder] = true;
        emit RecorderAuthorized(recorder);
    }

    function revokeRecorder(address recorder) external onlyOwner {
        authorizedRecorders[recorder] = false;
        emit RecorderRevoked(recorder);
    }
}
