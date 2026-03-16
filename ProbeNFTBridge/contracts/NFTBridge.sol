// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NFTBridge
 * @author ProbeChain Team
 * @notice Cross-chain NFT bridge with lock/claim mechanism on ProbeChain Rydberg Testnet
 * @dev Locks NFTs on source chain, relayer confirms on destination, timeout-based cancellation
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

/// @notice Minimal ERC721 interface
interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

contract NFTBridge is Ownable, ReentrancyGuard, Pausable {
    enum LockStatus { Locked, Claimed, Cancelled }

    /// @notice Lock record for a bridged NFT
    struct LockRecord {
        uint256 id;
        address nftContract;
        uint256 tokenId;
        address sender;
        uint256 destChainId;
        LockStatus status;
        uint256 lockedAt;
        uint256 timeoutAt;
        bytes32 bridgeProofHash;
    }

    mapping(uint256 => LockRecord) private _locks;
    mapping(address => uint256[]) private _userLocks;
    mapping(address => bool) private _relayers;
    mapping(uint256 => bool) private _supportedChains;

    uint256 private _nextLockId = 1;
    uint256 public lockTimeout = 24 hours;
    uint256 public totalLocked;
    uint256 public totalClaimed;
    uint256 public bridgeFee = 0.01 ether;

    /// @notice Emitted when an NFT is locked for bridging
    event NFTLocked(uint256 indexed lockId, address indexed nftContract, uint256 tokenId, address indexed sender, uint256 destChainId);
    /// @notice Emitted when an NFT bridge claim is completed
    event NFTClaimed(uint256 indexed lockId, address indexed relayer);
    /// @notice Emitted when a lock is cancelled after timeout
    event LockCancelled(uint256 indexed lockId, address indexed sender);
    /// @notice Emitted when a relayer is updated
    event RelayerUpdated(address indexed relayer, bool active);
    /// @notice Emitted when a chain support is updated
    event ChainSupportUpdated(uint256 indexed chainId, bool supported);

    error LockNotFound(uint256 lockId);
    error LockNotActive(uint256 lockId);
    error LockNotTimedOut(uint256 lockId);
    error InvalidBridgeProof();
    error UnsupportedChain(uint256 chainId);
    error NotRelayer(address caller);
    error NotLockOwner(address caller);
    error InsufficientFee(uint256 sent, uint256 required);
    error ZeroAddress();

    modifier onlyRelayer() {
        if (!_relayers[msg.sender]) revert NotRelayer(msg.sender);
        _;
    }

    constructor() {
        _supportedChains[1] = true;      // Ethereum
        _supportedChains[56] = true;     // BSC
        _supportedChains[137] = true;    // Polygon
        _supportedChains[8004] = true;   // ProbeChain Rydberg
    }

    /**
     * @notice Lock an NFT for cross-chain bridging
     * @param nftContract The NFT contract address
     * @param tokenId The token ID to bridge
     * @param destChain The destination chain ID
     * @return lockId The lock record identifier
     */
    function lockNFT(
        address nftContract,
        uint256 tokenId,
        uint256 destChain
    ) external payable nonReentrant whenNotPaused returns (uint256 lockId) {
        if (nftContract == address(0)) revert ZeroAddress();
        if (!_supportedChains[destChain]) revert UnsupportedChain(destChain);
        if (msg.value < bridgeFee) revert InsufficientFee(msg.value, bridgeFee);

        // Transfer NFT to this contract
        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);

        lockId = _nextLockId++;
        _locks[lockId] = LockRecord({
            id: lockId,
            nftContract: nftContract,
            tokenId: tokenId,
            sender: msg.sender,
            destChainId: destChain,
            status: LockStatus.Locked,
            lockedAt: block.timestamp,
            timeoutAt: block.timestamp + lockTimeout,
            bridgeProofHash: bytes32(0)
        });

        _userLocks[msg.sender].push(lockId);
        totalLocked++;

        emit NFTLocked(lockId, nftContract, tokenId, msg.sender, destChain);
    }

    /**
     * @notice Claim a bridged NFT with proof (relayer only)
     * @param lockId The lock to claim
     * @param bridgeProof The bridge proof data (verified off-chain)
     */
    function claimNFT(
        uint256 lockId,
        bytes calldata bridgeProof
    ) external nonReentrant whenNotPaused onlyRelayer {
        LockRecord storage lock = _locks[lockId];
        if (lock.id == 0) revert LockNotFound(lockId);
        if (lock.status != LockStatus.Locked) revert LockNotActive(lockId);
        if (bridgeProof.length == 0) revert InvalidBridgeProof();

        lock.status = LockStatus.Claimed;
        lock.bridgeProofHash = keccak256(bridgeProof);
        totalClaimed++;

        emit NFTClaimed(lockId, msg.sender);
    }

    /**
     * @notice Cancel a lock after timeout and return NFT to sender
     * @param lockId The lock to cancel
     */
    function cancelLock(uint256 lockId) external nonReentrant whenNotPaused {
        LockRecord storage lock = _locks[lockId];
        if (lock.id == 0) revert LockNotFound(lockId);
        if (lock.status != LockStatus.Locked) revert LockNotActive(lockId);
        if (lock.sender != msg.sender && msg.sender != owner()) revert NotLockOwner(msg.sender);
        if (block.timestamp < lock.timeoutAt) revert LockNotTimedOut(lockId);

        lock.status = LockStatus.Cancelled;

        // Return NFT to sender
        IERC721(lock.nftContract).safeTransferFrom(address(this), lock.sender, lock.tokenId);

        emit LockCancelled(lockId, lock.sender);
    }

    /**
     * @notice Get lock details
     * @param lockId The lock to query
     * @return lock The lock record
     */
    function getLock(uint256 lockId) external view returns (LockRecord memory lock) {
        if (_locks[lockId].id == 0) revert LockNotFound(lockId);
        return _locks[lockId];
    }

    /**
     * @notice Get all locks for a user
     * @param user The user address
     * @return ids Array of lock IDs
     */
    function getUserLocks(address user) external view returns (uint256[] memory ids) {
        return _userLocks[user];
    }

    /// @notice Set relayer status
    function setRelayer(address relayer, bool active) external onlyOwner {
        _relayers[relayer] = active;
        emit RelayerUpdated(relayer, active);
    }

    /// @notice Check if address is a relayer
    function isRelayer(address addr) external view returns (bool) { return _relayers[addr]; }

    /// @notice Set chain support
    function setSupportedChain(uint256 chainId, bool supported) external onlyOwner {
        _supportedChains[chainId] = supported;
        emit ChainSupportUpdated(chainId, supported);
    }

    /// @notice Set bridge fee
    function setBridgeFee(uint256 fee) external onlyOwner { bridgeFee = fee; }

    /// @notice Set lock timeout
    function setLockTimeout(uint256 timeout) external onlyOwner { lockTimeout = timeout; }

    /// @notice Withdraw collected fees
    function withdrawFees() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    /// @notice ERC721 receiver
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}
