// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GroupChat
 * @author ProbeChain Team
 * @notice On-chain group messaging with admin controls on ProbeChain Rydberg Testnet
 * @dev Create groups, send message hashes, manage members, admin-controlled moderation
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

contract GroupChat is Ownable, ReentrancyGuard, Pausable {
    /// @notice Group data
    struct Group {
        uint256 id;
        string name;
        address admin;
        uint256 memberCount;
        uint256 messageCount;
        uint256 createdAt;
        bool active;
    }

    /// @notice Message record (content stored off-chain, hash on-chain)
    struct Message {
        uint256 id;
        uint256 groupId;
        address sender;
        bytes32 contentHash;
        uint256 timestamp;
        bool deleted;
    }

    mapping(uint256 => Group) private _groups;
    mapping(uint256 => mapping(address => bool)) private _members;
    mapping(uint256 => mapping(uint256 => Message)) private _messages;
    mapping(address => uint256[]) private _userGroups;

    uint256 private _nextGroupId = 1;
    uint256 private _nextMessageId = 1;
    uint256 public totalGroups;
    uint256 public totalMessages;
    uint256 public maxGroupMembers = 500;
    uint256 public maxMessageLength = 32; // hash-based, this is just for metadata

    /// @notice Emitted when a group is created
    event GroupCreated(uint256 indexed groupId, string name, address indexed admin, uint256 memberCount);
    /// @notice Emitted when a message is sent
    event MessageSent(uint256 indexed groupId, uint256 indexed messageId, address indexed sender, bytes32 contentHash);
    /// @notice Emitted when a member is added
    event MemberAdded(uint256 indexed groupId, address indexed member, address indexed addedBy);
    /// @notice Emitted when a member is removed
    event MemberRemoved(uint256 indexed groupId, address indexed member, address indexed removedBy);
    /// @notice Emitted when a message is deleted
    event MessageDeleted(uint256 indexed groupId, uint256 indexed messageId);
    /// @notice Emitted when group admin is transferred
    event AdminTransferred(uint256 indexed groupId, address indexed oldAdmin, address indexed newAdmin);

    error GroupNotFound(uint256 groupId);
    error GroupNotActive(uint256 groupId);
    error NotGroupMember(uint256 groupId, address account);
    error NotGroupAdmin(uint256 groupId, address account);
    error AlreadyMember(uint256 groupId, address account);
    error NotMember(uint256 groupId, address account);
    error GroupFull(uint256 groupId);
    error EmptyName();
    error EmptyMembers();
    error MessageNotFound(uint256 messageId);
    error CannotRemoveAdmin();

    /**
     * @notice Create a new chat group
     * @param name The group name
     * @param members Initial member addresses (creator is added automatically)
     * @return groupId The created group ID
     */
    function createGroup(
        string calldata name,
        address[] calldata members
    ) external whenNotPaused returns (uint256 groupId) {
        if (bytes(name).length == 0) revert EmptyName();

        groupId = _nextGroupId++;

        _groups[groupId] = Group({
            id: groupId,
            name: name,
            admin: msg.sender,
            memberCount: 1,
            messageCount: 0,
            createdAt: block.timestamp,
            active: true
        });

        // Add creator as member
        _members[groupId][msg.sender] = true;
        _userGroups[msg.sender].push(groupId);

        // Add initial members
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] != msg.sender && !_members[groupId][members[i]]) {
                _members[groupId][members[i]] = true;
                _userGroups[members[i]].push(groupId);
                _groups[groupId].memberCount++;
            }
        }

        totalGroups++;
        emit GroupCreated(groupId, name, msg.sender, _groups[groupId].memberCount);
    }

    /**
     * @notice Send a message to a group (content hash stored on-chain)
     * @param groupId The group to message
     * @param contentHash The hash of the message content (content stored off-chain)
     * @return messageId The message identifier
     */
    function sendMessage(
        uint256 groupId,
        bytes32 contentHash
    ) external whenNotPaused returns (uint256 messageId) {
        Group storage group = _groups[groupId];
        if (group.id == 0) revert GroupNotFound(groupId);
        if (!group.active) revert GroupNotActive(groupId);
        if (!_members[groupId][msg.sender]) revert NotGroupMember(groupId, msg.sender);

        messageId = _nextMessageId++;
        _messages[groupId][messageId] = Message({
            id: messageId,
            groupId: groupId,
            sender: msg.sender,
            contentHash: contentHash,
            timestamp: block.timestamp,
            deleted: false
        });

        group.messageCount++;
        totalMessages++;

        emit MessageSent(groupId, messageId, msg.sender, contentHash);
    }

    /**
     * @notice Add a member to a group (admin only)
     * @param groupId The group ID
     * @param member The address to add
     */
    function addMember(uint256 groupId, address member) external whenNotPaused {
        Group storage group = _groups[groupId];
        if (group.id == 0) revert GroupNotFound(groupId);
        if (group.admin != msg.sender) revert NotGroupAdmin(groupId, msg.sender);
        if (_members[groupId][member]) revert AlreadyMember(groupId, member);
        if (group.memberCount >= maxGroupMembers) revert GroupFull(groupId);

        _members[groupId][member] = true;
        _userGroups[member].push(groupId);
        group.memberCount++;

        emit MemberAdded(groupId, member, msg.sender);
    }

    /**
     * @notice Remove a member from a group (admin only)
     * @param groupId The group ID
     * @param member The address to remove
     */
    function removeMember(uint256 groupId, address member) external whenNotPaused {
        Group storage group = _groups[groupId];
        if (group.id == 0) revert GroupNotFound(groupId);
        if (group.admin != msg.sender) revert NotGroupAdmin(groupId, msg.sender);
        if (member == group.admin) revert CannotRemoveAdmin();
        if (!_members[groupId][member]) revert NotMember(groupId, member);

        _members[groupId][member] = false;
        group.memberCount--;

        emit MemberRemoved(groupId, member, msg.sender);
    }

    /**
     * @notice Leave a group voluntarily
     * @param groupId The group to leave
     */
    function leaveGroup(uint256 groupId) external whenNotPaused {
        Group storage group = _groups[groupId];
        if (group.id == 0) revert GroupNotFound(groupId);
        if (!_members[groupId][msg.sender]) revert NotMember(groupId, msg.sender);
        if (msg.sender == group.admin) revert CannotRemoveAdmin();

        _members[groupId][msg.sender] = false;
        group.memberCount--;

        emit MemberRemoved(groupId, msg.sender, msg.sender);
    }

    /**
     * @notice Delete a message (sender or admin)
     * @param groupId The group ID
     * @param messageId The message to delete
     */
    function deleteMessage(uint256 groupId, uint256 messageId) external whenNotPaused {
        Group storage group = _groups[groupId];
        if (group.id == 0) revert GroupNotFound(groupId);
        Message storage msg_ = _messages[groupId][messageId];
        if (msg_.id == 0) revert MessageNotFound(messageId);
        require(msg_.sender == msg.sender || group.admin == msg.sender, "Unauthorized");

        msg_.deleted = true;
        emit MessageDeleted(groupId, messageId);
    }

    /**
     * @notice Transfer admin rights
     * @param groupId The group ID
     * @param newAdmin The new admin address
     */
    function transferAdmin(uint256 groupId, address newAdmin) external whenNotPaused {
        Group storage group = _groups[groupId];
        if (group.id == 0) revert GroupNotFound(groupId);
        if (group.admin != msg.sender) revert NotGroupAdmin(groupId, msg.sender);
        if (!_members[groupId][newAdmin]) revert NotMember(groupId, newAdmin);

        address oldAdmin = group.admin;
        group.admin = newAdmin;
        emit AdminTransferred(groupId, oldAdmin, newAdmin);
    }

    /// @notice Get group info
    function getGroup(uint256 groupId) external view returns (Group memory) {
        if (_groups[groupId].id == 0) revert GroupNotFound(groupId);
        return _groups[groupId];
    }

    /// @notice Check membership
    function isMember(uint256 groupId, address account) external view returns (bool) {
        return _members[groupId][account];
    }

    /// @notice Get message
    function getMessage(uint256 groupId, uint256 messageId) external view returns (Message memory) {
        return _messages[groupId][messageId];
    }

    /// @notice Get user groups
    function getUserGroups(address user) external view returns (uint256[] memory) {
        return _userGroups[user];
    }

    /// @notice Deactivate group
    function deactivateGroup(uint256 groupId) external {
        Group storage group = _groups[groupId];
        if (group.id == 0) revert GroupNotFound(groupId);
        require(group.admin == msg.sender || msg.sender == owner(), "Unauthorized");
        group.active = false;
    }

    /// @notice Set max group members
    function setMaxGroupMembers(uint256 max) external onlyOwner { maxGroupMembers = max; }
}
