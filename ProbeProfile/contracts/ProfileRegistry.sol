// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ProfileRegistry
 * @author ProbeChain
 * @notice On-chain identity profiles with unique usernames, avatar hashes, bios, links,
 *         and a verifier role for identity attestation.
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

// ── ProfileRegistry ────────────────────────────────────────────────────────────
contract ProfileRegistry is Ownable, ReentrancyGuard, Pausable {

    struct Profile {
        address wallet;
        string username;
        string avatar;
        string bio;
        string[] links;
        bool verified;
        address verifiedBy;
        uint256 createdAt;
        uint256 updatedAt;
    }

    uint256 public profileCount;
    uint256 public registrationFee;

    mapping(address => Profile) private _profiles;
    mapping(string => address) private _usernameToAddress;
    mapping(address => bool) public isVerifier;

    // ── Events ─────────────────────────────────────────────────────────────────
    event ProfileCreated(address indexed user, string username);
    event ProfileUpdated(address indexed user, string username);
    event ProfileVerified(address indexed user, address indexed verifier);
    event ProfileUnverified(address indexed user, address indexed revoker);
    event VerifierAdded(address indexed verifier);
    event VerifierRemoved(address indexed verifier);
    event RegistrationFeeUpdated(uint256 newFee);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // ── Errors ─────────────────────────────────────────────────────────────────
    error EmptyUsername();
    error UsernameTooLong();
    error UsernameTaken();
    error ProfileAlreadyExists();
    error ProfileNotFound();
    error NotVerifier();
    error AlreadyVerified();
    error NotVerified();
    error InsufficientFee();
    error TransferFailed();
    error InvalidUsername();

    // ── Modifiers ──────────────────────────────────────────────────────────────
    modifier onlyVerifier() {
        if (!isVerifier[msg.sender] && msg.sender != owner()) revert NotVerifier();
        _;
    }

    // ── Username validation ────────────────────────────────────────────────────
    function _validateUsername(string calldata username) internal pure {
        bytes memory b = bytes(username);
        if (b.length == 0) revert EmptyUsername();
        if (b.length > 32) revert UsernameTooLong();
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            bool valid = (c >= 0x30 && c <= 0x39) || // 0-9
                         (c >= 0x41 && c <= 0x5A) || // A-Z
                         (c >= 0x61 && c <= 0x7A) || // a-z
                         c == 0x5F;                   // _
            if (!valid) revert InvalidUsername();
        }
    }

    // ── Create Profile ─────────────────────────────────────────────────────────
    /// @notice Create an on-chain profile with a unique username.
    /// @param username  Alphanumeric + underscore, max 32 chars.
    /// @param avatar    IPFS hash of avatar image.
    /// @param bio       Short bio text.
    /// @param links     Array of social / web links.
    function createProfile(
        string calldata username,
        string calldata avatar,
        string calldata bio,
        string[] calldata links
    ) external payable whenNotPaused {
        if (_profiles[msg.sender].createdAt != 0) revert ProfileAlreadyExists();
        if (msg.value < registrationFee) revert InsufficientFee();
        _validateUsername(username);
        if (_usernameToAddress[username] != address(0)) revert UsernameTaken();

        string[] memory storedLinks = new string[](links.length);
        for (uint256 i = 0; i < links.length; i++) {
            storedLinks[i] = links[i];
        }

        _profiles[msg.sender] = Profile({
            wallet: msg.sender,
            username: username,
            avatar: avatar,
            bio: bio,
            links: storedLinks,
            verified: false,
            verifiedBy: address(0),
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });
        _usernameToAddress[username] = msg.sender;
        profileCount++;

        emit ProfileCreated(msg.sender, username);
    }

    // ── Update Profile ─────────────────────────────────────────────────────────
    /// @notice Update avatar, bio, and links (username is immutable).
    function updateProfile(
        string calldata avatar,
        string calldata bio,
        string[] calldata links
    ) external whenNotPaused {
        Profile storage p = _profiles[msg.sender];
        if (p.createdAt == 0) revert ProfileNotFound();

        p.avatar = avatar;
        p.bio = bio;
        delete p.links;
        for (uint256 i = 0; i < links.length; i++) {
            p.links.push(links[i]);
        }
        p.updatedAt = block.timestamp;

        emit ProfileUpdated(msg.sender, p.username);
    }

    // ── Verification ───────────────────────────────────────────────────────────
    /// @notice Verifier attests that a user's profile is genuine.
    function verifyProfile(address user) external onlyVerifier whenNotPaused {
        Profile storage p = _profiles[user];
        if (p.createdAt == 0) revert ProfileNotFound();
        if (p.verified) revert AlreadyVerified();
        p.verified = true;
        p.verifiedBy = msg.sender;
        emit ProfileVerified(user, msg.sender);
    }

    /// @notice Verifier or owner revokes verification.
    function unverifyProfile(address user) external onlyVerifier whenNotPaused {
        Profile storage p = _profiles[user];
        if (p.createdAt == 0) revert ProfileNotFound();
        if (!p.verified) revert NotVerified();
        p.verified = false;
        p.verifiedBy = address(0);
        emit ProfileUnverified(user, msg.sender);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────
    /// @notice Add a verifier address.
    function addVerifier(address verifier) external onlyOwner {
        isVerifier[verifier] = true;
        emit VerifierAdded(verifier);
    }

    /// @notice Remove a verifier address.
    function removeVerifier(address verifier) external onlyOwner {
        isVerifier[verifier] = false;
        emit VerifierRemoved(verifier);
    }

    /// @notice Set registration fee.
    function setRegistrationFee(uint256 fee) external onlyOwner {
        registrationFee = fee;
        emit RegistrationFeeUpdated(fee);
    }

    /// @notice Withdraw collected fees.
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        if (bal == 0) revert TransferFailed();
        (bool ok, ) = payable(owner()).call{value: bal}("");
        if (!ok) revert TransferFailed();
        emit FeesWithdrawn(owner(), bal);
    }

    // ── Views ──────────────────────────────────────────────────────────────────
    /// @notice Get a user's profile.
    function getProfile(address user) external view returns (Profile memory) {
        if (_profiles[user].createdAt == 0) revert ProfileNotFound();
        return _profiles[user];
    }

    /// @notice Look up a wallet address by username.
    function getAddressByUsername(string calldata username) external view returns (address) {
        address addr = _usernameToAddress[username];
        if (addr == address(0)) revert ProfileNotFound();
        return addr;
    }
}
