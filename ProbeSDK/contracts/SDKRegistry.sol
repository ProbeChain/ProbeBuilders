// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SDKRegistry
 * @author ProbeChain Team
 * @notice On-chain registry for SDK packages with download integrity verification
 * @dev Supports TypeScript, Python, Rust, Go languages with versioned releases
 */
contract SDKRegistry {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "SDKRegistry: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "SDKRegistry: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "SDKRegistry: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums ──────────────────────────────────────────────────────────
    enum Language { TypeScript, Python, Rust, Go }

    // ─── Structs ────────────────────────────────────────────────────────
    struct SDKVersion {
        string version;
        bytes32 downloadHash;
        uint256 timestamp;
        bool deprecated;
    }

    struct SDK {
        uint256 id;
        string name;
        Language language;
        address publisher;
        uint256 createdAt;
        bool active;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public sdkCount;
    mapping(uint256 => SDK) public sdks;
    mapping(uint256 => SDKVersion[]) public sdkVersions;
    mapping(string => mapping(uint8 => uint256)) public sdkByNameAndLang;
    mapping(address => bool) public verifiedPublishers;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a new SDK is registered
    event SDKRegistered(uint256 indexed sdkId, string name, Language language, address indexed publisher);
    /// @notice Emitted when a new version is published
    event SDKUpdated(uint256 indexed sdkId, string version, bytes32 downloadHash);
    /// @notice Emitted when a download hash is verified
    event DownloadVerified(uint256 indexed sdkId, bytes32 hash, bool valid);
    /// @notice Emitted when a version is deprecated
    event VersionDeprecated(uint256 indexed sdkId, uint256 versionIndex);
    /// @notice Emitted when publisher is verified
    event PublisherVerified(address indexed publisher, bool status);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Publisher Management ───────────────────────────────────────────
    /**
     * @notice Verify or unverify a publisher
     * @param publisher Address to modify
     * @param status Verification status
     */
    function setVerifiedPublisher(address publisher, bool status) external onlyOwner {
        verifiedPublishers[publisher] = status;
        emit PublisherVerified(publisher, status);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register a new SDK in the registry
     * @param name Human-readable SDK name
     * @param language Programming language (0=TS, 1=Py, 2=Rust, 3=Go)
     * @param version Initial version string (e.g., "1.0.0")
     * @param downloadHash SHA-256 hash of the download package
     */
    function registerSDK(
        string calldata name,
        Language language,
        string calldata version,
        bytes32 downloadHash
    ) external whenNotPaused {
        require(bytes(name).length > 0, "SDKRegistry: empty name");
        require(bytes(version).length > 0, "SDKRegistry: empty version");
        require(downloadHash != bytes32(0), "SDKRegistry: empty hash");
        require(
            sdkByNameAndLang[name][uint8(language)] == 0,
            "SDKRegistry: SDK already registered for this language"
        );

        sdkCount++;
        uint256 sdkId = sdkCount;

        sdks[sdkId] = SDK({
            id: sdkId,
            name: name,
            language: language,
            publisher: msg.sender,
            createdAt: block.timestamp,
            active: true
        });

        sdkVersions[sdkId].push(SDKVersion({
            version: version,
            downloadHash: downloadHash,
            timestamp: block.timestamp,
            deprecated: false
        }));

        sdkByNameAndLang[name][uint8(language)] = sdkId;

        emit SDKRegistered(sdkId, name, language, msg.sender);
        emit SDKUpdated(sdkId, version, downloadHash);
    }

    /**
     * @notice Update an SDK with a new version
     * @param sdkId ID of the SDK to update
     * @param version New version string
     * @param downloadHash SHA-256 hash of the new download package
     */
    function updateSDK(
        uint256 sdkId,
        string calldata version,
        bytes32 downloadHash
    ) external whenNotPaused {
        SDK storage sdk = sdks[sdkId];
        require(sdk.active, "SDKRegistry: SDK not active");
        require(sdk.publisher == msg.sender, "SDKRegistry: not publisher");
        require(bytes(version).length > 0, "SDKRegistry: empty version");
        require(downloadHash != bytes32(0), "SDKRegistry: empty hash");

        sdkVersions[sdkId].push(SDKVersion({
            version: version,
            downloadHash: downloadHash,
            timestamp: block.timestamp,
            deprecated: false
        }));

        emit SDKUpdated(sdkId, version, downloadHash);
    }

    /**
     * @notice Verify a download hash against the on-chain record
     * @param sdkId SDK to verify against
     * @param hash Hash to check
     * @return valid True if the hash matches any non-deprecated version
     */
    function verifyDownload(uint256 sdkId, bytes32 hash) external returns (bool valid) {
        SDKVersion[] storage versions = sdkVersions[sdkId];
        for (uint256 i = 0; i < versions.length; i++) {
            if (!versions[i].deprecated && versions[i].downloadHash == hash) {
                emit DownloadVerified(sdkId, hash, true);
                return true;
            }
        }
        emit DownloadVerified(sdkId, hash, false);
        return false;
    }

    /**
     * @notice Get the latest non-deprecated version of an SDK
     * @param name SDK name
     * @param language SDK language
     * @return version Latest version string
     * @return downloadHash Latest download hash
     * @return timestamp Release timestamp
     */
    function getLatestVersion(
        string calldata name,
        Language language
    ) external view returns (string memory version, bytes32 downloadHash, uint256 timestamp) {
        uint256 sdkId = sdkByNameAndLang[name][uint8(language)];
        require(sdkId > 0, "SDKRegistry: SDK not found");

        SDKVersion[] storage versions = sdkVersions[sdkId];
        for (uint256 i = versions.length; i > 0; i--) {
            if (!versions[i - 1].deprecated) {
                SDKVersion storage v = versions[i - 1];
                return (v.version, v.downloadHash, v.timestamp);
            }
        }
        revert("SDKRegistry: no active version");
    }

    /**
     * @notice Deprecate a specific version
     * @param sdkId SDK ID
     * @param versionIndex Index of the version to deprecate
     */
    function deprecateVersion(uint256 sdkId, uint256 versionIndex) external {
        require(sdks[sdkId].publisher == msg.sender, "SDKRegistry: not publisher");
        require(versionIndex < sdkVersions[sdkId].length, "SDKRegistry: invalid index");

        sdkVersions[sdkId][versionIndex].deprecated = true;
        emit VersionDeprecated(sdkId, versionIndex);
    }

    /**
     * @notice Deactivate an SDK entirely
     * @param sdkId SDK to deactivate
     */
    function deactivateSDK(uint256 sdkId) external {
        require(
            sdks[sdkId].publisher == msg.sender || msg.sender == _owner,
            "SDKRegistry: unauthorized"
        );
        sdks[sdkId].active = false;
    }

    /**
     * @notice Get total version count for an SDK
     * @param sdkId SDK ID
     * @return count Number of versions
     */
    function getVersionCount(uint256 sdkId) external view returns (uint256 count) {
        return sdkVersions[sdkId].length;
    }

    /**
     * @notice Get a specific version by index
     * @param sdkId SDK ID
     * @param index Version index
     * @return v The version details
     */
    function getVersion(uint256 sdkId, uint256 index) external view returns (SDKVersion memory v) {
        require(index < sdkVersions[sdkId].length, "SDKRegistry: invalid index");
        return sdkVersions[sdkId][index];
    }
}
