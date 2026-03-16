// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CredentialStack
 * @author ProbeChain
 * @notice Verifiable credentials on-chain. Issuers create credentials for subjects;
 *         credentials can be verified, revoked, and issuers can delegate authority.
 *         Supports credential chains where one credential references another.
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

// ── CredentialStack ────────────────────────────────────────────────────────────
contract CredentialStack is Ownable, ReentrancyGuard, Pausable {

    enum CredStatus { Valid, Revoked, Expired }

    struct Credential {
        uint256 id;
        address issuer;
        address subject;
        string credType;
        string dataHash;
        uint256 issuedAt;
        uint256 expiry;
        uint256 parentCredId; // 0 = root credential
        CredStatus status;
    }

    uint256 public nextCredId = 1; // 0 reserved for "no parent"
    uint256 public issuanceFee;

    mapping(uint256 => Credential) public credentials;
    mapping(address => bool) public authorizedIssuers;
    mapping(address => mapping(address => bool)) public delegatedIssuers; // issuer -> delegate -> bool
    mapping(address => uint256[]) private _issuedCreds;
    mapping(address => uint256[]) private _receivedCreds;

    // ── Events ─────────────────────────────────────────────────────────────────
    event CredentialIssued(uint256 indexed credId, address indexed issuer, address indexed subject, string credType);
    event CredentialRevoked(uint256 indexed credId, address indexed revokedBy);
    event CredentialVerified(uint256 indexed credId, address indexed verifier, bool valid);
    event IssuerAuthorized(address indexed issuer);
    event IssuerDeauthorized(address indexed issuer);
    event IssuerDelegated(address indexed issuer, address indexed delegate);
    event DelegationRevoked(address indexed issuer, address indexed delegate);
    event IssuanceFeeUpdated(uint256 newFee);

    // ── Errors ─────────────────────────────────────────────────────────────────
    error NotAuthorizedIssuer();
    error EmptyCredential();
    error InvalidSubject();
    error InvalidExpiry();
    error CredentialNotFound();
    error NotIssuer();
    error AlreadyRevoked();
    error ParentCredInvalid();
    error InsufficientFee();
    error TransferFailed();

    // ── Modifiers ──────────────────────────────────────────────────────────────
    modifier onlyIssuer() {
        if (!authorizedIssuers[msg.sender] && msg.sender != owner()) revert NotAuthorizedIssuer();
        _;
    }

    // ── Issuer Management ──────────────────────────────────────────────────────
    /// @notice Authorize an address to issue credentials.
    function authorizeIssuer(address issuer) external onlyOwner {
        authorizedIssuers[issuer] = true;
        emit IssuerAuthorized(issuer);
    }

    /// @notice Deauthorize an issuer.
    function deauthorizeIssuer(address issuer) external onlyOwner {
        authorizedIssuers[issuer] = false;
        emit IssuerDeauthorized(issuer);
    }

    /// @notice An authorized issuer delegates issuance power to another address.
    function delegateIssuer(address delegate) external onlyIssuer whenNotPaused {
        delegatedIssuers[msg.sender][delegate] = true;
        authorizedIssuers[delegate] = true;
        emit IssuerDelegated(msg.sender, delegate);
    }

    /// @notice Revoke delegation.
    function revokeDelegation(address delegate) external onlyIssuer whenNotPaused {
        delegatedIssuers[msg.sender][delegate] = false;
        emit DelegationRevoked(msg.sender, delegate);
    }

    // ── Issue Credential ───────────────────────────────────────────────────────
    /// @notice Issue a new credential to a subject.
    /// @param subject       Credential holder.
    /// @param credType      Type string (e.g. "diploma", "license", "badge").
    /// @param dataHash      IPFS / Arweave hash of credential payload.
    /// @param expiry        Unix expiry timestamp (0 = never expires).
    /// @param parentCredId  Parent credential ID for chaining (0 = root).
    function issueCredential(
        address subject,
        string calldata credType,
        string calldata dataHash,
        uint256 expiry,
        uint256 parentCredId
    ) external payable onlyIssuer whenNotPaused returns (uint256 credId) {
        if (subject == address(0)) revert InvalidSubject();
        if (bytes(credType).length == 0 || bytes(dataHash).length == 0) revert EmptyCredential();
        if (expiry != 0 && expiry <= block.timestamp) revert InvalidExpiry();
        if (msg.value < issuanceFee) revert InsufficientFee();

        // Validate parent if specified
        if (parentCredId != 0) {
            Credential storage parent = credentials[parentCredId];
            if (parent.issuedAt == 0 || parent.status != CredStatus.Valid) revert ParentCredInvalid();
        }

        credId = nextCredId++;
        credentials[credId] = Credential({
            id: credId,
            issuer: msg.sender,
            subject: subject,
            credType: credType,
            dataHash: dataHash,
            issuedAt: block.timestamp,
            expiry: expiry,
            parentCredId: parentCredId,
            status: CredStatus.Valid
        });

        _issuedCreds[msg.sender].push(credId);
        _receivedCreds[subject].push(credId);

        emit CredentialIssued(credId, msg.sender, subject, credType);
    }

    // ── Verify ─────────────────────────────────────────────────────────────────
    /// @notice Verify whether a credential is currently valid.
    /// @return valid True if not revoked and not expired.
    function verifyCredential(uint256 credId) external returns (bool valid) {
        Credential storage c = credentials[credId];
        if (c.issuedAt == 0) revert CredentialNotFound();

        // Auto-expire
        if (c.expiry != 0 && block.timestamp > c.expiry && c.status == CredStatus.Valid) {
            c.status = CredStatus.Expired;
        }

        valid = c.status == CredStatus.Valid;
        emit CredentialVerified(credId, msg.sender, valid);
    }

    // ── Revoke ─────────────────────────────────────────────────────────────────
    /// @notice Issuer or owner revokes a credential.
    function revokeCredential(uint256 credId) external whenNotPaused {
        Credential storage c = credentials[credId];
        if (c.issuedAt == 0) revert CredentialNotFound();
        if (msg.sender != c.issuer && msg.sender != owner()) revert NotIssuer();
        if (c.status == CredStatus.Revoked) revert AlreadyRevoked();
        c.status = CredStatus.Revoked;
        emit CredentialRevoked(credId, msg.sender);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────
    /// @notice Set issuance fee.
    function setIssuanceFee(uint256 fee) external onlyOwner {
        issuanceFee = fee;
        emit IssuanceFeeUpdated(fee);
    }

    /// @notice Withdraw collected fees.
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        if (bal == 0) revert TransferFailed();
        (bool ok, ) = payable(owner()).call{value: bal}("");
        if (!ok) revert TransferFailed();
    }

    // ── Views ──────────────────────────────────────────────────────────────────
    /// @notice Get credentials issued by an address.
    function getIssuedCredentials(address issuer) external view returns (uint256[] memory) {
        return _issuedCreds[issuer];
    }

    /// @notice Get credentials received by a subject.
    function getReceivedCredentials(address subject) external view returns (uint256[] memory) {
        return _receivedCreds[subject];
    }

    /// @notice Walk the credential chain upward to the root.
    function getCredentialChain(uint256 credId) external view returns (uint256[] memory chain) {
        uint256 count;
        uint256 current = credId;
        // First pass: count depth (max 20 to prevent gas issues)
        while (current != 0 && count < 20) {
            count++;
            current = credentials[current].parentCredId;
        }
        chain = new uint256[](count);
        current = credId;
        for (uint256 i = 0; i < count; i++) {
            chain[i] = current;
            current = credentials[current].parentCredId;
        }
    }
}
