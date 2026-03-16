// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PaymentStream
 * @author ProbeChain
 * @notice Per-second payment streaming for continuous compensation
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

contract PaymentStream is Ownable, ReentrancyGuard, Pausable {
    /// @notice Stream status
    enum StreamStatus { Active, Completed, Cancelled }

    /// @notice Payment stream record
    struct Stream {
        uint256 id;
        address sender;
        address recipient;
        uint256 deposit;
        uint256 withdrawn;
        uint256 startTime;
        uint256 stopTime;
        uint256 ratePerSecond;
        StreamStatus status;
        uint256 createdAt;
    }

    /// @dev Stream counter
    uint256 private _nextStreamId;

    /// @dev Stream ID => Stream
    mapping(uint256 => Stream) private _streams;

    /// @dev All stream IDs
    uint256[] private _streamIds;

    /// @dev Sender => stream IDs
    mapping(address => uint256[]) private _senderStreams;

    /// @dev Recipient => stream IDs
    mapping(address => uint256[]) private _recipientStreams;

    /// @dev Total value locked in active streams
    uint256 public totalLocked;

    // ───────── Events ─────────

    /// @notice Emitted when a stream is created
    event StreamCreated(uint256 indexed streamId, address indexed sender, address indexed recipient, uint256 deposit, uint256 startTime, uint256 stopTime);

    /// @notice Emitted when tokens are withdrawn from a stream
    event WithdrawnFromStream(uint256 indexed streamId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a stream is cancelled
    event StreamCancelled(uint256 indexed streamId, uint256 recipientAmount, uint256 senderRefund);

    /// @notice Emitted when a stream completes naturally
    event StreamCompleted(uint256 indexed streamId);

    // ───────── Constructor ─────────

    constructor() {
        _nextStreamId = 1;
    }

    // ───────── Admin ─────────

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Create a payment stream
    /// @param recipient The address to receive streamed funds
    /// @param startTime When the stream starts (unix timestamp)
    /// @param stopTime When the stream ends (unix timestamp)
    /// @return streamId The new stream ID
    function createStream(
        address recipient,
        uint256 startTime,
        uint256 stopTime
    ) external payable whenNotPaused returns (uint256 streamId) {
        require(recipient != address(0), "Stream: zero recipient");
        require(recipient != msg.sender, "Stream: self stream");
        require(msg.value > 0, "Stream: zero deposit");
        require(startTime >= block.timestamp, "Stream: start in past");
        require(stopTime > startTime, "Stream: stop <= start");

        uint256 duration = stopTime - startTime;
        require(msg.value >= duration, "Stream: deposit < duration");

        uint256 ratePerSecond = msg.value / duration;
        require(ratePerSecond > 0, "Stream: zero rate");

        // Adjust deposit to be evenly divisible
        uint256 adjustedDeposit = ratePerSecond * duration;
        uint256 refund = msg.value - adjustedDeposit;

        streamId = _nextStreamId++;

        _streams[streamId] = Stream({
            id: streamId,
            sender: msg.sender,
            recipient: recipient,
            deposit: adjustedDeposit,
            withdrawn: 0,
            startTime: startTime,
            stopTime: stopTime,
            ratePerSecond: ratePerSecond,
            status: StreamStatus.Active,
            createdAt: block.timestamp
        });

        _streamIds.push(streamId);
        _senderStreams[msg.sender].push(streamId);
        _recipientStreams[recipient].push(streamId);
        totalLocked += adjustedDeposit;

        // Refund dust
        if (refund > 0) {
            (bool sent, ) = msg.sender.call{value: refund}("");
            require(sent, "Stream: refund failed");
        }

        emit StreamCreated(streamId, msg.sender, recipient, adjustedDeposit, startTime, stopTime);
    }

    /// @notice Withdraw available streamed funds
    /// @param streamId The stream to withdraw from
    /// @param amount The amount to withdraw
    function withdrawFromStream(
        uint256 streamId,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        Stream storage s = _streams[streamId];
        require(s.id != 0, "Stream: not found");
        require(s.status == StreamStatus.Active, "Stream: not active");
        require(msg.sender == s.recipient, "Stream: not recipient");

        uint256 available = _availableBalance(s);
        require(amount > 0 && amount <= available, "Stream: invalid amount");

        s.withdrawn += amount;
        totalLocked -= amount;

        // Check if stream is fully withdrawn
        if (s.withdrawn >= s.deposit) {
            s.status = StreamStatus.Completed;
            emit StreamCompleted(streamId);
        }

        (bool sent, ) = s.recipient.call{value: amount}("");
        require(sent, "Stream: transfer failed");

        emit WithdrawnFromStream(streamId, s.recipient, amount);
    }

    /// @notice Cancel a stream (sender or recipient)
    /// @param streamId The stream to cancel
    function cancelStream(uint256 streamId) external whenNotPaused nonReentrant {
        Stream storage s = _streams[streamId];
        require(s.id != 0, "Stream: not found");
        require(s.status == StreamStatus.Active, "Stream: not active");
        require(
            msg.sender == s.sender || msg.sender == s.recipient,
            "Stream: not party"
        );

        uint256 recipientBalance = _availableBalance(s);
        uint256 senderBalance = s.deposit - s.withdrawn - recipientBalance;

        s.status = StreamStatus.Cancelled;
        totalLocked -= (s.deposit - s.withdrawn);

        // Pay recipient their earned amount
        if (recipientBalance > 0) {
            (bool sent1, ) = s.recipient.call{value: recipientBalance}("");
            require(sent1, "Stream: recipient transfer failed");
        }

        // Refund sender the unearned amount
        if (senderBalance > 0) {
            (bool sent2, ) = s.sender.call{value: senderBalance}("");
            require(sent2, "Stream: sender refund failed");
        }

        emit StreamCancelled(streamId, recipientBalance, senderBalance);
    }

    // ───────── Internal ─────────

    /// @dev Calculate available balance for recipient
    function _availableBalance(Stream memory s) internal view returns (uint256) {
        if (block.timestamp <= s.startTime) return 0;

        uint256 elapsed;
        if (block.timestamp >= s.stopTime) {
            elapsed = s.stopTime - s.startTime;
        } else {
            elapsed = block.timestamp - s.startTime;
        }

        uint256 totalEarned = s.ratePerSecond * elapsed;
        if (totalEarned > s.deposit) totalEarned = s.deposit;

        return totalEarned - s.withdrawn;
    }

    // ───────── View Functions ─────────

    /// @notice Get stream details
    function getStream(uint256 streamId) external view returns (Stream memory) {
        require(_streams[streamId].id != 0, "Stream: not found");
        return _streams[streamId];
    }

    /// @notice Get available balance for withdrawal
    function availableBalance(uint256 streamId) external view returns (uint256) {
        Stream memory s = _streams[streamId];
        if (s.id == 0 || s.status != StreamStatus.Active) return 0;
        return _availableBalance(s);
    }

    /// @notice Get sender's stream IDs
    function getSenderStreams(address sender) external view returns (uint256[] memory) {
        return _senderStreams[sender];
    }

    /// @notice Get recipient's stream IDs
    function getRecipientStreams(address recipient) external view returns (uint256[] memory) {
        return _recipientStreams[recipient];
    }

    /// @notice Total streams created
    function totalStreams() external view returns (uint256) {
        return _nextStreamId - 1;
    }
}
