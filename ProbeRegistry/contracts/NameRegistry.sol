// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NameRegistry
 * @author ProbeChain Team
 * @notice ENS-like universal name registry for ProbeChain Rydberg Testnet
 * @dev Register, transfer, resolve names to addresses with custom resolvers and metadata
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

contract NameRegistry is Ownable, ReentrancyGuard, Pausable {
    /// @notice Name record
    struct NameRecord {
        string name;
        address recordOwner;
        address resolver;
        string metadata;
        uint256 registeredAt;
        uint256 expiresAt;
        bool active;
    }

    mapping(bytes32 => NameRecord) private _names;
    mapping(address => bytes32[]) private _ownerNames;
    mapping(address => bytes32) private _reverseRecords; // address -> name hash

    uint256 public registrationFee = 0.01 ether;
    uint256 public registrationDuration = 365 days;
    uint256 public totalRegistrations;

    /// @notice Emitted when a name is registered
    event NameRegistered(bytes32 indexed nameHash, string name, address indexed registeredOwner, uint256 expiresAt);
    /// @notice Emitted when a name is transferred
    event NameTransferred(bytes32 indexed nameHash, address indexed from, address indexed to);
    /// @notice Emitted when a resolver is set
    event ResolverSet(bytes32 indexed nameHash, address indexed resolver);
    /// @notice Emitted when metadata is updated
    event MetadataUpdated(bytes32 indexed nameHash, string metadata);
    /// @notice Emitted when a name is renewed
    event NameRenewed(bytes32 indexed nameHash, uint256 newExpiresAt);

    error NameAlreadyRegistered(string name);
    error NameNotFound(bytes32 nameHash);
    error NameExpired(bytes32 nameHash);
    error NotNameOwner(address caller);
    error InsufficientFee(uint256 sent, uint256 required);
    error EmptyName();
    error InvalidDuration();

    /**
     * @notice Register a new name
     * @param name The name to register
     * @param nameOwner The address that will own the name
     * @param metadata Optional metadata string (URI, description, etc.)
     * @return nameHash The hash of the registered name
     */
    function registerName(
        string calldata name,
        address nameOwner,
        string calldata metadata
    ) external payable whenNotPaused returns (bytes32 nameHash) {
        if (bytes(name).length == 0) revert EmptyName();
        if (msg.value < registrationFee) revert InsufficientFee(msg.value, registrationFee);

        nameHash = keccak256(abi.encodePacked(name));
        NameRecord storage record = _names[nameHash];

        // Allow re-registration if expired
        if (record.active && block.timestamp < record.expiresAt) {
            revert NameAlreadyRegistered(name);
        }

        uint256 expiresAt = block.timestamp + registrationDuration;

        _names[nameHash] = NameRecord({
            name: name,
            recordOwner: nameOwner,
            resolver: address(0),
            metadata: metadata,
            registeredAt: block.timestamp,
            expiresAt: expiresAt,
            active: true
        });

        _ownerNames[nameOwner].push(nameHash);
        totalRegistrations++;

        emit NameRegistered(nameHash, name, nameOwner, expiresAt);
    }

    /**
     * @notice Transfer name ownership
     * @param name The name to transfer
     * @param newOwner The new owner address
     */
    function transferName(string calldata name, address newOwner) external whenNotPaused {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        NameRecord storage record = _names[nameHash];
        if (!record.active) revert NameNotFound(nameHash);
        if (record.recordOwner != msg.sender) revert NotNameOwner(msg.sender);
        if (block.timestamp >= record.expiresAt) revert NameExpired(nameHash);

        address oldOwner = record.recordOwner;
        record.recordOwner = newOwner;
        _ownerNames[newOwner].push(nameHash);

        emit NameTransferred(nameHash, oldOwner, newOwner);
    }

    /**
     * @notice Resolve a name to its owner address
     * @param name The name to resolve
     * @return addr The resolved address
     */
    function resolveName(string calldata name) external view returns (address addr) {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        NameRecord storage record = _names[nameHash];
        if (!record.active) revert NameNotFound(nameHash);
        if (block.timestamp >= record.expiresAt) revert NameExpired(nameHash);

        // Use resolver if set, otherwise return owner
        return record.resolver != address(0) ? record.resolver : record.recordOwner;
    }

    /**
     * @notice Set a custom resolver for a name
     * @param name The name to configure
     * @param resolverAddr The resolver contract address
     */
    function setResolver(string calldata name, address resolverAddr) external whenNotPaused {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        NameRecord storage record = _names[nameHash];
        if (!record.active) revert NameNotFound(nameHash);
        if (record.recordOwner != msg.sender) revert NotNameOwner(msg.sender);

        record.resolver = resolverAddr;
        emit ResolverSet(nameHash, resolverAddr);
    }

    /**
     * @notice Renew a name registration
     * @param name The name to renew
     */
    function renewName(string calldata name) external payable whenNotPaused {
        if (msg.value < registrationFee) revert InsufficientFee(msg.value, registrationFee);

        bytes32 nameHash = keccak256(abi.encodePacked(name));
        NameRecord storage record = _names[nameHash];
        if (!record.active) revert NameNotFound(nameHash);
        if (record.recordOwner != msg.sender) revert NotNameOwner(msg.sender);

        record.expiresAt += registrationDuration;
        emit NameRenewed(nameHash, record.expiresAt);
    }

    /**
     * @notice Update metadata for a name
     * @param name The name to update
     * @param metadata New metadata string
     */
    function updateMetadata(string calldata name, string calldata metadata) external whenNotPaused {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        NameRecord storage record = _names[nameHash];
        if (!record.active) revert NameNotFound(nameHash);
        if (record.recordOwner != msg.sender) revert NotNameOwner(msg.sender);

        record.metadata = metadata;
        emit MetadataUpdated(nameHash, metadata);
    }

    /**
     * @notice Set reverse record (address -> name)
     * @param name The name to point the address to
     */
    function setReverseRecord(string calldata name) external whenNotPaused {
        bytes32 nameHash = keccak256(abi.encodePacked(name));
        NameRecord storage record = _names[nameHash];
        if (!record.active) revert NameNotFound(nameHash);
        if (record.recordOwner != msg.sender) revert NotNameOwner(msg.sender);
        _reverseRecords[msg.sender] = nameHash;
    }

    /**
     * @notice Get name record by hash
     * @param nameHash The name hash
     * @return record The name record
     */
    function getRecord(bytes32 nameHash) external view returns (NameRecord memory record) {
        if (!_names[nameHash].active) revert NameNotFound(nameHash);
        return _names[nameHash];
    }

    /**
     * @notice Get names owned by an address
     * @param addr The owner address
     * @return hashes Array of name hashes
     */
    function getOwnedNames(address addr) external view returns (bytes32[] memory hashes) {
        return _ownerNames[addr];
    }

    /// @notice Set registration fee
    function setRegistrationFee(uint256 fee) external onlyOwner { registrationFee = fee; }

    /// @notice Set registration duration
    function setRegistrationDuration(uint256 duration) external onlyOwner {
        if (duration < 30 days) revert InvalidDuration();
        registrationDuration = duration;
    }

    /// @notice Withdraw collected fees
    function withdrawFees() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    receive() external payable {}
}
