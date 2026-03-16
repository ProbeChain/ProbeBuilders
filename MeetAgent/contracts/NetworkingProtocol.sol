// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NetworkingProtocol
 * @author ProbeChain
 * @notice Professional networking on-chain. Users create skill-based profiles,
 *         request/accept connections, endorse skills, and discover matches.
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

// ── NetworkingProtocol ─────────────────────────────────────────────────────────
contract NetworkingProtocol is Ownable, ReentrancyGuard, Pausable {

    struct UserProfile {
        address wallet;
        string[] skills;
        string[] interests;
        uint256 connectionCount;
        uint256 endorsementCount;
        uint256 createdAt;
    }

    enum ConnectionStatus { None, Pending, Accepted, Rejected }

    struct Connection {
        address requester;
        address target;
        ConnectionStatus status;
        uint256 timestamp;
    }

    uint256 public profileCount;
    uint256 public nextConnectionId;

    mapping(address => UserProfile) private _profiles;
    mapping(uint256 => Connection) public connections;
    mapping(address => uint256[]) private _connectionIds;
    // endorser -> user -> skill -> endorsed
    mapping(address => mapping(address => mapping(string => bool))) private _endorsed;
    // user -> skill -> endorsement count
    mapping(address => mapping(string => uint256)) public skillEndorsements;
    // quick lookup: user1 -> user2 -> connectionId
    mapping(address => mapping(address => uint256)) private _connectionLookup;

    address[] private _allUsers;

    // ── Events ─────────────────────────────────────────────────────────────────
    event ProfileCreated(address indexed user, uint256 skillCount, uint256 interestCount);
    event ProfileUpdated(address indexed user);
    event ConnectionRequested(uint256 indexed connId, address indexed requester, address indexed target);
    event ConnectionAccepted(uint256 indexed connId, address indexed accepter);
    event ConnectionRejected(uint256 indexed connId, address indexed rejecter);
    event SkillEndorsed(address indexed endorser, address indexed user, string skill, uint256 totalEndorsements);

    // ── Errors ─────────────────────────────────────────────────────────────────
    error ProfileAlreadyExists();
    error ProfileNotFound();
    error EmptyProfile();
    error CannotConnectSelf();
    error ConnectionAlreadyExists();
    error ConnectionNotFound();
    error NotConnectionTarget();
    error ConnectionNotPending();
    error AlreadyEndorsed();
    error SkillNotFound();
    error NotConnected();

    // ── Profile ────────────────────────────────────────────────────────────────
    /// @notice Create a professional profile.
    /// @param skills    Array of skill strings.
    /// @param interests Array of interest strings.
    function createProfile(
        string[] calldata skills,
        string[] calldata interests
    ) external whenNotPaused {
        if (_profiles[msg.sender].createdAt != 0) revert ProfileAlreadyExists();
        if (skills.length == 0) revert EmptyProfile();

        string[] memory storedSkills = new string[](skills.length);
        for (uint256 i = 0; i < skills.length; i++) storedSkills[i] = skills[i];

        string[] memory storedInterests = new string[](interests.length);
        for (uint256 i = 0; i < interests.length; i++) storedInterests[i] = interests[i];

        _profiles[msg.sender] = UserProfile({
            wallet: msg.sender,
            skills: storedSkills,
            interests: storedInterests,
            connectionCount: 0,
            endorsementCount: 0,
            createdAt: block.timestamp
        });

        _allUsers.push(msg.sender);
        profileCount++;

        emit ProfileCreated(msg.sender, skills.length, interests.length);
    }

    /// @notice Update skills and interests.
    function updateProfile(
        string[] calldata skills,
        string[] calldata interests
    ) external whenNotPaused {
        UserProfile storage p = _profiles[msg.sender];
        if (p.createdAt == 0) revert ProfileNotFound();

        delete p.skills;
        for (uint256 i = 0; i < skills.length; i++) p.skills.push(skills[i]);
        delete p.interests;
        for (uint256 i = 0; i < interests.length; i++) p.interests.push(interests[i]);

        emit ProfileUpdated(msg.sender);
    }

    // ── Connections ────────────────────────────────────────────────────────────
    /// @notice Request a connection with another user.
    function requestConnection(address target) external whenNotPaused returns (uint256 connId) {
        if (target == msg.sender) revert CannotConnectSelf();
        if (_profiles[target].createdAt == 0) revert ProfileNotFound();
        if (_profiles[msg.sender].createdAt == 0) revert ProfileNotFound();
        if (_connectionLookup[msg.sender][target] != 0) revert ConnectionAlreadyExists();

        connId = ++nextConnectionId; // start from 1
        connections[connId] = Connection({
            requester: msg.sender,
            target: target,
            status: ConnectionStatus.Pending,
            timestamp: block.timestamp
        });

        _connectionIds[msg.sender].push(connId);
        _connectionIds[target].push(connId);
        _connectionLookup[msg.sender][target] = connId;
        _connectionLookup[target][msg.sender] = connId;

        emit ConnectionRequested(connId, msg.sender, target);
    }

    /// @notice Accept a pending connection request.
    function acceptConnection(uint256 connId) external whenNotPaused {
        Connection storage c = connections[connId];
        if (c.timestamp == 0) revert ConnectionNotFound();
        if (msg.sender != c.target) revert NotConnectionTarget();
        if (c.status != ConnectionStatus.Pending) revert ConnectionNotPending();

        c.status = ConnectionStatus.Accepted;
        _profiles[c.requester].connectionCount++;
        _profiles[c.target].connectionCount++;

        emit ConnectionAccepted(connId, msg.sender);
    }

    /// @notice Reject a pending connection request.
    function rejectConnection(uint256 connId) external whenNotPaused {
        Connection storage c = connections[connId];
        if (c.timestamp == 0) revert ConnectionNotFound();
        if (msg.sender != c.target) revert NotConnectionTarget();
        if (c.status != ConnectionStatus.Pending) revert ConnectionNotPending();
        c.status = ConnectionStatus.Rejected;
        emit ConnectionRejected(connId, msg.sender);
    }

    // ── Endorsements ───────────────────────────────────────────────────────────
    /// @notice Endorse a connected user's skill.
    /// @param user  The user to endorse.
    /// @param skill The skill string to endorse (must match user's profile).
    function endorseSkill(address user, string calldata skill) external whenNotPaused {
        if (_profiles[msg.sender].createdAt == 0) revert ProfileNotFound();
        if (_profiles[user].createdAt == 0) revert ProfileNotFound();

        // Check connection exists and is accepted
        uint256 connId = _connectionLookup[msg.sender][user];
        if (connId == 0 || connections[connId].status != ConnectionStatus.Accepted)
            revert NotConnected();

        if (_endorsed[msg.sender][user][skill]) revert AlreadyEndorsed();

        // Verify user has this skill
        bool found;
        string[] storage skills = _profiles[user].skills;
        for (uint256 i = 0; i < skills.length; i++) {
            if (keccak256(bytes(skills[i])) == keccak256(bytes(skill))) {
                found = true;
                break;
            }
        }
        if (!found) revert SkillNotFound();

        _endorsed[msg.sender][user][skill] = true;
        skillEndorsements[user][skill]++;
        _profiles[user].endorsementCount++;

        emit SkillEndorsed(msg.sender, user, skill, skillEndorsements[user][skill]);
    }

    // ── Views ──────────────────────────────────────────────────────────────────
    /// @notice Get a user's profile.
    function getProfile(address user) external view returns (UserProfile memory) {
        if (_profiles[user].createdAt == 0) revert ProfileNotFound();
        return _profiles[user];
    }

    /// @notice Get connection IDs for a user.
    function getConnections(address user) external view returns (uint256[] memory) {
        return _connectionIds[user];
    }

    /// @notice Find matches — users sharing at least one skill or interest.
    /// @dev    Returns up to `limit` matching addresses (gas-bounded).
    function getMatches(address user, uint256 limit) external view returns (address[] memory) {
        UserProfile storage p = _profiles[user];
        if (p.createdAt == 0) revert ProfileNotFound();

        address[] memory temp = new address[](limit);
        uint256 count;

        for (uint256 u = 0; u < _allUsers.length && count < limit; u++) {
            address candidate = _allUsers[u];
            if (candidate == user) continue;
            UserProfile storage cp = _profiles[candidate];
            bool matched;

            for (uint256 i = 0; i < p.skills.length && !matched; i++) {
                for (uint256 j = 0; j < cp.skills.length && !matched; j++) {
                    if (keccak256(bytes(p.skills[i])) == keccak256(bytes(cp.skills[j]))) {
                        matched = true;
                    }
                }
            }
            for (uint256 i = 0; i < p.interests.length && !matched; i++) {
                for (uint256 j = 0; j < cp.interests.length && !matched; j++) {
                    if (keccak256(bytes(p.interests[i])) == keccak256(bytes(cp.interests[j]))) {
                        matched = true;
                    }
                }
            }

            if (matched) {
                temp[count] = candidate;
                count++;
            }
        }

        address[] memory result = new address[](count);
        for (uint256 i = 0; i < count; i++) result[i] = temp[i];
        return result;
    }
}
