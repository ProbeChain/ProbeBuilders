// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title KYCRegistry
 * @author ProbeBuilders
 * @notice Privacy-preserving KYC verification registry for ProbeChain Rydberg Testnet.
 *         Verifiers attest to user identity levels without storing personal data on-chain.
 * @dev Inline Ownable, ReentrancyGuard, Pausable. EVM London compatible.
 */

/* ───────── Abstract helpers (inlined) ───────── */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed prev, address indexed next_);
    error OwnableUnauthorized();
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorized(); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardLocked();
    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardLocked();
        _status = 2;
        _;
        _status = 1;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();
    modifier whenNotPaused() { if (_paused) revert ContractPaused(); _; }
    modifier whenPaused() { if (!_paused) revert ContractNotPaused(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

/* ───────── Main Contract ───────── */

contract KYCRegistry is Ownable, ReentrancyGuard, Pausable {

    /* ── Enums ── */

    /// @notice KYC verification levels
    enum Level {
        None,      // 0 - not verified
        Basic,     // 1 - email + phone
        Standard,  // 2 - government ID
        Enhanced   // 3 - full due diligence
    }

    /* ── Structs ── */

    /// @notice A KYC verification record
    struct Verification {
        Level   level;
        bytes32 documentHash;  // hash of off-chain document (privacy)
        address verifier;
        uint256 verifiedAt;
        uint256 expiresAt;
        bool    revoked;
    }

    /* ── State ── */

    /// @notice user => level => Verification
    mapping(address => mapping(Level => Verification)) private _verifications;
    /// @notice Authorized verifier addresses
    mapping(address => bool) public verifiers;
    /// @notice Count of active verifiers
    uint256 public verifierCount;
    /// @notice Total verifications issued
    uint256 public totalVerifications;
    /// @notice Default verification validity period (365 days)
    uint256 public defaultValidity = 365 days;

    /* ── Events ── */

    /// @notice Emitted when a verification is submitted
    event VerificationSubmitted(address indexed user, Level level, bytes32 documentHash, address indexed verifier, uint256 expiresAt);
    /// @notice Emitted when a verification is revoked
    event VerificationRevoked(address indexed user, Level level, address indexed revokedBy);
    /// @notice Emitted when a verifier is added
    event VerifierAdded(address indexed verifier);
    /// @notice Emitted when a verifier is removed
    event VerifierRemoved(address indexed verifier);
    /// @notice Emitted when default validity is changed
    event ValidityUpdated(uint256 oldValidity, uint256 newValidity);

    /* ── Errors ── */

    error NotVerifier();
    error AlreadyVerifier();
    error NotAVerifier();
    error AlreadyVerified();
    error NotVerified();
    error InvalidLevel();
    error CannotSelfVerify();

    /* ── Modifiers ── */

    modifier onlyVerifier() {
        if (!verifiers[msg.sender]) revert NotVerifier();
        _;
    }

    /* ── Constructor ── */

    constructor() Ownable() {
        verifiers[msg.sender] = true;
        verifierCount = 1;
        emit VerifierAdded(msg.sender);
    }

    /* ── Verifier management ── */

    /**
     * @notice Add a new authorized verifier
     * @param verifier Address to authorize
     */
    function addVerifier(address verifier) external onlyOwner {
        require(verifier != address(0), "zero addr");
        if (verifiers[verifier]) revert AlreadyVerifier();
        verifiers[verifier] = true;
        verifierCount++;
        emit VerifierAdded(verifier);
    }

    /**
     * @notice Remove a verifier
     * @param verifier Address to remove
     */
    function removeVerifier(address verifier) external onlyOwner {
        if (!verifiers[verifier]) revert NotAVerifier();
        verifiers[verifier] = false;
        verifierCount--;
        emit VerifierRemoved(verifier);
    }

    /**
     * @notice Update default verification validity period
     * @param newValidity New validity in seconds
     */
    function setDefaultValidity(uint256 newValidity) external onlyOwner {
        require(newValidity >= 30 days, "too short");
        emit ValidityUpdated(defaultValidity, newValidity);
        defaultValidity = newValidity;
    }

    /* ── Core functions ── */

    /**
     * @notice Submit a KYC verification for a user
     * @param user The user being verified
     * @param level The verification level (Basic, Standard, Enhanced)
     * @param documentHash Hash of the off-chain KYC documents
     */
    function submitVerification(
        address user,
        Level level,
        bytes32 documentHash
    ) external onlyVerifier whenNotPaused {
        require(user != address(0), "zero user");
        if (level == Level.None) revert InvalidLevel();
        if (user == msg.sender) revert CannotSelfVerify();

        Verification storage v = _verifications[user][level];
        // Allow re-verification if previous is revoked or expired
        if (v.verifiedAt != 0 && !v.revoked && block.timestamp < v.expiresAt) {
            revert AlreadyVerified();
        }

        uint256 expiry = block.timestamp + defaultValidity;

        _verifications[user][level] = Verification({
            level: level,
            documentHash: documentHash,
            verifier: msg.sender,
            verifiedAt: block.timestamp,
            expiresAt: expiry,
            revoked: false
        });

        totalVerifications++;

        emit VerificationSubmitted(user, level, documentHash, msg.sender, expiry);
    }

    /**
     * @notice Submit verification with custom expiry
     * @param user The user being verified
     * @param level The verification level
     * @param documentHash Hash of documents
     * @param expiresAt Custom expiration timestamp
     */
    function submitVerificationWithExpiry(
        address user,
        Level level,
        bytes32 documentHash,
        uint256 expiresAt
    ) external onlyVerifier whenNotPaused {
        require(user != address(0), "zero user");
        if (level == Level.None) revert InvalidLevel();
        if (user == msg.sender) revert CannotSelfVerify();
        require(expiresAt > block.timestamp, "already expired");

        Verification storage v = _verifications[user][level];
        if (v.verifiedAt != 0 && !v.revoked && block.timestamp < v.expiresAt) {
            revert AlreadyVerified();
        }

        _verifications[user][level] = Verification({
            level: level,
            documentHash: documentHash,
            verifier: msg.sender,
            verifiedAt: block.timestamp,
            expiresAt: expiresAt,
            revoked: false
        });

        totalVerifications++;

        emit VerificationSubmitted(user, level, documentHash, msg.sender, expiresAt);
    }

    /**
     * @notice Revoke a user's verification at a specific level
     * @param user The user whose verification to revoke
     * @param level The level to revoke
     */
    function revokeVerification(address user, Level level) external onlyVerifier whenNotPaused {
        Verification storage v = _verifications[user][level];
        if (v.verifiedAt == 0 || v.revoked) revert NotVerified();

        // Only the original verifier or owner can revoke
        require(v.verifier == msg.sender || msg.sender == owner(), "not authorized");

        v.revoked = true;

        emit VerificationRevoked(user, level, msg.sender);
    }

    /* ── View functions ── */

    /**
     * @notice Check if a user is verified at a given level
     * @param user The user to check
     * @param level The required level
     * @return verified True if the user holds a valid, non-expired, non-revoked verification
     */
    function isVerified(address user, Level level) external view returns (bool verified) {
        Verification storage v = _verifications[user][level];
        verified = v.verifiedAt != 0 && !v.revoked && block.timestamp < v.expiresAt;
    }

    /**
     * @notice Get full verification details for a user at a level
     * @param user The user
     * @param level The level
     * @return The verification record
     */
    function getVerification(address user, Level level) external view returns (Verification memory) {
        return _verifications[user][level];
    }

    /**
     * @notice Get the highest valid verification level for a user
     * @param user The user to check
     * @return highest The highest valid Level
     */
    function getHighestLevel(address user) external view returns (Level highest) {
        highest = Level.None;
        for (uint8 i = 3; i >= 1; i--) {
            Level lvl = Level(i);
            Verification storage v = _verifications[user][lvl];
            if (v.verifiedAt != 0 && !v.revoked && block.timestamp < v.expiresAt) {
                highest = lvl;
                break;
            }
        }
    }

    /**
     * @notice Check if a user meets at least a minimum verification level
     * @param user The user
     * @param minLevel The minimum required level
     * @return meets True if user holds minLevel or higher
     */
    function meetsMinimumLevel(address user, Level minLevel) external view returns (bool meets) {
        for (uint8 i = uint8(minLevel); i <= 3; i++) {
            Level lvl = Level(i);
            Verification storage v = _verifications[user][lvl];
            if (v.verifiedAt != 0 && !v.revoked && block.timestamp < v.expiresAt) {
                return true;
            }
        }
        return false;
    }
}
