// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MessageEscrow
 * @author ProbeChain
 * @notice Pay-to-read encrypted messaging. Senders attach a fee; recipients pay that fee
 *         (which goes to the sender) to decrypt and read the message.
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London).
 */

// ── Ownable ────────────────────────────────────────────────────────────────────
abstract contract Ownable {
    address private _owner;
    error OwnableUnauthorized(address account);
    error OwnableInvalidOwner(address owner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    function owner() public view virtual returns (address) { return _owner; }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorized(msg.sender); _; }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ── ReentrancyGuard ────────────────────────────────────────────────────────────
abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status != 1) revert ReentrancyGuardReentrantCall();
        _status = 2; _; _status = 1;
    }
}

// ── Pausable ───────────────────────────────────────────────────────────────────
abstract contract Pausable is Ownable {
    bool private _paused;
    error EnforcedPause(); error ExpectedPause();
    event Paused(address account); event Unpaused(address account);
    function paused() public view returns (bool) { return _paused; }
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    modifier whenPaused() { if (!_paused) revert ExpectedPause(); _; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

// ── MessageEscrow ──────────────────────────────────────────────────────────────
contract MessageEscrow is Ownable, ReentrancyGuard, Pausable {

    enum MsgStatus { Pending, Read, Deleted }

    struct Message {
        uint256 id;
        address sender;
        address recipient;
        string encryptedHash;
        uint256 readFee;
        uint256 createdAt;
        MsgStatus status;
    }

    uint256 public nextMessageId;
    uint256 public platformFeeBps = 200; // 2 %
    uint256 public accumulatedFees;

    mapping(uint256 => Message) public messages;
    mapping(address => uint256[]) private _inbox;
    mapping(address => uint256[]) private _outbox;

    // ── Events ─────────────────────────────────────────────────────────────────
    event MessageSent(uint256 indexed messageId, address indexed sender, address indexed recipient, uint256 readFee);
    event MessageRead(uint256 indexed messageId, address indexed reader, uint256 feePaid);
    event MessageDeleted(uint256 indexed messageId, address indexed deletedBy);
    event FeesWithdrawn(address indexed to, uint256 amount);
    event PlatformFeeUpdated(uint256 newBps);

    // ── Errors ─────────────────────────────────────────────────────────────────
    error InvalidRecipient();
    error EmptyHash();
    error MessageNotFound();
    error NotRecipient();
    error NotSenderOrRecipient();
    error AlreadyRead();
    error AlreadyDeleted();
    error IncorrectFee();
    error TransferFailed();
    error NoFeesToWithdraw();

    // ── Send ───────────────────────────────────────────────────────────────────
    /// @notice Send an encrypted message with a read fee.
    /// @param recipient     The intended reader.
    /// @param encryptedHash IPFS / Arweave hash of the encrypted payload.
    /// @param readFee       Fee the recipient must pay to read the message.
    function sendEncryptedMessage(
        address recipient,
        string calldata encryptedHash,
        uint256 readFee
    ) external payable whenNotPaused returns (uint256 messageId) {
        if (recipient == address(0) || recipient == msg.sender) revert InvalidRecipient();
        if (bytes(encryptedHash).length == 0) revert EmptyHash();

        messageId = nextMessageId++;
        messages[messageId] = Message({
            id: messageId,
            sender: msg.sender,
            recipient: recipient,
            encryptedHash: encryptedHash,
            readFee: readFee,
            createdAt: block.timestamp,
            status: MsgStatus.Pending
        });

        _inbox[recipient].push(messageId);
        _outbox[msg.sender].push(messageId);

        emit MessageSent(messageId, msg.sender, recipient, readFee);
    }

    // ── Read ───────────────────────────────────────────────────────────────────
    /// @notice Recipient reads a message by paying the read fee.
    /// @dev    Fee is forwarded to the sender minus platform cut.
    function readMessage(uint256 messageId) external payable nonReentrant whenNotPaused {
        Message storage m = messages[messageId];
        if (m.createdAt == 0) revert MessageNotFound();
        if (msg.sender != m.recipient) revert NotRecipient();
        if (m.status == MsgStatus.Read) revert AlreadyRead();
        if (m.status == MsgStatus.Deleted) revert AlreadyDeleted();
        if (msg.value != m.readFee) revert IncorrectFee();

        m.status = MsgStatus.Read;

        if (m.readFee > 0) {
            uint256 fee = (m.readFee * platformFeeBps) / 10_000;
            accumulatedFees += fee;
            uint256 payout = m.readFee - fee;
            (bool ok, ) = payable(m.sender).call{value: payout}("");
            if (!ok) revert TransferFailed();
        }

        emit MessageRead(messageId, msg.sender, m.readFee);
    }

    // ── Delete ─────────────────────────────────────────────────────────────────
    /// @notice Sender or recipient can delete (soft-delete) a message.
    function deleteMessage(uint256 messageId) external whenNotPaused {
        Message storage m = messages[messageId];
        if (m.createdAt == 0) revert MessageNotFound();
        if (msg.sender != m.sender && msg.sender != m.recipient) revert NotSenderOrRecipient();
        if (m.status == MsgStatus.Deleted) revert AlreadyDeleted();
        m.status = MsgStatus.Deleted;
        emit MessageDeleted(messageId, msg.sender);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────
    /// @notice Update platform fee (max 10 %).
    function setPlatformFee(uint256 newBps) external onlyOwner {
        if (newBps > 1000) revert IncorrectFee();
        platformFeeBps = newBps;
        emit PlatformFeeUpdated(newBps);
    }

    /// @notice Withdraw accumulated platform fees.
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = accumulatedFees;
        if (amount == 0) revert NoFeesToWithdraw();
        accumulatedFees = 0;
        (bool ok, ) = payable(owner()).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit FeesWithdrawn(owner(), amount);
    }

    // ── Views ──────────────────────────────────────────────────────────────────
    /// @notice Get all message IDs in a user's inbox.
    function getInbox(address user) external view returns (uint256[] memory) {
        return _inbox[user];
    }

    /// @notice Get all message IDs in a user's outbox.
    function getOutbox(address user) external view returns (uint256[] memory) {
        return _outbox[user];
    }

    /// @notice Get full message details (only sender or recipient).
    function getMessageDetails(uint256 messageId) external view returns (Message memory) {
        Message storage m = messages[messageId];
        if (m.createdAt == 0) revert MessageNotFound();
        if (msg.sender != m.sender && msg.sender != m.recipient && msg.sender != owner())
            revert NotSenderOrRecipient();
        return m;
    }
}
