// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title UniversalID
 * @author ProbeChain
 * @notice Universal identity system supporting Human, Agent, and Organization types
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

/// @notice Inline Ownable implementation
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/// @notice Inline Pausable implementation
abstract contract Pausable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function _pause() internal whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract UniversalID is Ownable, Pausable {
    /// @notice Identity types supported by the system
    enum IdentityType { Human, Agent, Organization }

    /// @notice Attribute verification status
    enum AttributeStatus { Pending, Verified, Revoked }

    /// @notice Core identity structure
    struct Identity {
        uint256 id;
        address owner;
        bytes publicKey;
        IdentityType identityType;
        uint256 createdAt;
        bool active;
    }

    /// @notice Attribute attached to an identity
    struct Attribute {
        string key;
        string value;
        bytes32 proofHash;
        AttributeStatus status;
        address verifiedBy;
        uint256 timestamp;
    }

    /// @dev Counter for identity IDs
    uint256 private _nextId;

    /// @dev Identity ID => Identity
    mapping(uint256 => Identity) private _identities;

    /// @dev Address => Identity ID
    mapping(address => uint256) private _ownerToId;

    /// @dev Identity ID => attribute key => Attribute
    mapping(uint256 => mapping(string => Attribute)) private _attributes;

    /// @dev Identity ID => list of attribute keys
    mapping(uint256 => string[]) private _attributeKeys;

    /// @dev Authorized verifiers
    mapping(address => bool) public verifiers;

    // ───────── Events ─────────

    /// @notice Emitted when a new identity is created
    event IdentityCreated(uint256 indexed id, address indexed owner, IdentityType identityType);

    /// @notice Emitted when an attribute is added
    event AttributeAdded(uint256 indexed id, string key, bytes32 proofHash);

    /// @notice Emitted when an attribute is verified
    event AttributeVerified(uint256 indexed id, string key, address indexed verifier);

    /// @notice Emitted when an attribute is revoked
    event AttributeRevoked(uint256 indexed id, string key, address indexed revokedBy);

    /// @notice Emitted when a verifier is added or removed
    event VerifierUpdated(address indexed verifier, bool status);

    /// @notice Emitted when an identity is deactivated
    event IdentityDeactivated(uint256 indexed id);

    // ───────── Modifiers ─────────

    modifier onlyVerifier() {
        require(verifiers[msg.sender], "UniversalID: caller is not a verifier");
        _;
    }

    modifier identityExists(uint256 idId) {
        require(_identities[idId].active, "UniversalID: identity does not exist or inactive");
        _;
    }

    modifier onlyIdentityOwner(uint256 idId) {
        require(_identities[idId].owner == msg.sender, "UniversalID: not identity owner");
        _;
    }

    // ───────── Constructor ─────────

    constructor() {
        _nextId = 1;
    }

    // ───────── Admin Functions ─────────

    /// @notice Add or remove a verifier
    /// @param verifier The address to update
    /// @param status True to add, false to remove
    function setVerifier(address verifier, bool status) external onlyOwner {
        require(verifier != address(0), "UniversalID: zero address");
        verifiers[verifier] = status;
        emit VerifierUpdated(verifier, status);
    }

    /// @notice Pause the contract
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause the contract
    function unpause() external onlyOwner {
        _unpause();
    }

    // ───────── Identity Functions ─────────

    /// @notice Create a new universal identity
    /// @param publicKey The public key associated with the identity
    /// @param identityType The type: Human, Agent, or Organization
    /// @return id The new identity ID
    function createIdentity(
        bytes calldata publicKey,
        IdentityType identityType
    ) external whenNotPaused returns (uint256 id) {
        require(publicKey.length > 0, "UniversalID: empty public key");
        require(_ownerToId[msg.sender] == 0, "UniversalID: identity already exists");

        id = _nextId++;
        _identities[id] = Identity({
            id: id,
            owner: msg.sender,
            publicKey: publicKey,
            identityType: identityType,
            createdAt: block.timestamp,
            active: true
        });
        _ownerToId[msg.sender] = id;

        emit IdentityCreated(id, msg.sender, identityType);
    }

    /// @notice Add an attribute to an identity
    /// @param idId The identity ID
    /// @param key The attribute key (e.g., "email", "name")
    /// @param value The attribute value
    /// @param proofHash Hash of the proof document
    function addAttribute(
        uint256 idId,
        string calldata key,
        string calldata value,
        bytes32 proofHash
    ) external whenNotPaused identityExists(idId) onlyIdentityOwner(idId) {
        require(bytes(key).length > 0, "UniversalID: empty key");
        require(proofHash != bytes32(0), "UniversalID: empty proof hash");

        if (bytes(_attributes[idId][key].key).length == 0) {
            _attributeKeys[idId].push(key);
        }

        _attributes[idId][key] = Attribute({
            key: key,
            value: value,
            proofHash: proofHash,
            status: AttributeStatus.Pending,
            verifiedBy: address(0),
            timestamp: block.timestamp
        });

        emit AttributeAdded(idId, key, proofHash);
    }

    /// @notice Verify an attribute on an identity (verifier only)
    /// @param idId The identity ID
    /// @param key The attribute key to verify
    function verifyAttribute(
        uint256 idId,
        string calldata key
    ) external whenNotPaused identityExists(idId) onlyVerifier {
        Attribute storage attr = _attributes[idId][key];
        require(bytes(attr.key).length > 0, "UniversalID: attribute not found");
        require(attr.status == AttributeStatus.Pending, "UniversalID: not pending");

        attr.status = AttributeStatus.Verified;
        attr.verifiedBy = msg.sender;

        emit AttributeVerified(idId, key, msg.sender);
    }

    /// @notice Revoke an attribute (owner or verifier)
    /// @param idId The identity ID
    /// @param key The attribute key to revoke
    function revokeAttribute(
        uint256 idId,
        string calldata key
    ) external whenNotPaused identityExists(idId) {
        require(
            _identities[idId].owner == msg.sender || verifiers[msg.sender],
            "UniversalID: not authorized"
        );
        Attribute storage attr = _attributes[idId][key];
        require(bytes(attr.key).length > 0, "UniversalID: attribute not found");
        require(attr.status != AttributeStatus.Revoked, "UniversalID: already revoked");

        attr.status = AttributeStatus.Revoked;

        emit AttributeRevoked(idId, key, msg.sender);
    }

    /// @notice Deactivate an identity
    /// @param idId The identity ID
    function deactivateIdentity(uint256 idId) external identityExists(idId) onlyIdentityOwner(idId) {
        _identities[idId].active = false;
        emit IdentityDeactivated(idId);
    }

    // ───────── View Functions ─────────

    /// @notice Get identity details
    /// @param idId The identity ID
    /// @return The identity struct
    function getIdentity(uint256 idId) external view returns (Identity memory) {
        require(_identities[idId].createdAt > 0, "UniversalID: not found");
        return _identities[idId];
    }

    /// @notice Get identity ID by owner address
    /// @param addr The owner address
    /// @return The identity ID (0 if none)
    function getIdentityByOwner(address addr) external view returns (uint256) {
        return _ownerToId[addr];
    }

    /// @notice Get an attribute
    /// @param idId The identity ID
    /// @param key The attribute key
    /// @return The attribute struct
    function getAttribute(uint256 idId, string calldata key) external view returns (Attribute memory) {
        return _attributes[idId][key];
    }

    /// @notice Get all attribute keys for an identity
    /// @param idId The identity ID
    /// @return Array of attribute keys
    function getAttributeKeys(uint256 idId) external view returns (string[] memory) {
        return _attributeKeys[idId];
    }

    /// @notice Check if an attribute is verified
    /// @param idId The identity ID
    /// @param key The attribute key
    /// @return True if the attribute is verified
    function isAttributeVerified(uint256 idId, string calldata key) external view returns (bool) {
        return _attributes[idId][key].status == AttributeStatus.Verified;
    }

    /// @notice Get total number of identities created
    /// @return count The total count
    function totalIdentities() external view returns (uint256 count) {
        return _nextId - 1;
    }
}
