// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ModelVersioning
 * @author ProbeChain Team
 * @notice On-chain model version registry for AI/ML models on ProbeChain Rydberg Testnet
 * @dev Tracks model versions, changelogs, and deprecation status with full audit trail
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender);
        _;
    }

    function owner() public view virtual returns (address) { return _owner; }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;
    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardReentrantCall();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    error ExpectedPause();

    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    modifier whenPaused() { if (!_paused) revert ExpectedPause(); _; }

    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

contract ModelVersioning is Ownable, ReentrancyGuard, Pausable {
    /// @notice Version entry for a model
    struct Version {
        uint256 versionNumber;
        bytes32 versionHash;
        string changelog;
        uint256 timestamp;
        bool deprecated;
    }

    /// @notice Model registration data
    struct Model {
        uint256 id;
        string name;
        address registrar;
        uint256 versionCount;
        uint256 createdAt;
        bool active;
    }

    mapping(uint256 => Model) private _models;
    mapping(uint256 => mapping(uint256 => Version)) private _versions;
    mapping(string => uint256) private _nameToId;
    mapping(address => uint256[]) private _registrarModels;

    uint256 private _nextModelId = 1;

    /// @notice Emitted when a new model is registered
    event ModelRegistered(uint256 indexed modelId, string name, address indexed registrar, bytes32 initialHash);
    /// @notice Emitted when a new version is pushed
    event VersionPushed(uint256 indexed modelId, uint256 versionNumber, bytes32 versionHash, string changelog);
    /// @notice Emitted when a version is deprecated
    event VersionDeprecated(uint256 indexed modelId, uint256 versionNumber);

    error ModelNotFound(uint256 modelId);
    error ModelNameTaken(string name);
    error ModelInactive(uint256 modelId);
    error VersionNotFound(uint256 modelId, uint256 versionNumber);
    error NotModelRegistrar(address caller);
    error EmptyName();
    error AlreadyDeprecated(uint256 modelId, uint256 versionNumber);

    /**
     * @notice Register a new model in the registry
     * @param name Human-readable model name (must be unique)
     * @param initialHash Hash of the initial model artifact
     * @return modelId The assigned model ID
     */
    function registerModel(
        string calldata name,
        bytes32 initialHash
    ) external whenNotPaused returns (uint256 modelId) {
        if (bytes(name).length == 0) revert EmptyName();
        if (_nameToId[name] != 0) revert ModelNameTaken(name);

        modelId = _nextModelId++;
        _models[modelId] = Model({
            id: modelId,
            name: name,
            registrar: msg.sender,
            versionCount: 1,
            createdAt: block.timestamp,
            active: true
        });

        _versions[modelId][1] = Version({
            versionNumber: 1,
            versionHash: initialHash,
            changelog: "Initial version",
            timestamp: block.timestamp,
            deprecated: false
        });

        _nameToId[name] = modelId;
        _registrarModels[msg.sender].push(modelId);

        emit ModelRegistered(modelId, name, msg.sender, initialHash);
        emit VersionPushed(modelId, 1, initialHash, "Initial version");
    }

    /**
     * @notice Push a new version for an existing model
     * @param modelId The model to update
     * @param versionHash Hash of the new model artifact
     * @param changelog Description of changes
     * @return versionNumber The new version number
     */
    function pushVersion(
        uint256 modelId,
        bytes32 versionHash,
        string calldata changelog
    ) external whenNotPaused returns (uint256 versionNumber) {
        Model storage model = _models[modelId];
        if (model.id == 0) revert ModelNotFound(modelId);
        if (!model.active) revert ModelInactive(modelId);
        if (model.registrar != msg.sender) revert NotModelRegistrar(msg.sender);

        versionNumber = ++model.versionCount;
        _versions[modelId][versionNumber] = Version({
            versionNumber: versionNumber,
            versionHash: versionHash,
            changelog: changelog,
            timestamp: block.timestamp,
            deprecated: false
        });

        emit VersionPushed(modelId, versionNumber, versionHash, changelog);
    }

    /**
     * @notice Get the latest version of a model
     * @param modelId The model to query
     * @return version The latest version data
     */
    function getLatestVersion(uint256 modelId) external view returns (Version memory version) {
        Model storage model = _models[modelId];
        if (model.id == 0) revert ModelNotFound(modelId);
        return _versions[modelId][model.versionCount];
    }

    /**
     * @notice Compare two versions of a model
     * @param modelId The model to query
     * @param v1 First version number
     * @param v2 Second version number
     * @return version1 The first version data
     * @return version2 The second version data
     * @return hashMatch Whether both version hashes are identical
     */
    function compareVersions(
        uint256 modelId,
        uint256 v1,
        uint256 v2
    ) external view returns (Version memory version1, Version memory version2, bool hashMatch) {
        if (_models[modelId].id == 0) revert ModelNotFound(modelId);
        if (_versions[modelId][v1].versionNumber == 0) revert VersionNotFound(modelId, v1);
        if (_versions[modelId][v2].versionNumber == 0) revert VersionNotFound(modelId, v2);

        version1 = _versions[modelId][v1];
        version2 = _versions[modelId][v2];
        hashMatch = version1.versionHash == version2.versionHash;
    }

    /**
     * @notice Deprecate a specific version
     * @param modelId The model containing the version
     * @param versionNumber The version to deprecate
     */
    function deprecateVersion(uint256 modelId, uint256 versionNumber) external whenNotPaused {
        Model storage model = _models[modelId];
        if (model.id == 0) revert ModelNotFound(modelId);
        if (model.registrar != msg.sender && owner() != msg.sender) revert NotModelRegistrar(msg.sender);

        Version storage ver = _versions[modelId][versionNumber];
        if (ver.versionNumber == 0) revert VersionNotFound(modelId, versionNumber);
        if (ver.deprecated) revert AlreadyDeprecated(modelId, versionNumber);

        ver.deprecated = true;
        emit VersionDeprecated(modelId, versionNumber);
    }

    /**
     * @notice Get a specific version of a model
     * @param modelId The model to query
     * @param versionNumber The version number
     * @return version The version data
     */
    function getVersion(uint256 modelId, uint256 versionNumber) external view returns (Version memory version) {
        if (_models[modelId].id == 0) revert ModelNotFound(modelId);
        if (_versions[modelId][versionNumber].versionNumber == 0) revert VersionNotFound(modelId, versionNumber);
        return _versions[modelId][versionNumber];
    }

    /**
     * @notice Get model metadata
     * @param modelId The model to query
     * @return model The model data
     */
    function getModel(uint256 modelId) external view returns (Model memory model) {
        if (_models[modelId].id == 0) revert ModelNotFound(modelId);
        return _models[modelId];
    }

    /**
     * @notice Get model ID by name
     * @param name The model name
     * @return modelId The model ID (0 if not found)
     */
    function getModelByName(string calldata name) external view returns (uint256 modelId) {
        return _nameToId[name];
    }

    /**
     * @notice Deactivate a model (no more versions can be pushed)
     * @param modelId The model to deactivate
     */
    function deactivateModel(uint256 modelId) external {
        Model storage model = _models[modelId];
        if (model.id == 0) revert ModelNotFound(modelId);
        if (model.registrar != msg.sender && owner() != msg.sender) revert NotModelRegistrar(msg.sender);
        model.active = false;
    }

    /**
     * @notice Get all models registered by an address
     * @param registrar The registrar address
     * @return ids Array of model IDs
     */
    function getRegistrarModels(address registrar) external view returns (uint256[] memory ids) {
        return _registrarModels[registrar];
    }
}
