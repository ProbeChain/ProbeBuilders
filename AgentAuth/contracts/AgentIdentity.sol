// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title AgentIdentity — Soulbound agent identity and DID for ProbeChain
/// @author ProbeBuilders
/// @notice Create non-transferable identities, manage credentials, and track reputation
/// @dev Soulbound tokens (non-transferable). Rydberg Testnet (Chain ID 8004).
contract AgentIdentity {
    // ─── Enums & Structs ─────────────────────────────────────────────────
    enum CredentialStatus { Active, Revoked }

    struct Identity {
        uint256 id;
        address owner;
        bytes32 publicKeyHash;
        string metadata;
        uint256 reputationScore;
        uint256 credentialCount;
        bool verified;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct Credential {
        uint256 id;
        uint256 identityId;
        string credentialType;
        bytes32 dataHash;
        address issuer;
        CredentialStatus status;
        uint256 issuedAt;
        uint256 expiresAt;
    }

    // ─── State ───────────────────────────────────────────────────────────
    address public owner;
    bool public paused;

    uint256 private _nextIdentityId = 1;
    uint256 private _nextCredentialId = 1;

    mapping(uint256 => Identity) private _identities;
    mapping(address => uint256) public addressToIdentity; // 1 identity per address (soulbound)
    mapping(uint256 => Credential) private _credentials;
    mapping(uint256 => uint256[]) private _identityCredentials; // identityId => credentialIds
    mapping(address => bool) public trustedIssuers;

    uint256 public totalIdentities;

    // ─── Events ──────────────────────────────────────────────────────────
    event IdentityCreated(uint256 indexed identityId, address indexed identityOwner, bytes32 publicKeyHash);
    event IdentityVerified(uint256 indexed identityId, address indexed verifier);
    event IdentityMetadataUpdated(uint256 indexed identityId, string metadata);
    event CredentialAdded(uint256 indexed credentialId, uint256 indexed identityId, string credentialType, address indexed issuer);
    event CredentialRevoked(uint256 indexed credentialId, uint256 indexed identityId, address indexed revoker);
    event ReputationUpdated(uint256 indexed identityId, uint256 oldScore, uint256 newScore, string reason);
    event TrustedIssuerUpdated(address indexed issuer, bool trusted);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "AgentIdentity: not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "AgentIdentity: paused");
        _;
    }

    modifier identityExists(uint256 identityId) {
        require(_identities[identityId].createdAt != 0, "AgentIdentity: identity not found");
        _;
    }

    modifier onlyIdentityOwner(uint256 identityId) {
        require(_identities[identityId].owner == msg.sender, "AgentIdentity: not identity owner");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Identity Management ─────────────────────────────────────────────

    /// @notice Create a soulbound identity (one per address)
    /// @param publicKeyHash Hash of the agent's public key
    /// @param metadata JSON metadata URI or string
    /// @return identityId The new identity ID
    function createIdentity(
        bytes32 publicKeyHash,
        string calldata metadata
    ) external whenNotPaused returns (uint256 identityId) {
        require(addressToIdentity[msg.sender] == 0, "AgentIdentity: already has identity");
        require(publicKeyHash != bytes32(0), "AgentIdentity: empty public key hash");
        require(bytes(metadata).length > 0 && bytes(metadata).length <= 2048, "AgentIdentity: invalid metadata");

        identityId = _nextIdentityId++;

        _identities[identityId] = Identity({
            id: identityId,
            owner: msg.sender,
            publicKeyHash: publicKeyHash,
            metadata: metadata,
            reputationScore: 50, // neutral start
            credentialCount: 0,
            verified: false,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        addressToIdentity[msg.sender] = identityId;
        totalIdentities++;

        emit IdentityCreated(identityId, msg.sender, publicKeyHash);
    }

    /// @notice Verify an identity (admin or trusted issuer only)
    /// @param identityId The identity to verify
    function verifyIdentity(uint256 identityId) external identityExists(identityId) {
        require(msg.sender == owner || trustedIssuers[msg.sender], "AgentIdentity: not authorized to verify");
        require(!_identities[identityId].verified, "AgentIdentity: already verified");

        _identities[identityId].verified = true;
        _identities[identityId].updatedAt = block.timestamp;

        // Boost reputation for verification
        _adjustReputation(identityId, 10, true, "identity_verified");

        emit IdentityVerified(identityId, msg.sender);
    }

    /// @notice Update identity metadata
    /// @param identityId The identity to update
    /// @param metadata New metadata
    function updateMetadata(uint256 identityId, string calldata metadata)
        external
        identityExists(identityId)
        onlyIdentityOwner(identityId)
    {
        require(bytes(metadata).length > 0 && bytes(metadata).length <= 2048, "AgentIdentity: invalid metadata");
        _identities[identityId].metadata = metadata;
        _identities[identityId].updatedAt = block.timestamp;
        emit IdentityMetadataUpdated(identityId, metadata);
    }

    // ─── Credential Management ───────────────────────────────────────────

    /// @notice Add a credential to an identity
    /// @param identityId The identity receiving the credential
    /// @param credentialType Type label (e.g., "KYC", "SKILL_CERT", "AUDIT")
    /// @param dataHash Hash of the credential data
    /// @param expiresAt Expiration timestamp (0 = never)
    /// @return credentialId The new credential ID
    function addCredential(
        uint256 identityId,
        string calldata credentialType,
        bytes32 dataHash,
        uint256 expiresAt
    ) external whenNotPaused identityExists(identityId) returns (uint256 credentialId) {
        require(
            msg.sender == owner || trustedIssuers[msg.sender] || _identities[identityId].owner == msg.sender,
            "AgentIdentity: not authorized"
        );
        require(bytes(credentialType).length > 0, "AgentIdentity: empty type");
        require(dataHash != bytes32(0), "AgentIdentity: empty data hash");
        if (expiresAt != 0) {
            require(expiresAt > block.timestamp, "AgentIdentity: already expired");
        }

        credentialId = _nextCredentialId++;

        _credentials[credentialId] = Credential({
            id: credentialId,
            identityId: identityId,
            credentialType: credentialType,
            dataHash: dataHash,
            issuer: msg.sender,
            status: CredentialStatus.Active,
            issuedAt: block.timestamp,
            expiresAt: expiresAt
        });

        _identityCredentials[identityId].push(credentialId);
        _identities[identityId].credentialCount++;
        _identities[identityId].updatedAt = block.timestamp;

        // Reputation boost for each credential
        _adjustReputation(identityId, 2, true, "credential_added");

        emit CredentialAdded(credentialId, identityId, credentialType, msg.sender);
    }

    /// @notice Revoke a credential
    /// @param credentialId The credential to revoke
    function revokeCredential(uint256 credentialId) external {
        Credential storage cred = _credentials[credentialId];
        require(cred.issuedAt != 0, "AgentIdentity: credential not found");
        require(cred.status == CredentialStatus.Active, "AgentIdentity: already revoked");
        require(
            msg.sender == cred.issuer || msg.sender == owner || msg.sender == _identities[cred.identityId].owner,
            "AgentIdentity: not authorized to revoke"
        );

        cred.status = CredentialStatus.Revoked;

        // Reputation penalty for revocation
        _adjustReputation(cred.identityId, 5, false, "credential_revoked");

        emit CredentialRevoked(credentialId, cred.identityId, msg.sender);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Get identity details
    function getIdentity(uint256 identityId) external view identityExists(identityId) returns (Identity memory) {
        return _identities[identityId];
    }

    /// @notice Get identity by address
    function getIdentityByAddress(address addr) external view returns (Identity memory) {
        uint256 id = addressToIdentity[addr];
        require(id != 0, "AgentIdentity: no identity for address");
        return _identities[id];
    }

    /// @notice Get credential details
    function getCredential(uint256 credentialId) external view returns (Credential memory) {
        require(_credentials[credentialId].issuedAt != 0, "AgentIdentity: credential not found");
        return _credentials[credentialId];
    }

    /// @notice Check if a credential is valid (active and not expired)
    function isCredentialValid(uint256 credentialId) external view returns (bool) {
        Credential storage cred = _credentials[credentialId];
        if (cred.issuedAt == 0) return false;
        if (cred.status != CredentialStatus.Active) return false;
        if (cred.expiresAt != 0 && block.timestamp > cred.expiresAt) return false;
        return true;
    }

    /// @notice Get all credential IDs for an identity
    function getIdentityCredentials(uint256 identityId) external view returns (uint256[] memory) {
        return _identityCredentials[identityId];
    }

    /// @notice Get reputation score for an identity
    function getReputation(uint256 identityId) external view identityExists(identityId) returns (uint256) {
        return _identities[identityId].reputationScore;
    }

    // ─── Internal ────────────────────────────────────────────────────────

    /// @dev Adjust reputation score, clamped to 0-100
    function _adjustReputation(uint256 identityId, uint256 amount, bool increase, string memory reason) internal {
        uint256 oldScore = _identities[identityId].reputationScore;
        uint256 newScore;

        if (increase) {
            newScore = oldScore + amount;
            if (newScore > 100) newScore = 100;
        } else {
            if (amount >= oldScore) {
                newScore = 0;
            } else {
                newScore = oldScore - amount;
            }
        }

        _identities[identityId].reputationScore = newScore;
        emit ReputationUpdated(identityId, oldScore, newScore, reason);
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    /// @notice Add or remove a trusted credential issuer
    function setTrustedIssuer(address issuer, bool trusted) external onlyOwner {
        trustedIssuers[issuer] = trusted;
        emit TrustedIssuerUpdated(issuer, trusted);
    }

    /// @notice Manually adjust reputation (admin)
    function adminSetReputation(uint256 identityId, uint256 score)
        external
        onlyOwner
        identityExists(identityId)
    {
        require(score <= 100, "AgentIdentity: score 0-100");
        uint256 old = _identities[identityId].reputationScore;
        _identities[identityId].reputationScore = score;
        emit ReputationUpdated(identityId, old, score, "admin_override");
    }

    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "AgentIdentity: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
