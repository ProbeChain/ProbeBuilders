// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title BridgeLock
 * @author ProbeChain
 * @notice Cross-chain bridge with multi-relayer consensus for locking and claiming tokens
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

contract BridgeLock is Ownable, ReentrancyGuard, Pausable {
    /// @notice Lock status
    enum LockStatus { Locked, Confirmed, Claimed, Refunded }

    /// @notice Token lock record
    struct Lock {
        uint256 id;
        address sender;
        address recipient;
        uint256 amount;
        uint256 destChain;
        LockStatus status;
        uint256 confirmations;
        uint256 lockedAt;
        bytes32 bridgeProof;
    }

    /// @notice Relayer information
    struct Relayer {
        address addr;
        uint256 stake;
        uint256 confirmedCount;
        bool active;
        uint256 registeredAt;
    }

    /// @dev Minimum relayer stake
    uint256 public minRelayerStake;

    /// @dev Required confirmations for bridge
    uint256 public requiredConfirmations;

    /// @dev Lock expiration time
    uint256 public lockExpiration;

    /// @dev Lock counter
    uint256 private _nextLockId;

    /// @dev Lock ID => Lock
    mapping(uint256 => Lock) private _locks;

    /// @dev Address => Relayer
    mapping(address => Relayer) private _relayers;

    /// @dev Active relayer list
    address[] private _relayerList;

    /// @dev Lock ID => relayer => confirmed
    mapping(uint256 => mapping(address => bool)) private _confirmations;

    /// @dev Total locked value
    uint256 public totalLocked;

    // ───────── Events ─────────

    /// @notice Emitted when tokens are locked for bridging
    event TokensLocked(uint256 indexed lockId, address indexed sender, address recipient, uint256 amount, uint256 destChain);

    /// @notice Emitted when a relayer confirms a bridge
    event BridgeConfirmed(uint256 indexed lockId, address indexed relayer, uint256 confirmations);

    /// @notice Emitted when tokens are claimed after bridge
    event TokensClaimed(uint256 indexed lockId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a lock is refunded (expired)
    event LockRefunded(uint256 indexed lockId, address indexed sender, uint256 amount);

    /// @notice Emitted when a relayer registers
    event RelayerRegistered(address indexed relayer, uint256 stake);

    /// @notice Emitted when a relayer is removed
    event RelayerRemoved(address indexed relayer);

    // ───────── Constructor ─────────

    constructor() {
        _nextLockId = 1;
        minRelayerStake = 1 ether;
        requiredConfirmations = 2;
        lockExpiration = 24 hours;
    }

    // ───────── Admin ─────────

    /// @notice Update minimum relayer stake
    function setMinRelayerStake(uint256 stake) external onlyOwner {
        minRelayerStake = stake;
    }

    /// @notice Update required confirmations
    function setRequiredConfirmations(uint256 count) external onlyOwner {
        require(count > 0, "BridgeLock: zero confirmations");
        requiredConfirmations = count;
    }

    /// @notice Pause/unpause
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Relayer Management ─────────

    /// @notice Register as a relayer with stake
    function registerRelayer() external payable whenNotPaused {
        require(msg.value >= minRelayerStake, "BridgeLock: insufficient stake");
        require(!_relayers[msg.sender].active, "BridgeLock: already registered");

        _relayers[msg.sender] = Relayer({
            addr: msg.sender,
            stake: msg.value,
            confirmedCount: 0,
            active: true,
            registeredAt: block.timestamp
        });
        _relayerList.push(msg.sender);

        emit RelayerRegistered(msg.sender, msg.value);
    }

    /// @notice Remove a relayer (owner only)
    function removeRelayer(address relayer) external onlyOwner nonReentrant {
        Relayer storage r = _relayers[relayer];
        require(r.active, "BridgeLock: not active");

        r.active = false;
        uint256 stake = r.stake;
        r.stake = 0;

        (bool sent, ) = relayer.call{value: stake}("");
        require(sent, "BridgeLock: refund failed");

        emit RelayerRemoved(relayer);
    }

    // ───────── Bridge Functions ─────────

    /// @notice Lock tokens for cross-chain bridging
    /// @param destChain Destination chain ID
    /// @param recipient Recipient address on destination chain
    /// @return lockId The lock ID
    function lockTokens(
        uint256 destChain,
        address recipient
    ) external payable whenNotPaused nonReentrant returns (uint256 lockId) {
        require(msg.value > 0, "BridgeLock: zero amount");
        require(recipient != address(0), "BridgeLock: zero recipient");
        require(destChain != block.chainid, "BridgeLock: same chain");

        lockId = _nextLockId++;

        _locks[lockId] = Lock({
            id: lockId,
            sender: msg.sender,
            recipient: recipient,
            amount: msg.value,
            destChain: destChain,
            status: LockStatus.Locked,
            confirmations: 0,
            lockedAt: block.timestamp,
            bridgeProof: bytes32(0)
        });

        totalLocked += msg.value;

        emit TokensLocked(lockId, msg.sender, recipient, msg.value, destChain);
    }

    /// @notice Confirm a bridge lock (relayer only)
    /// @param lockId The lock to confirm
    /// @param bridgeProof Proof of bridge execution on destination chain
    function confirmBridge(uint256 lockId, bytes32 bridgeProof) external whenNotPaused {
        require(_relayers[msg.sender].active, "BridgeLock: not relayer");

        Lock storage lock = _locks[lockId];
        require(lock.id != 0, "BridgeLock: not found");
        require(lock.status == LockStatus.Locked, "BridgeLock: not locked");
        require(!_confirmations[lockId][msg.sender], "BridgeLock: already confirmed");

        _confirmations[lockId][msg.sender] = true;
        lock.confirmations++;
        lock.bridgeProof = bridgeProof;
        _relayers[msg.sender].confirmedCount++;

        if (lock.confirmations >= requiredConfirmations) {
            lock.status = LockStatus.Confirmed;
        }

        emit BridgeConfirmed(lockId, msg.sender, lock.confirmations);
    }

    /// @notice Claim tokens after bridge confirmation
    /// @param lockId The lock to claim
    function claimTokens(uint256 lockId) external whenNotPaused nonReentrant {
        Lock storage lock = _locks[lockId];
        require(lock.id != 0, "BridgeLock: not found");
        require(lock.status == LockStatus.Confirmed, "BridgeLock: not confirmed");
        require(lock.recipient == msg.sender, "BridgeLock: not recipient");

        lock.status = LockStatus.Claimed;
        totalLocked -= lock.amount;

        (bool sent, ) = msg.sender.call{value: lock.amount}("");
        require(sent, "BridgeLock: transfer failed");

        emit TokensClaimed(lockId, msg.sender, lock.amount);
    }

    /// @notice Refund expired lock back to sender
    /// @param lockId The lock to refund
    function refundLock(uint256 lockId) external whenNotPaused nonReentrant {
        Lock storage lock = _locks[lockId];
        require(lock.id != 0, "BridgeLock: not found");
        require(lock.status == LockStatus.Locked, "BridgeLock: not locked");
        require(lock.sender == msg.sender, "BridgeLock: not sender");
        require(block.timestamp > lock.lockedAt + lockExpiration, "BridgeLock: not expired");

        lock.status = LockStatus.Refunded;
        totalLocked -= lock.amount;

        (bool sent, ) = msg.sender.call{value: lock.amount}("");
        require(sent, "BridgeLock: refund failed");

        emit LockRefunded(lockId, msg.sender, lock.amount);
    }

    // ───────── View Functions ─────────

    /// @notice Get lock details
    function getLock(uint256 lockId) external view returns (Lock memory) {
        require(_locks[lockId].id != 0, "BridgeLock: not found");
        return _locks[lockId];
    }

    /// @notice Get relayer details
    function getRelayer(address relayer) external view returns (Relayer memory) {
        return _relayers[relayer];
    }

    /// @notice Get all relayer addresses
    function getRelayers() external view returns (address[] memory) {
        return _relayerList;
    }

    /// @notice Check if relayer confirmed a lock
    function hasConfirmed(uint256 lockId, address relayer) external view returns (bool) {
        return _confirmations[lockId][relayer];
    }

    /// @notice Total locks created
    function totalLocks() external view returns (uint256) {
        return _nextLockId - 1;
    }
}
