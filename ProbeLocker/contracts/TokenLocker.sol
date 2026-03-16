// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TokenLocker
 * @author ProbeChain
 * @notice Token lock supporting ERC-20 and native PROBE with time-based unlocking
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

/// @notice Minimal ERC-20 interface for token interactions
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

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

contract TokenLocker is Ownable, ReentrancyGuard, Pausable {
    /// @notice Native PROBE sentinel address
    address public constant NATIVE_TOKEN = address(0);

    /// @notice Lock record
    struct Lock {
        uint256 id;
        address owner;
        address token;
        uint256 amount;
        uint256 unlockTime;
        bool withdrawn;
        uint256 createdAt;
    }

    /// @dev Lock counter
    uint256 private _nextLockId;

    /// @dev Lock ID => Lock
    mapping(uint256 => Lock) private _locks;

    /// @dev All lock IDs
    uint256[] private _lockIds;

    /// @dev Owner => lock IDs
    mapping(address => uint256[]) private _ownerLocks;

    /// @dev Token => total locked amount
    mapping(address => uint256) private _tokenLocked;

    /// @dev Total native PROBE locked
    uint256 public totalNativeLocked;

    // ───────── Events ─────────

    /// @notice Emitted when tokens are locked
    event TokensLocked(uint256 indexed lockId, address indexed owner, address indexed token, uint256 amount, uint256 unlockTime);

    /// @notice Emitted when a lock is extended
    event LockExtended(uint256 indexed lockId, uint256 oldUnlockTime, uint256 newUnlockTime);

    /// @notice Emitted when tokens are unlocked and withdrawn
    event TokensUnlocked(uint256 indexed lockId, address indexed owner, address indexed token, uint256 amount);

    // ───────── Constructor ─────────

    constructor() {
        _nextLockId = 1;
    }

    // ───────── Admin ─────────

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Lock ERC-20 tokens
    /// @param token The ERC-20 token address
    /// @param amount Amount to lock
    /// @param unlockTime Unix timestamp when tokens can be withdrawn
    /// @return lockId The new lock ID
    function lockTokens(
        address token,
        uint256 amount,
        uint256 unlockTime
    ) external payable whenNotPaused nonReentrant returns (uint256 lockId) {
        require(amount > 0, "Locker: zero amount");
        require(unlockTime > block.timestamp, "Locker: unlock in past");
        require(unlockTime <= block.timestamp + 365 days * 10, "Locker: too far");

        lockId = _nextLockId++;

        if (token == NATIVE_TOKEN) {
            // Lock native PROBE
            require(msg.value >= amount, "Locker: insufficient PROBE");
            totalNativeLocked += amount;

            // Refund excess
            if (msg.value > amount) {
                (bool sent, ) = msg.sender.call{value: msg.value - amount}("");
                require(sent, "Locker: refund failed");
            }
        } else {
            // Lock ERC-20
            require(msg.value == 0, "Locker: no PROBE for ERC20 lock");
            uint256 balBefore = IERC20(token).balanceOf(address(this));
            bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
            require(success, "Locker: transfer failed");
            uint256 balAfter = IERC20(token).balanceOf(address(this));
            amount = balAfter - balBefore; // Handle fee-on-transfer tokens
        }

        _locks[lockId] = Lock({
            id: lockId,
            owner: msg.sender,
            token: token,
            amount: amount,
            unlockTime: unlockTime,
            withdrawn: false,
            createdAt: block.timestamp
        });

        _lockIds.push(lockId);
        _ownerLocks[msg.sender].push(lockId);
        _tokenLocked[token] += amount;

        emit TokensLocked(lockId, msg.sender, token, amount, unlockTime);
    }

    /// @notice Extend a lock's unlock time
    /// @param lockId The lock to extend
    /// @param newUnlockTime The new (later) unlock time
    function extendLock(uint256 lockId, uint256 newUnlockTime) external whenNotPaused {
        Lock storage l = _locks[lockId];
        require(l.id != 0, "Locker: not found");
        require(l.owner == msg.sender, "Locker: not owner");
        require(!l.withdrawn, "Locker: already withdrawn");
        require(newUnlockTime > l.unlockTime, "Locker: must be later");
        require(newUnlockTime <= block.timestamp + 365 days * 10, "Locker: too far");

        uint256 oldTime = l.unlockTime;
        l.unlockTime = newUnlockTime;

        emit LockExtended(lockId, oldTime, newUnlockTime);
    }

    /// @notice Unlock and withdraw tokens after unlock time
    /// @param lockId The lock to withdraw from
    function unlock(uint256 lockId) external whenNotPaused nonReentrant {
        Lock storage l = _locks[lockId];
        require(l.id != 0, "Locker: not found");
        require(l.owner == msg.sender, "Locker: not owner");
        require(!l.withdrawn, "Locker: already withdrawn");
        require(block.timestamp >= l.unlockTime, "Locker: still locked");

        l.withdrawn = true;
        _tokenLocked[l.token] -= l.amount;

        if (l.token == NATIVE_TOKEN) {
            totalNativeLocked -= l.amount;
            (bool sent, ) = msg.sender.call{value: l.amount}("");
            require(sent, "Locker: PROBE transfer failed");
        } else {
            bool success = IERC20(l.token).transfer(msg.sender, l.amount);
            require(success, "Locker: token transfer failed");
        }

        emit TokensUnlocked(lockId, msg.sender, l.token, l.amount);
    }

    // ───────── View Functions ─────────

    /// @notice Get lock details
    function getLock(uint256 lockId) external view returns (Lock memory) {
        require(_locks[lockId].id != 0, "Locker: not found");
        return _locks[lockId];
    }

    /// @notice Get locks by owner
    function getOwnerLocks(address lockOwner) external view returns (uint256[] memory) {
        return _ownerLocks[lockOwner];
    }

    /// @notice Get total locked amount for a token
    function getLockedBalance(address token) external view returns (uint256) {
        return _tokenLocked[token];
    }

    /// @notice Check if a lock is unlockable
    function isUnlockable(uint256 lockId) external view returns (bool) {
        Lock memory l = _locks[lockId];
        return l.id != 0 && !l.withdrawn && block.timestamp >= l.unlockTime;
    }

    /// @notice Total locks created
    function totalLocks() external view returns (uint256) {
        return _nextLockId - 1;
    }

    /// @notice Get active lock IDs (not withdrawn)
    function getActiveLocks() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < _lockIds.length; i++) {
            if (!_locks[_lockIds[i]].withdrawn) count++;
        }
        uint256[] memory result = new uint256[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < _lockIds.length; i++) {
            if (!_locks[_lockIds[i]].withdrawn) {
                result[j++] = _lockIds[i];
            }
        }
        return result;
    }
}
