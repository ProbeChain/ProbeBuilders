// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title AgentMessaging — Agent-to-agent messaging on ProbeChain
/// @author ProbeBuilders
/// @notice Send encrypted messages between agents, create group channels, acknowledge delivery
/// @dev Message payloads stored as events for off-chain indexing. Rydberg Testnet (Chain ID 8004).
contract AgentMessaging {
    // ─── Enums & Structs ─────────────────────────────────────────────────
    enum ChannelStatus { Active, Closed }
    enum MessageStatus { Sent, Acknowledged, Expired }

    struct Message {
        uint256 id;
        address sender;
        address recipient;
        uint256 channelId; // 0 = direct message
        bytes32 payloadHash;
        MessageStatus status;
        uint256 sentAt;
        uint256 acknowledgedAt;
        uint256 expiresAt;
    }

    struct Channel {
        uint256 id;
        string name;
        address creator;
        ChannelStatus status;
        uint256 memberCount;
        uint256 messageCount;
        uint256 createdAt;
        uint256 closedAt;
    }

    // ─── State ───────────────────────────────────────────────────────────
    address public owner;
    bool public paused;

    uint256 private _nextMessageId = 1;
    uint256 private _nextChannelId = 1;

    mapping(uint256 => Message) public messages;
    mapping(uint256 => Channel) public channels;
    mapping(uint256 => mapping(address => bool)) public channelMembers;
    mapping(uint256 => address[]) private _channelMemberList;
    mapping(address => uint256[]) private _sentMessages;
    mapping(address => uint256[]) private _receivedMessages;
    mapping(address => uint256[]) private _userChannels;

    uint256 public totalMessages;
    uint256 public totalChannels;
    uint256 public messageFee;
    uint256 public defaultExpiry = 7 days;

    // ─── Events ──────────────────────────────────────────────────────────
    event MessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address indexed recipient,
        uint256 channelId,
        bytes encryptedPayload,
        uint256 expiresAt
    );
    event MessageAcknowledged(uint256 indexed messageId, address indexed recipient, uint256 timestamp);
    event ChannelCreated(uint256 indexed channelId, string name, address indexed creator, address[] members);
    event ChannelClosed(uint256 indexed channelId, address indexed closedBy);
    event MemberAdded(uint256 indexed channelId, address indexed member, address indexed addedBy);
    event MemberRemoved(uint256 indexed channelId, address indexed member, address indexed removedBy);
    event MessageFeeUpdated(uint256 oldFee, uint256 newFee);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "AgentMessaging: not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "AgentMessaging: paused");
        _;
    }

    modifier onlyChannelMember(uint256 channelId) {
        require(channelMembers[channelId][msg.sender], "AgentMessaging: not a channel member");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    /// @param _messageFee Fee in wei per message (0 = free)
    constructor(uint256 _messageFee) {
        owner = msg.sender;
        messageFee = _messageFee;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Messaging ───────────────────────────────────────────────────────

    /// @notice Send a direct encrypted message to another agent
    /// @param toAgent Recipient address
    /// @param encryptedPayload Encrypted message content
    /// @return messageId The message ID
    function sendMessage(
        address toAgent,
        bytes calldata encryptedPayload
    ) external payable whenNotPaused returns (uint256 messageId) {
        require(toAgent != address(0) && toAgent != msg.sender, "AgentMessaging: invalid recipient");
        require(encryptedPayload.length > 0 && encryptedPayload.length <= 4096, "AgentMessaging: invalid payload");
        require(msg.value >= messageFee, "AgentMessaging: insufficient fee");

        messageId = _nextMessageId++;
        uint256 expiresAt = block.timestamp + defaultExpiry;

        messages[messageId] = Message({
            id: messageId,
            sender: msg.sender,
            recipient: toAgent,
            channelId: 0,
            payloadHash: keccak256(encryptedPayload),
            status: MessageStatus.Sent,
            sentAt: block.timestamp,
            acknowledgedAt: 0,
            expiresAt: expiresAt
        });

        _sentMessages[msg.sender].push(messageId);
        _receivedMessages[toAgent].push(messageId);
        totalMessages++;

        emit MessageSent(messageId, msg.sender, toAgent, 0, encryptedPayload, expiresAt);
    }

    /// @notice Send a message to a channel
    /// @param channelId The channel
    /// @param encryptedPayload Encrypted message content
    /// @return messageId The message ID
    function sendChannelMessage(
        uint256 channelId,
        bytes calldata encryptedPayload
    ) external payable whenNotPaused onlyChannelMember(channelId) returns (uint256 messageId) {
        Channel storage ch = channels[channelId];
        require(ch.createdAt != 0, "AgentMessaging: channel not found");
        require(ch.status == ChannelStatus.Active, "AgentMessaging: channel closed");
        require(encryptedPayload.length > 0 && encryptedPayload.length <= 4096, "AgentMessaging: invalid payload");
        require(msg.value >= messageFee, "AgentMessaging: insufficient fee");

        messageId = _nextMessageId++;
        uint256 expiresAt = block.timestamp + defaultExpiry;

        messages[messageId] = Message({
            id: messageId,
            sender: msg.sender,
            recipient: address(0), // broadcast to channel
            channelId: channelId,
            payloadHash: keccak256(encryptedPayload),
            status: MessageStatus.Sent,
            sentAt: block.timestamp,
            acknowledgedAt: 0,
            expiresAt: expiresAt
        });

        ch.messageCount++;
        _sentMessages[msg.sender].push(messageId);
        totalMessages++;

        emit MessageSent(messageId, msg.sender, address(0), channelId, encryptedPayload, expiresAt);
    }

    /// @notice Acknowledge receipt of a message
    /// @param messageId The message to acknowledge
    function acknowledgeMessage(uint256 messageId) external {
        Message storage m = messages[messageId];
        require(m.sentAt != 0, "AgentMessaging: message not found");
        require(
            m.recipient == msg.sender || (m.channelId != 0 && channelMembers[m.channelId][msg.sender]),
            "AgentMessaging: not authorized"
        );
        require(m.status == MessageStatus.Sent, "AgentMessaging: already acknowledged");
        require(block.timestamp <= m.expiresAt, "AgentMessaging: message expired");

        m.status = MessageStatus.Acknowledged;
        m.acknowledgedAt = block.timestamp;

        emit MessageAcknowledged(messageId, msg.sender, block.timestamp);
    }

    // ─── Channel Management ──────────────────────────────────────────────

    /// @notice Create a group communication channel
    /// @param name Channel name
    /// @param members Initial member addresses
    /// @return channelId The new channel ID
    function createChannel(
        string calldata name,
        address[] calldata members
    ) external whenNotPaused returns (uint256 channelId) {
        require(bytes(name).length > 0 && bytes(name).length <= 128, "AgentMessaging: invalid name");
        require(members.length >= 1 && members.length <= 100, "AgentMessaging: invalid member count");

        channelId = _nextChannelId++;

        channels[channelId] = Channel({
            id: channelId,
            name: name,
            creator: msg.sender,
            status: ChannelStatus.Active,
            memberCount: members.length + 1, // +1 for creator
            messageCount: 0,
            createdAt: block.timestamp,
            closedAt: 0
        });

        // Add creator
        channelMembers[channelId][msg.sender] = true;
        _channelMemberList[channelId].push(msg.sender);
        _userChannels[msg.sender].push(channelId);

        // Add members
        for (uint256 i; i < members.length; ++i) {
            if (members[i] != address(0) && members[i] != msg.sender && !channelMembers[channelId][members[i]]) {
                channelMembers[channelId][members[i]] = true;
                _channelMemberList[channelId].push(members[i]);
                _userChannels[members[i]].push(channelId);
            }
        }

        totalChannels++;

        emit ChannelCreated(channelId, name, msg.sender, members);
    }

    /// @notice Add a member to a channel (creator only)
    /// @param channelId The channel
    /// @param member The member to add
    function addMember(uint256 channelId, address member) external {
        Channel storage ch = channels[channelId];
        require(ch.createdAt != 0 && ch.status == ChannelStatus.Active, "AgentMessaging: invalid channel");
        require(ch.creator == msg.sender, "AgentMessaging: not channel creator");
        require(!channelMembers[channelId][member], "AgentMessaging: already a member");
        require(member != address(0), "AgentMessaging: zero address");

        channelMembers[channelId][member] = true;
        _channelMemberList[channelId].push(member);
        _userChannels[member].push(channelId);
        ch.memberCount++;

        emit MemberAdded(channelId, member, msg.sender);
    }

    /// @notice Close a channel (creator only)
    /// @param channelId The channel to close
    function closeChannel(uint256 channelId) external {
        Channel storage ch = channels[channelId];
        require(ch.createdAt != 0, "AgentMessaging: channel not found");
        require(ch.creator == msg.sender, "AgentMessaging: not channel creator");
        require(ch.status == ChannelStatus.Active, "AgentMessaging: already closed");

        ch.status = ChannelStatus.Closed;
        ch.closedAt = block.timestamp;

        emit ChannelClosed(channelId, msg.sender);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Get messages sent by an address
    function getSentMessages(address sender) external view returns (uint256[] memory) {
        return _sentMessages[sender];
    }

    /// @notice Get messages received by an address
    function getReceivedMessages(address recipient) external view returns (uint256[] memory) {
        return _receivedMessages[recipient];
    }

    /// @notice Get channels for a user
    function getUserChannels(address user) external view returns (uint256[] memory) {
        return _userChannels[user];
    }

    /// @notice Get channel members
    function getChannelMembers(uint256 channelId) external view returns (address[] memory) {
        return _channelMemberList[channelId];
    }

    /// @notice Check if message is expired
    function isMessageExpired(uint256 messageId) external view returns (bool) {
        return messages[messageId].expiresAt > 0 && block.timestamp > messages[messageId].expiresAt;
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    function setMessageFee(uint256 newFee) external onlyOwner {
        uint256 old = messageFee;
        messageFee = newFee;
        emit MessageFeeUpdated(old, newFee);
    }

    function setDefaultExpiry(uint256 newExpiry) external onlyOwner {
        require(newExpiry >= 1 hours, "AgentMessaging: expiry too short");
        defaultExpiry = newExpiry;
    }

    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    function withdrawFees() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "AgentMessaging: no balance");
        (bool ok, ) = payable(owner).call{value: bal}("");
        require(ok, "AgentMessaging: transfer failed");
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "AgentMessaging: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
