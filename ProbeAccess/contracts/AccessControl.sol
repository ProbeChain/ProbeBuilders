// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AccessControl
 * @author ProbeChain Team
 * @notice Hierarchical role-based access control system for ProbeChain Rydberg Testnet
 * @dev Create roles with admin inheritance, grant/revoke per account, role enumeration
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

contract AccessControl is Ownable, ReentrancyGuard, Pausable {
    /// @notice Role data
    struct RoleData {
        bytes32 roleId;
        string roleName;
        bytes32 adminRole;
        uint256 memberCount;
        bool exists;
    }

    /// @notice Member data with role context
    struct MemberInfo {
        address account;
        uint256 grantedAt;
        address grantedBy;
    }

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    mapping(bytes32 => RoleData) private _roles;
    mapping(bytes32 => mapping(address => bool)) private _roleMembers;
    mapping(bytes32 => mapping(address => MemberInfo)) private _memberInfo;
    mapping(address => bytes32[]) private _accountRoles;
    bytes32[] private _allRoles;

    uint256 public totalRoles;

    /// @notice Emitted when a role is created
    event RoleCreated(bytes32 indexed roleId, string roleName, bytes32 indexed adminRole);
    /// @notice Emitted when a role is granted
    event RoleGranted(bytes32 indexed roleId, address indexed account, address indexed sender);
    /// @notice Emitted when a role is revoked
    event RoleRevoked(bytes32 indexed roleId, address indexed account, address indexed sender);
    /// @notice Emitted when admin role is changed
    event RoleAdminChanged(bytes32 indexed roleId, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    error RoleNotFound(bytes32 roleId);
    error RoleAlreadyExists(bytes32 roleId);
    error AccountAlreadyHasRole(bytes32 roleId, address account);
    error AccountDoesNotHaveRole(bytes32 roleId, address account);
    error UnauthorizedAdmin(address caller, bytes32 roleId);
    error EmptyRoleName();

    constructor() {
        // Set up default admin role
        _roles[DEFAULT_ADMIN_ROLE] = RoleData({
            roleId: DEFAULT_ADMIN_ROLE,
            roleName: "DEFAULT_ADMIN",
            adminRole: DEFAULT_ADMIN_ROLE,
            memberCount: 1,
            exists: true
        });
        _roleMembers[DEFAULT_ADMIN_ROLE][msg.sender] = true;
        _memberInfo[DEFAULT_ADMIN_ROLE][msg.sender] = MemberInfo({
            account: msg.sender,
            grantedAt: block.timestamp,
            grantedBy: address(0)
        });
        _accountRoles[msg.sender].push(DEFAULT_ADMIN_ROLE);
        _allRoles.push(DEFAULT_ADMIN_ROLE);
        totalRoles = 1;
    }

    /**
     * @notice Check if caller has admin role for a given role
     */
    modifier onlyRoleAdmin(bytes32 roleId) {
        bytes32 adminRole = _roles[roleId].adminRole;
        if (!_roleMembers[adminRole][msg.sender] && msg.sender != owner()) {
            revert UnauthorizedAdmin(msg.sender, roleId);
        }
        _;
    }

    /**
     * @notice Create a new role
     * @param roleName Human-readable role name
     * @param adminRole The admin role that can manage this role
     * @return roleId The created role identifier
     */
    function createRole(
        string calldata roleName,
        bytes32 adminRole
    ) external whenNotPaused returns (bytes32 roleId) {
        if (bytes(roleName).length == 0) revert EmptyRoleName();

        roleId = keccak256(abi.encodePacked(roleName));
        if (_roles[roleId].exists) revert RoleAlreadyExists(roleId);

        // Admin role must exist (or be DEFAULT_ADMIN_ROLE)
        if (adminRole != DEFAULT_ADMIN_ROLE && !_roles[adminRole].exists) {
            revert RoleNotFound(adminRole);
        }

        // Caller must be admin of the admin role
        if (!_roleMembers[adminRole][msg.sender] && msg.sender != owner()) {
            revert UnauthorizedAdmin(msg.sender, adminRole);
        }

        _roles[roleId] = RoleData({
            roleId: roleId,
            roleName: roleName,
            adminRole: adminRole,
            memberCount: 0,
            exists: true
        });

        _allRoles.push(roleId);
        totalRoles++;

        emit RoleCreated(roleId, roleName, adminRole);
    }

    /**
     * @notice Grant a role to an account
     * @param roleId The role to grant
     * @param account The account to grant to
     */
    function grantRole(bytes32 roleId, address account) external whenNotPaused onlyRoleAdmin(roleId) {
        if (!_roles[roleId].exists) revert RoleNotFound(roleId);
        if (_roleMembers[roleId][account]) revert AccountAlreadyHasRole(roleId, account);

        _roleMembers[roleId][account] = true;
        _memberInfo[roleId][account] = MemberInfo({
            account: account,
            grantedAt: block.timestamp,
            grantedBy: msg.sender
        });
        _roles[roleId].memberCount++;
        _accountRoles[account].push(roleId);

        emit RoleGranted(roleId, account, msg.sender);
    }

    /**
     * @notice Revoke a role from an account
     * @param roleId The role to revoke
     * @param account The account to revoke from
     */
    function revokeRole(bytes32 roleId, address account) external whenNotPaused onlyRoleAdmin(roleId) {
        if (!_roles[roleId].exists) revert RoleNotFound(roleId);
        if (!_roleMembers[roleId][account]) revert AccountDoesNotHaveRole(roleId, account);

        _roleMembers[roleId][account] = false;
        _roles[roleId].memberCount--;

        emit RoleRevoked(roleId, account, msg.sender);
    }

    /**
     * @notice Renounce a role (self-revoke)
     * @param roleId The role to renounce
     */
    function renounceRole(bytes32 roleId) external whenNotPaused {
        if (!_roleMembers[roleId][msg.sender]) revert AccountDoesNotHaveRole(roleId, msg.sender);
        _roleMembers[roleId][msg.sender] = false;
        _roles[roleId].memberCount--;
        emit RoleRevoked(roleId, msg.sender, msg.sender);
    }

    /**
     * @notice Check if an account has a specific role
     * @param roleId The role to check
     * @param account The account to check
     * @return hasIt True if the account has the role
     */
    function hasRole(bytes32 roleId, address account) external view returns (bool hasIt) {
        return _roleMembers[roleId][account];
    }

    /**
     * @notice Get role data
     * @param roleId The role to query
     * @return role The role data
     */
    function getRole(bytes32 roleId) external view returns (RoleData memory role) {
        if (!_roles[roleId].exists) revert RoleNotFound(roleId);
        return _roles[roleId];
    }

    /**
     * @notice Get member info
     * @param roleId The role
     * @param account The account
     * @return info The member info
     */
    function getMemberInfo(bytes32 roleId, address account) external view returns (MemberInfo memory info) {
        return _memberInfo[roleId][account];
    }

    /**
     * @notice Get all roles for an account
     * @param account The account address
     * @return roles Array of role IDs
     */
    function getAccountRoles(address account) external view returns (bytes32[] memory roles) {
        return _accountRoles[account];
    }

    /**
     * @notice Get all registered roles
     * @return roles Array of all role IDs
     */
    function getAllRoles() external view returns (bytes32[] memory roles) {
        return _allRoles;
    }

    /**
     * @notice Change the admin role for a role
     * @param roleId The role to update
     * @param newAdminRole The new admin role
     */
    function setRoleAdmin(bytes32 roleId, bytes32 newAdminRole) external onlyOwner {
        if (!_roles[roleId].exists) revert RoleNotFound(roleId);
        bytes32 previousAdmin = _roles[roleId].adminRole;
        _roles[roleId].adminRole = newAdminRole;
        emit RoleAdminChanged(roleId, previousAdmin, newAdminRole);
    }

    /**
     * @notice Compute role ID from name
     * @param roleName The role name
     * @return roleId The computed role ID
     */
    function computeRoleId(string calldata roleName) external pure returns (bytes32 roleId) {
        return keccak256(abi.encodePacked(roleName));
    }
}
