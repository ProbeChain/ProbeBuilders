// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PrivateMempool
 * @author ProbeChain
 * @notice MEV protection via commit-reveal scheme for encrypted transaction submission
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

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

abstract contract Pausable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function _pause() internal whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function _unpause() internal whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

contract PrivateMempool is Ownable, ReentrancyGuard, Pausable {
    /// @notice Commit status
    enum CommitStatus { Committed, Revealed, Executed, Expired }

    /// @notice Committed encrypted transaction
    struct CommittedTx {
        uint256 id;
        address sender;
        bytes encryptedData;
        bytes32 commitHash;
        bytes decryptedData;
        bytes32 salt;
        CommitStatus status;
        uint256 committedAt;
        uint256 revealDeadline;
    }

    /// @notice Execution bundle
    struct Bundle {
        uint256 id;
        uint256[] txIds;
        address executedBy;
        uint256 executedAt;
    }

    /// @dev Commit counter
    uint256 private _nextCommitId;

    /// @dev Bundle counter
    uint256 private _nextBundleId;

    /// @dev Reveal window duration
    uint256 public revealWindow;

    /// @dev Commit ID => CommittedTx
    mapping(uint256 => CommittedTx) private _commits;

    /// @dev Bundle ID => Bundle
    mapping(uint256 => Bundle) private _bundles;

    /// @dev Authorized sequencers
    mapping(address => bool) public sequencers;

    /// @dev User => commit IDs
    mapping(address => uint256[]) private _userCommits;

    /// @dev Total commits
    uint256 public totalCommits;

    /// @dev Total bundles executed
    uint256 public totalBundles;

    // ───────── Events ─────────

    /// @notice Emitted when an encrypted tx is submitted
    event TxCommitted(uint256 indexed commitId, address indexed sender, bytes32 commitHash);

    /// @notice Emitted when a tx is revealed
    event TxRevealed(uint256 indexed commitId, address indexed sender);

    /// @notice Emitted when a bundle is executed
    event BundleExecuted(uint256 indexed bundleId, uint256[] txIds, address indexed sequencer);

    /// @notice Emitted when a commit expires
    event CommitExpired(uint256 indexed commitId);

    /// @notice Emitted when a sequencer is updated
    event SequencerUpdated(address indexed sequencer, bool status);

    // ───────── Constructor ─────────

    constructor() {
        _nextCommitId = 1;
        _nextBundleId = 1;
        revealWindow = 10 minutes;
    }

    // ───────── Admin ─────────

    /// @notice Set sequencer status
    function setSequencer(address sequencer, bool status) external onlyOwner {
        require(sequencer != address(0), "PrivateMempool: zero address");
        sequencers[sequencer] = status;
        emit SequencerUpdated(sequencer, status);
    }

    /// @notice Update reveal window
    function setRevealWindow(uint256 window) external onlyOwner {
        require(window >= 1 minutes, "PrivateMempool: too short");
        revealWindow = window;
    }

    /// @notice Pause/unpause
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Submit an encrypted transaction with a commit hash
    /// @param encryptedData The encrypted transaction data
    /// @param commitHash Hash of (decryptedData + salt) for verification
    /// @return commitId The commit ID
    function submitEncryptedTx(
        bytes calldata encryptedData,
        bytes32 commitHash
    ) external whenNotPaused returns (uint256 commitId) {
        require(encryptedData.length > 0, "PrivateMempool: empty data");
        require(commitHash != bytes32(0), "PrivateMempool: empty hash");

        commitId = _nextCommitId++;

        _commits[commitId] = CommittedTx({
            id: commitId,
            sender: msg.sender,
            encryptedData: encryptedData,
            commitHash: commitHash,
            decryptedData: "",
            salt: bytes32(0),
            status: CommitStatus.Committed,
            committedAt: block.timestamp,
            revealDeadline: block.timestamp + revealWindow
        });

        _userCommits[msg.sender].push(commitId);
        totalCommits++;

        emit TxCommitted(commitId, msg.sender, commitHash);
    }

    /// @notice Reveal a previously committed transaction
    /// @param commitId The commit to reveal
    /// @param decryptedData The original transaction data
    /// @param salt The salt used in the commit hash
    function revealTx(
        uint256 commitId,
        bytes calldata decryptedData,
        bytes32 salt
    ) external whenNotPaused {
        CommittedTx storage c = _commits[commitId];
        require(c.id != 0, "PrivateMempool: not found");
        require(c.sender == msg.sender, "PrivateMempool: not sender");
        require(c.status == CommitStatus.Committed, "PrivateMempool: not committed");
        require(block.timestamp <= c.revealDeadline, "PrivateMempool: reveal expired");

        // Verify commit hash matches
        bytes32 computedHash = keccak256(abi.encodePacked(decryptedData, salt));
        require(computedHash == c.commitHash, "PrivateMempool: hash mismatch");

        c.decryptedData = decryptedData;
        c.salt = salt;
        c.status = CommitStatus.Revealed;

        emit TxRevealed(commitId, msg.sender);
    }

    /// @notice Execute a bundle of revealed transactions (sequencer only)
    /// @param txIds Array of commit IDs to execute in order
    /// @return bundleId The bundle ID
    function executeBundle(
        uint256[] calldata txIds
    ) external whenNotPaused nonReentrant returns (uint256 bundleId) {
        require(sequencers[msg.sender], "PrivateMempool: not sequencer");
        require(txIds.length > 0, "PrivateMempool: empty bundle");

        for (uint256 i = 0; i < txIds.length; i++) {
            CommittedTx storage c = _commits[txIds[i]];
            require(c.id != 0, "PrivateMempool: tx not found");
            require(c.status == CommitStatus.Revealed, "PrivateMempool: not revealed");
            c.status = CommitStatus.Executed;
        }

        bundleId = _nextBundleId++;

        _bundles[bundleId] = Bundle({
            id: bundleId,
            txIds: txIds,
            executedBy: msg.sender,
            executedAt: block.timestamp
        });

        totalBundles++;

        emit BundleExecuted(bundleId, txIds, msg.sender);
    }

    /// @notice Mark expired commits
    /// @param commitId The commit to expire
    function expireCommit(uint256 commitId) external {
        CommittedTx storage c = _commits[commitId];
        require(c.id != 0, "PrivateMempool: not found");
        require(c.status == CommitStatus.Committed, "PrivateMempool: not committed");
        require(block.timestamp > c.revealDeadline, "PrivateMempool: not expired");

        c.status = CommitStatus.Expired;
        emit CommitExpired(commitId);
    }

    // ───────── View Functions ─────────

    /// @notice Get commit details
    function getCommit(uint256 commitId) external view returns (CommittedTx memory) {
        require(_commits[commitId].id != 0, "PrivateMempool: not found");
        return _commits[commitId];
    }

    /// @notice Get bundle details
    function getBundle(uint256 bundleId) external view returns (Bundle memory) {
        require(_bundles[bundleId].id != 0, "PrivateMempool: not found");
        return _bundles[bundleId];
    }

    /// @notice Get user's commit IDs
    function getUserCommits(address user) external view returns (uint256[] memory) {
        return _userCommits[user];
    }

    /// @notice Check if a commit is still in reveal window
    function isInRevealWindow(uint256 commitId) external view returns (bool) {
        CommittedTx memory c = _commits[commitId];
        return c.status == CommitStatus.Committed && block.timestamp <= c.revealDeadline;
    }
}
