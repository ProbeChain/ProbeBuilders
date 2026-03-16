// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title ToolRegistry
 * @author ProbeBuilders
 * @notice CLI tool registry on-chain for download integrity verification
 * @dev Tracks tool versions, download hashes, and platform support
 */

abstract contract Ownable {
    address private _owner;
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert OwnableInvalidOwner(address(0));
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender);
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
}

/// @title ToolRegistry — CLI tool registry for download integrity
contract ToolRegistry is Ownable, Pausable {

    /// @notice Tool version entry
    struct ToolVersion {
        string version;
        bytes32 downloadHash;
        string platform;          // e.g., "linux-amd64", "darwin-arm64", "windows-amd64"
        string downloadURL;
        uint64 publishedAt;
        bool deprecated;
    }

    /// @notice Tool metadata
    struct Tool {
        string name;
        address publisher;
        string description;
        string repository;
        uint256 versionCount;
        uint64 createdAt;
        bool active;
    }

    uint256 public nextToolId = 1;

    mapping(uint256 => Tool) public tools;
    /// @notice toolId => version index => ToolVersion
    mapping(uint256 => mapping(uint256 => ToolVersion)) public toolVersions;
    /// @notice name hash => toolId (for lookup by name)
    mapping(bytes32 => uint256) public toolByName;
    /// @notice publisher => toolIds
    mapping(address => uint256[]) public publisherTools;
    /// @notice Verified publishers
    mapping(address => bool) public verifiedPublishers;

    event ToolRegistered(uint256 indexed toolId, string name, address indexed publisher);
    event ToolUpdated(uint256 indexed toolId, string version, bytes32 downloadHash, string platform);
    event ToolDeprecated(uint256 indexed toolId, uint256 versionIndex);
    event ToolDeactivated(uint256 indexed toolId);
    event PublisherVerified(address indexed publisher, bool verified);
    event DownloadVerified(uint256 indexed toolId, uint256 versionIndex, address indexed verifier, bool valid);

    error NotPublisher();
    error ToolNotFound();
    error ToolNotActive();
    error NameAlreadyTaken();
    error InvalidName();
    error InvalidVersion();

    constructor() Ownable(msg.sender) {}

    /// @notice Register a new tool
    /// @param name_ Tool name (unique)
    /// @param description_ Tool description
    /// @param repository_ Source repository URL
    /// @param version_ Initial version string
    /// @param downloadHash_ SHA-256 hash of the download
    /// @param platform_ Target platform
    /// @param downloadURL_ Download URL
    /// @return toolId Registered tool ID
    function registerTool(
        string calldata name_,
        string calldata description_,
        string calldata repository_,
        string calldata version_,
        bytes32 downloadHash_,
        string calldata platform_,
        string calldata downloadURL_
    ) external whenNotPaused returns (uint256 toolId) {
        bytes32 nameHash = keccak256(abi.encodePacked(name_));
        if (bytes(name_).length == 0 || bytes(name_).length > 64) revert InvalidName();
        if (toolByName[nameHash] != 0) revert NameAlreadyTaken();
        if (bytes(version_).length == 0) revert InvalidVersion();

        toolId = nextToolId++;
        tools[toolId] = Tool({
            name: name_,
            publisher: msg.sender,
            description: description_,
            repository: repository_,
            versionCount: 1,
            createdAt: uint64(block.timestamp),
            active: true
        });

        toolVersions[toolId][0] = ToolVersion({
            version: version_,
            downloadHash: downloadHash_,
            platform: platform_,
            downloadURL: downloadURL_,
            publishedAt: uint64(block.timestamp),
            deprecated: false
        });

        toolByName[nameHash] = toolId;
        publisherTools[msg.sender].push(toolId);

        emit ToolRegistered(toolId, name_, msg.sender);
        emit ToolUpdated(toolId, version_, downloadHash_, platform_);
    }

    /// @notice Publish a new version of a tool
    /// @param toolId Tool ID
    /// @param version_ New version string
    /// @param downloadHash_ SHA-256 hash of the download
    /// @param platform_ Target platform
    /// @param downloadURL_ Download URL
    function updateTool(
        uint256 toolId,
        string calldata version_,
        bytes32 downloadHash_,
        string calldata platform_,
        string calldata downloadURL_
    ) external whenNotPaused {
        Tool storage t = tools[toolId];
        if (t.publisher != msg.sender) revert NotPublisher();
        if (!t.active) revert ToolNotActive();
        if (bytes(version_).length == 0) revert InvalidVersion();

        uint256 idx = t.versionCount;
        t.versionCount++;

        toolVersions[toolId][idx] = ToolVersion({
            version: version_,
            downloadHash: downloadHash_,
            platform: platform_,
            downloadURL: downloadURL_,
            publishedAt: uint64(block.timestamp),
            deprecated: false
        });

        emit ToolUpdated(toolId, version_, downloadHash_, platform_);
    }

    /// @notice Get latest version info for a tool
    /// @param toolId Tool ID
    /// @return version Version string
    /// @return downloadHash Download hash
    /// @return platform Platform string
    /// @return downloadURL Download URL
    function getLatestVersion(uint256 toolId)
        external
        view
        returns (
            string memory version,
            bytes32 downloadHash,
            string memory platform,
            string memory downloadURL
        )
    {
        Tool storage t = tools[toolId];
        if (t.versionCount == 0) revert ToolNotFound();

        // Find latest non-deprecated version
        for (uint256 i = t.versionCount; i > 0; i--) {
            ToolVersion storage v = toolVersions[toolId][i - 1];
            if (!v.deprecated) {
                return (v.version, v.downloadHash, v.platform, v.downloadURL);
            }
        }
        revert ToolNotFound();
    }

    /// @notice Verify a download hash matches a tool version
    /// @param toolId Tool ID
    /// @param hash Hash to verify
    /// @return valid True if hash matches any non-deprecated version
    /// @return version Matching version string
    function verifyDownload(uint256 toolId, bytes32 hash)
        external
        view
        returns (bool valid, string memory version)
    {
        Tool storage t = tools[toolId];
        for (uint256 i = 0; i < t.versionCount; i++) {
            ToolVersion storage v = toolVersions[toolId][i];
            if (v.downloadHash == hash && !v.deprecated) {
                return (true, v.version);
            }
        }
        return (false, "");
    }

    /// @notice Deprecate a specific version
    function deprecateVersion(uint256 toolId, uint256 versionIndex) external {
        Tool storage t = tools[toolId];
        if (t.publisher != msg.sender) revert NotPublisher();
        require(versionIndex < t.versionCount, "Invalid index");

        toolVersions[toolId][versionIndex].deprecated = true;
        emit ToolDeprecated(toolId, versionIndex);
    }

    /// @notice Deactivate a tool entirely
    function deactivateTool(uint256 toolId) external {
        Tool storage t = tools[toolId];
        if (t.publisher != msg.sender && msg.sender != owner()) revert NotPublisher();
        t.active = false;
        emit ToolDeactivated(toolId);
    }

    /// @notice Verify/unverify a publisher (owner only)
    function setVerifiedPublisher(address publisher, bool verified) external onlyOwner {
        verifiedPublishers[publisher] = verified;
        emit PublisherVerified(publisher, verified);
    }

    /// @notice Look up tool ID by name
    function getToolIdByName(string calldata name_) external view returns (uint256) {
        bytes32 nameHash = keccak256(abi.encodePacked(name_));
        uint256 id = toolByName[nameHash];
        if (id == 0) revert ToolNotFound();
        return id;
    }

    /// @notice Get all tool IDs for a publisher
    function getPublisherTools(address publisher) external view returns (uint256[] memory) {
        return publisherTools[publisher];
    }
}
