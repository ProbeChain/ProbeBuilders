// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title VoiceMarket
 * @author ProbeChain
 * @notice Voice model marketplace with consent verification and abuse reporting on ProbeChain Rydberg Testnet
 * @dev Manages voice registration, listing, usage payments, and abuse reports
 */

/// @dev Minimal Ownable implementation
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/// @dev Minimal ReentrancyGuard implementation
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/// @dev Minimal Pausable implementation
abstract contract Pausable is Ownable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    function pause() public onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract VoiceMarket is Ownable, ReentrancyGuard, Pausable {
    // ─── Types ───────────────────────────────────────────────────────────
    enum VoiceStatus { Pending, Approved, Suspended, Banned }
    enum AbuseType { Impersonation, NonConsensual, Harassment, Fraud, Other }

    struct Voice {
        uint256 id;
        address voiceOwner;
        string name;
        bytes32 sampleHash;
        bool ownerConsent;
        VoiceStatus status;
        uint256 pricePerUse;
        bool listed;
        uint256 totalUses;
        uint256 totalEarnings;
        uint256 registeredAt;
    }

    struct AbuseReport {
        uint256 id;
        uint256 voiceId;
        address reporter;
        AbuseType abuseType;
        string evidence;
        bool resolved;
        uint256 reportedAt;
    }

    struct UsageLog {
        uint256 voiceId;
        address user;
        uint256 amountPaid;
        uint256 timestamp;
    }

    // ─── State ───────────────────────────────────────────────────────────
    uint256 public voiceCount;
    uint256 public reportCount;
    uint256 public usageLogCount;
    uint256 public platformFeeBps = 500; // 5%
    uint256 public abuseThreshold = 3;

    mapping(uint256 => Voice) public voices;
    mapping(uint256 => AbuseReport) public abuseReports;
    mapping(uint256 => uint256) public voiceAbuseCount;
    mapping(uint256 => UsageLog) public usageLogs;
    mapping(address => bool) public approvedVerifiers;

    // ─── Events ──────────────────────────────────────────────────────────
    /// @notice Emitted when a new voice model is registered
    event VoiceRegistered(uint256 indexed voiceId, address indexed voiceOwner, string name, bytes32 sampleHash);

    /// @notice Emitted when a voice is listed for use
    event VoiceListed(uint256 indexed voiceId, uint256 pricePerUse);

    /// @notice Emitted when a voice is used
    event VoiceUsed(uint256 indexed voiceId, address indexed user, uint256 amountPaid);

    /// @notice Emitted when abuse is reported
    event AbuseReported(uint256 indexed reportId, uint256 indexed voiceId, address indexed reporter, AbuseType abuseType);

    /// @notice Emitted when a voice status changes
    event VoiceStatusChanged(uint256 indexed voiceId, VoiceStatus newStatus);

    /// @notice Emitted when a verifier is added or removed
    event VerifierUpdated(address indexed verifier, bool approved);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyVoiceOwner(uint256 _voiceId) {
        require(voices[_voiceId].voiceOwner == msg.sender, "Not voice owner");
        _;
    }

    // ─── Voice Management ────────────────────────────────────────────────

    /**
     * @notice Register a new voice model with consent verification
     * @param _name Name for the voice model
     * @param _sampleHash Hash of the voice sample data
     * @param _ownerConsent Whether the voice owner has given consent
     * @return voiceId The ID of the registered voice
     */
    function registerVoice(string calldata _name, bytes32 _sampleHash, bool _ownerConsent)
        external
        whenNotPaused
        returns (uint256 voiceId)
    {
        require(bytes(_name).length > 0 && bytes(_name).length <= 128, "Invalid name length");
        require(_sampleHash != bytes32(0), "Empty sample hash");
        require(_ownerConsent, "Owner consent required");

        voiceId = ++voiceCount;
        voices[voiceId] = Voice({
            id: voiceId,
            voiceOwner: msg.sender,
            name: _name,
            sampleHash: _sampleHash,
            ownerConsent: _ownerConsent,
            status: VoiceStatus.Approved,
            pricePerUse: 0,
            listed: false,
            totalUses: 0,
            totalEarnings: 0,
            registeredAt: block.timestamp
        });

        emit VoiceRegistered(voiceId, msg.sender, _name, _sampleHash);
    }

    /**
     * @notice List a voice model on the marketplace
     * @param _voiceId The voice ID
     * @param _pricePerUse Price per use in wei
     */
    function listVoice(uint256 _voiceId, uint256 _pricePerUse)
        external
        whenNotPaused
        onlyVoiceOwner(_voiceId)
    {
        Voice storage voice = voices[_voiceId];
        require(voice.status == VoiceStatus.Approved, "Voice not approved");
        require(_pricePerUse > 0, "Price must be > 0");

        voice.pricePerUse = _pricePerUse;
        voice.listed = true;

        emit VoiceListed(_voiceId, _pricePerUse);
    }

    /**
     * @notice Use a voice model (pay per use)
     * @param _voiceId The voice ID
     */
    function useVoice(uint256 _voiceId)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        Voice storage voice = voices[_voiceId];
        require(voice.listed, "Voice not listed");
        require(voice.status == VoiceStatus.Approved, "Voice not approved");
        require(msg.value >= voice.pricePerUse, "Insufficient payment");

        voice.totalUses++;
        voice.totalEarnings += msg.value;

        uint256 platformCut = (msg.value * platformFeeBps) / 10000;
        uint256 ownerPayment = msg.value - platformCut;

        // Log usage
        uint256 logId = ++usageLogCount;
        usageLogs[logId] = UsageLog({
            voiceId: _voiceId,
            user: msg.sender,
            amountPaid: msg.value,
            timestamp: block.timestamp
        });

        // Pay voice owner
        (bool sent, ) = voice.voiceOwner.call{value: ownerPayment}("");
        require(sent, "Payment to voice owner failed");

        emit VoiceUsed(_voiceId, msg.sender, msg.value);
    }

    /**
     * @notice Report abuse of a voice model
     * @param _voiceId The voice ID
     * @param _abuseType The type of abuse
     * @param _evidence Evidence description or URI
     */
    function reportAbuse(uint256 _voiceId, AbuseType _abuseType, string calldata _evidence)
        external
        whenNotPaused
    {
        require(voices[_voiceId].id != 0, "Voice does not exist");
        require(bytes(_evidence).length > 0, "Evidence required");

        uint256 reportId = ++reportCount;
        abuseReports[reportId] = AbuseReport({
            id: reportId,
            voiceId: _voiceId,
            reporter: msg.sender,
            abuseType: _abuseType,
            evidence: _evidence,
            resolved: false,
            reportedAt: block.timestamp
        });

        voiceAbuseCount[_voiceId]++;

        // Auto-suspend if threshold reached
        if (voiceAbuseCount[_voiceId] >= abuseThreshold) {
            voices[_voiceId].status = VoiceStatus.Suspended;
            voices[_voiceId].listed = false;
            emit VoiceStatusChanged(_voiceId, VoiceStatus.Suspended);
        }

        emit AbuseReported(reportId, _voiceId, msg.sender, _abuseType);
    }

    /**
     * @notice Delist a voice from the marketplace
     * @param _voiceId The voice ID
     */
    function delistVoice(uint256 _voiceId) external onlyVoiceOwner(_voiceId) {
        voices[_voiceId].listed = false;
    }

    /**
     * @notice Update voice status (admin only)
     * @param _voiceId The voice ID
     * @param _status New status
     */
    function setVoiceStatus(uint256 _voiceId, VoiceStatus _status) external onlyOwner {
        voices[_voiceId].status = _status;
        if (_status == VoiceStatus.Suspended || _status == VoiceStatus.Banned) {
            voices[_voiceId].listed = false;
        }
        emit VoiceStatusChanged(_voiceId, _status);
    }

    /**
     * @notice Update the platform fee
     * @param _newFeeBps New fee in basis points
     */
    function setPlatformFee(uint256 _newFeeBps) external onlyOwner {
        require(_newFeeBps <= 1500, "Fee too high (max 15%)");
        platformFeeBps = _newFeeBps;
    }

    /**
     * @notice Withdraw accumulated platform fees
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees");
        (bool sent, ) = owner().call{value: balance}("");
        require(sent, "Withdraw failed");
    }

    /**
     * @notice Get voice details
     * @param _voiceId The voice ID
     */
    function getVoice(uint256 _voiceId) external view returns (Voice memory) {
        return voices[_voiceId];
    }
}
