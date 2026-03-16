// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title HumanVerifier
 * @author ProbeChain
 * @notice Sybil resistance via challenge-response human verification
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: not owner");
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract Pausable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    constructor() { _paused = false; }

    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }

    function paused() public view returns (bool) { return _paused; }
    function _pause() internal whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function _unpause() internal whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

contract HumanVerifier is Ownable, Pausable {
    /// @notice Challenge types for human verification
    enum ChallengeType { Captcha, Social, Biometric }

    /// @notice Challenge status
    enum ChallengeStatus { Active, Responded, Verified, Failed, Expired }

    /// @notice Challenge data structure
    struct Challenge {
        uint256 id;
        address user;
        ChallengeType challengeType;
        bytes32 challengeHash;
        bytes32 responseHash;
        ChallengeStatus status;
        uint256 createdAt;
        uint256 expiresAt;
        address verifiedBy;
    }

    /// @notice Human verification record
    struct HumanRecord {
        bool verified;
        uint256 verifiedAt;
        uint256 challengeId;
        uint256 expiresAt;
    }

    /// @dev Counter for challenge IDs
    uint256 private _nextChallengeId;

    /// @dev Challenge expiration duration
    uint256 public challengeDuration;

    /// @dev Verification validity duration
    uint256 public verificationValidity;

    /// @dev Challenge ID => Challenge
    mapping(uint256 => Challenge) private _challenges;

    /// @dev Address => human verification record
    mapping(address => HumanRecord) private _humanRecords;

    /// @dev Authorized verifiers
    mapping(address => bool) public verifiers;

    /// @dev User => active challenge IDs
    mapping(address => uint256[]) private _userChallenges;

    // ───────── Events ─────────

    /// @notice Emitted when a challenge is started
    event ChallengeStarted(uint256 indexed challengeId, address indexed user, ChallengeType challengeType);

    /// @notice Emitted when a challenge response is submitted
    event ChallengeResponseSubmitted(uint256 indexed challengeId, address indexed user);

    /// @notice Emitted when a human is verified
    event HumanVerified(uint256 indexed challengeId, address indexed user, address indexed verifier);

    /// @notice Emitted when verification fails
    event VerificationFailed(uint256 indexed challengeId, address indexed user);

    /// @notice Emitted when a verifier is updated
    event VerifierUpdated(address indexed verifier, bool status);

    /// @notice Emitted when verification expires
    event VerificationExpired(address indexed user);

    // ───────── Constructor ─────────

    constructor() {
        _nextChallengeId = 1;
        challengeDuration = 1 hours;
        verificationValidity = 365 days;
    }

    // ───────── Admin ─────────

    /// @notice Set verifier status
    function setVerifier(address verifier, bool status) external onlyOwner {
        require(verifier != address(0), "HumanVerifier: zero address");
        verifiers[verifier] = status;
        emit VerifierUpdated(verifier, status);
    }

    /// @notice Update challenge duration
    function setChallengeDuration(uint256 duration) external onlyOwner {
        require(duration >= 5 minutes, "HumanVerifier: too short");
        challengeDuration = duration;
    }

    /// @notice Update verification validity
    function setVerificationValidity(uint256 validity) external onlyOwner {
        require(validity >= 1 days, "HumanVerifier: too short");
        verificationValidity = validity;
    }

    /// @notice Pause the contract
    function pause() external onlyOwner { _pause(); }

    /// @notice Unpause the contract
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Start a challenge for a user
    /// @param user The address to challenge
    /// @param challengeType The type of challenge
    /// @param challengeHash Hash of the challenge data
    /// @return challengeId The new challenge ID
    function startChallenge(
        address user,
        ChallengeType challengeType,
        bytes32 challengeHash
    ) external whenNotPaused returns (uint256 challengeId) {
        require(verifiers[msg.sender] || msg.sender == owner(), "HumanVerifier: not authorized");
        require(user != address(0), "HumanVerifier: zero address");
        require(challengeHash != bytes32(0), "HumanVerifier: empty hash");

        challengeId = _nextChallengeId++;

        _challenges[challengeId] = Challenge({
            id: challengeId,
            user: user,
            challengeType: challengeType,
            challengeHash: challengeHash,
            responseHash: bytes32(0),
            status: ChallengeStatus.Active,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + challengeDuration,
            verifiedBy: address(0)
        });

        _userChallenges[user].push(challengeId);

        emit ChallengeStarted(challengeId, user, challengeType);
    }

    /// @notice Submit a response to a challenge
    /// @param challengeId The challenge to respond to
    /// @param responseHash Hash of the response data
    function submitChallengeResponse(
        uint256 challengeId,
        bytes32 responseHash
    ) external whenNotPaused {
        Challenge storage c = _challenges[challengeId];
        require(c.id != 0, "HumanVerifier: not found");
        require(c.user == msg.sender, "HumanVerifier: not your challenge");
        require(c.status == ChallengeStatus.Active, "HumanVerifier: not active");
        require(block.timestamp <= c.expiresAt, "HumanVerifier: expired");
        require(responseHash != bytes32(0), "HumanVerifier: empty response");

        c.responseHash = responseHash;
        c.status = ChallengeStatus.Responded;

        emit ChallengeResponseSubmitted(challengeId, msg.sender);
    }

    /// @notice Verify a challenge response (verifier only)
    /// @param challengeId The challenge to verify
    /// @param approved Whether the response is valid
    function verifyHuman(
        uint256 challengeId,
        bool approved
    ) external whenNotPaused {
        require(verifiers[msg.sender], "HumanVerifier: not verifier");

        Challenge storage c = _challenges[challengeId];
        require(c.id != 0, "HumanVerifier: not found");
        require(c.status == ChallengeStatus.Responded, "HumanVerifier: not responded");

        if (approved) {
            c.status = ChallengeStatus.Verified;
            c.verifiedBy = msg.sender;

            _humanRecords[c.user] = HumanRecord({
                verified: true,
                verifiedAt: block.timestamp,
                challengeId: challengeId,
                expiresAt: block.timestamp + verificationValidity
            });

            emit HumanVerified(challengeId, c.user, msg.sender);
        } else {
            c.status = ChallengeStatus.Failed;
            emit VerificationFailed(challengeId, c.user);
        }
    }

    // ───────── View Functions ─────────

    /// @notice Check if an address is human-verified
    /// @param addr The address to check
    /// @return True if verified and not expired
    function isHuman(address addr) external view returns (bool) {
        HumanRecord memory record = _humanRecords[addr];
        return record.verified && block.timestamp <= record.expiresAt;
    }

    /// @notice Get challenge details
    /// @param challengeId The challenge ID
    /// @return The challenge struct
    function getChallenge(uint256 challengeId) external view returns (Challenge memory) {
        require(_challenges[challengeId].id != 0, "HumanVerifier: not found");
        return _challenges[challengeId];
    }

    /// @notice Get human record for an address
    /// @param addr The address
    /// @return The human record
    function getHumanRecord(address addr) external view returns (HumanRecord memory) {
        return _humanRecords[addr];
    }

    /// @notice Get all challenge IDs for a user
    /// @param user The user address
    /// @return Array of challenge IDs
    function getUserChallenges(address user) external view returns (uint256[] memory) {
        return _userChallenges[user];
    }

    /// @notice Total challenges created
    /// @return count The total count
    function totalChallenges() external view returns (uint256 count) {
        return _nextChallengeId - 1;
    }
}
