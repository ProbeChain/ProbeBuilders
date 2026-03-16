// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPRegistry
 * @author ProbeChain
 * @notice On-chain intellectual property registration, transfer, and licensing on ProbeChain Rydberg Testnet
 * @dev Supports Patent, Trademark, Copyright, and Trade Secret IP types with licensing and usage tracking
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

contract IPRegistry is Ownable, ReentrancyGuard, Pausable {
    // ─── Types ───────────────────────────────────────────────────────────
    enum IPType { Patent, Trademark, Copyright, TradeSecret }
    enum LicenseStatus { Active, Expired, Revoked }

    struct IPRecord {
        uint256 id;
        address currentOwner;
        string title;
        bytes32 contentHash;
        IPType ipType;
        string description;
        uint256 registeredAt;
        uint256 transferCount;
        bool active;
    }

    struct License {
        uint256 id;
        uint256 ipId;
        address licensee;
        string terms;
        uint256 fee;
        uint256 grantedAt;
        uint256 expiresAt;
        LicenseStatus status;
    }

    struct UsageRecord {
        uint256 ipId;
        bytes32 usageHash;
        address reporter;
        uint256 recordedAt;
    }

    // ─── State ───────────────────────────────────────────────────────────
    uint256 public ipCount;
    uint256 public licenseCount;
    uint256 public usageCount;
    uint256 public registrationFee = 0.001 ether;

    mapping(uint256 => IPRecord) public ipRecords;
    mapping(uint256 => License) public licenses;
    mapping(uint256 => UsageRecord) public usageRecords;
    mapping(bytes32 => bool) public contentHashExists;
    mapping(uint256 => uint256[]) public ipLicenses;
    mapping(uint256 => uint256[]) public ipUsages;

    // ─── Events ──────────────────────────────────────────────────────────
    /// @notice Emitted when new IP is registered
    event IPRegistered(uint256 indexed ipId, address indexed owner, string title, IPType ipType, bytes32 contentHash);

    /// @notice Emitted when IP ownership is transferred
    event IPTransferred(uint256 indexed ipId, address indexed from, address indexed to);

    /// @notice Emitted when a license is granted
    event LicenseGranted(uint256 indexed licenseId, uint256 indexed ipId, address indexed licensee, uint256 fee);

    /// @notice Emitted when usage is recorded
    event UsageRecorded(uint256 indexed ipId, bytes32 usageHash, address indexed reporter);

    /// @notice Emitted when registration fee is updated
    event RegistrationFeeUpdated(uint256 oldFee, uint256 newFee);

    /// @notice Emitted when a license status changes
    event LicenseStatusChanged(uint256 indexed licenseId, LicenseStatus newStatus);

    // ─── IP Registration ─────────────────────────────────────────────────

    /**
     * @notice Register a new intellectual property
     * @param _title Title of the IP
     * @param _contentHash Hash of the IP content/documentation
     * @param _ipType Type of intellectual property
     * @param _description Description of the IP
     * @return ipId The ID of the registered IP
     */
    function registerIP(
        string calldata _title,
        bytes32 _contentHash,
        IPType _ipType,
        string calldata _description
    ) external payable whenNotPaused returns (uint256 ipId) {
        require(bytes(_title).length > 0 && bytes(_title).length <= 256, "Invalid title length");
        require(_contentHash != bytes32(0), "Empty content hash");
        require(!contentHashExists[_contentHash], "Content already registered");
        require(msg.value >= registrationFee, "Insufficient registration fee");

        ipId = ++ipCount;
        contentHashExists[_contentHash] = true;

        ipRecords[ipId] = IPRecord({
            id: ipId,
            currentOwner: msg.sender,
            title: _title,
            contentHash: _contentHash,
            ipType: _ipType,
            description: _description,
            registeredAt: block.timestamp,
            transferCount: 0,
            active: true
        });

        emit IPRegistered(ipId, msg.sender, _title, _ipType, _contentHash);
    }

    /**
     * @notice Transfer IP ownership to a new address
     * @param _ipId The IP ID
     * @param _newOwner The new owner address
     */
    function transferIP(uint256 _ipId, address _newOwner) external whenNotPaused {
        IPRecord storage record = ipRecords[_ipId];
        require(record.active, "IP not active");
        require(record.currentOwner == msg.sender, "Not IP owner");
        require(_newOwner != address(0), "Invalid new owner");
        require(_newOwner != msg.sender, "Already owner");

        address previousOwner = record.currentOwner;
        record.currentOwner = _newOwner;
        record.transferCount++;

        emit IPTransferred(_ipId, previousOwner, _newOwner);
    }

    /**
     * @notice License an IP to another party
     * @param _ipId The IP ID
     * @param _licensee The licensee address
     * @param _terms The license terms (URI or description)
     * @param _fee The license fee in wei
     * @return licenseId The ID of the created license
     */
    function licenseIP(
        uint256 _ipId,
        address _licensee,
        string calldata _terms,
        uint256 _fee
    ) external payable whenNotPaused nonReentrant returns (uint256 licenseId) {
        IPRecord storage record = ipRecords[_ipId];
        require(record.active, "IP not active");
        require(record.currentOwner == msg.sender || msg.sender == _licensee, "Not authorized");

        if (msg.sender == _licensee) {
            require(msg.value >= _fee, "Insufficient license fee");
            (bool sent, ) = record.currentOwner.call{value: _fee}("");
            require(sent, "Fee transfer failed");
        }

        licenseId = ++licenseCount;
        licenses[licenseId] = License({
            id: licenseId,
            ipId: _ipId,
            licensee: _licensee,
            terms: _terms,
            fee: _fee,
            grantedAt: block.timestamp,
            expiresAt: block.timestamp + 365 days,
            status: LicenseStatus.Active
        });

        ipLicenses[_ipId].push(licenseId);

        emit LicenseGranted(licenseId, _ipId, _licensee, _fee);
    }

    /**
     * @notice Record usage of an IP
     * @param _ipId The IP ID
     * @param _usageHash Hash of the usage proof
     */
    function recordUsage(uint256 _ipId, bytes32 _usageHash) external whenNotPaused {
        require(ipRecords[_ipId].active, "IP not active");
        require(_usageHash != bytes32(0), "Empty usage hash");

        uint256 usageId = ++usageCount;
        usageRecords[usageId] = UsageRecord({
            ipId: _ipId,
            usageHash: _usageHash,
            reporter: msg.sender,
            recordedAt: block.timestamp
        });

        ipUsages[_ipId].push(usageId);

        emit UsageRecorded(_ipId, _usageHash, msg.sender);
    }

    /**
     * @notice Revoke a license (IP owner only)
     * @param _licenseId The license ID
     */
    function revokeLicense(uint256 _licenseId) external whenNotPaused {
        License storage lic = licenses[_licenseId];
        require(ipRecords[lic.ipId].currentOwner == msg.sender, "Not IP owner");
        require(lic.status == LicenseStatus.Active, "License not active");

        lic.status = LicenseStatus.Revoked;
        emit LicenseStatusChanged(_licenseId, LicenseStatus.Revoked);
    }

    /**
     * @notice Update the registration fee
     * @param _newFee New fee in wei
     */
    function setRegistrationFee(uint256 _newFee) external onlyOwner {
        emit RegistrationFeeUpdated(registrationFee, _newFee);
        registrationFee = _newFee;
    }

    /**
     * @notice Withdraw accumulated fees
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        (bool sent, ) = owner().call{value: balance}("");
        require(sent, "Withdraw failed");
    }

    /**
     * @notice Get all license IDs for an IP
     * @param _ipId The IP ID
     */
    function getIPLicenses(uint256 _ipId) external view returns (uint256[] memory) {
        return ipLicenses[_ipId];
    }

    /**
     * @notice Get all usage record IDs for an IP
     * @param _ipId The IP ID
     */
    function getIPUsages(uint256 _ipId) external view returns (uint256[] memory) {
        return ipUsages[_ipId];
    }
}
