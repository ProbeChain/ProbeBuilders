// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ProvenanceTracker
 * @author ProbeChain
 * @notice Data provenance tracking with origin registration, transformations, and auditor certification
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London)
 */

// --- Inline Ownable ---
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorized(address account);
    error OwnableInvalidOwner(address owner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorized(msg.sender);
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(newOwner);
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// --- Inline ReentrancyGuard ---
abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardReentrantCall();
        _status = 2;
        _;
        _status = 1;
    }
}

// --- Inline Pausable ---
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();

    modifier whenNotPaused() {
        if (_paused) revert ContractPaused();
        _;
    }

    function paused() public view returns (bool) { return _paused; }

    function pause() external onlyOwner {
        if (_paused) revert ContractPaused();
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        if (!_paused) revert ContractNotPaused();
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract ProvenanceTracker is Ownable, ReentrancyGuard, Pausable {
    // --- Types ---
    struct Origin {
        uint256 id;
        address registrar;
        bytes32 dataHash;
        string source;
        uint256 timestamp;
        string metadata;
        bool certified;
        address certifiedBy;
        uint256 certifiedAt;
    }

    struct Transformation {
        uint256 id;
        uint256 originId;
        address transformer;
        string transformType;
        bytes32 inputHash;
        bytes32 outputHash;
        uint256 timestamp;
    }

    // --- State ---
    uint256 public nextOriginId;
    uint256 public nextTransformId;

    mapping(uint256 => Origin) public origins;
    mapping(uint256 => Transformation) public transformations;
    mapping(bytes32 => uint256) public dataHashToOriginId;
    mapping(bytes32 => uint256) public dataHashToTransformId;
    mapping(uint256 => uint256[]) private _originTransformations;
    mapping(address => bool) public authorizedAuditors;
    mapping(address => uint256) public auditorCertCount;

    // --- Events ---
    event OriginRegistered(uint256 indexed originId, address indexed registrar, bytes32 dataHash, string source);
    event TransformationAdded(uint256 indexed transformId, uint256 indexed originId, string transformType, bytes32 outputHash);
    event DataCertified(uint256 indexed originId, address indexed auditor, uint256 timestamp);
    event AuditorAuthorized(address indexed auditor);
    event AuditorRevoked(address indexed auditor);
    event ProvenanceVerified(bytes32 indexed dataHash, uint256 originId, uint256 transformCount);

    // --- Errors ---
    error OriginNotFound();
    error DataHashAlreadyRegistered();
    error NotAuthorizedAuditor();
    error AlreadyCertified();
    error DataHashNotFound();
    error NotOriginRegistrar();
    error InvalidDataHash();

    // --- Auditor Management ---

    /// @notice Authorize an auditor
    function authorizeAuditor(address auditor) external onlyOwner {
        authorizedAuditors[auditor] = true;
        emit AuditorAuthorized(auditor);
    }

    /// @notice Revoke an auditor
    function revokeAuditor(address auditor) external onlyOwner {
        authorizedAuditors[auditor] = false;
        emit AuditorRevoked(auditor);
    }

    // --- Origin Registration ---

    /// @notice Register the origin of a data asset
    /// @param dataHash Unique hash identifying the data
    /// @param source Description of the data source
    /// @param timestamp Original creation timestamp
    /// @param metadata Additional metadata (JSON string)
    /// @return originId The ID of the registered origin
    function registerOrigin(
        bytes32 dataHash,
        string calldata source,
        uint256 timestamp,
        string calldata metadata
    ) external whenNotPaused returns (uint256 originId) {
        if (dataHash == bytes32(0)) revert InvalidDataHash();
        if (dataHashToOriginId[dataHash] != 0) revert DataHashAlreadyRegistered();

        originId = ++nextOriginId; // Start from 1 so 0 means not found
        origins[originId] = Origin({
            id: originId,
            registrar: msg.sender,
            dataHash: dataHash,
            source: source,
            timestamp: timestamp,
            metadata: metadata,
            certified: false,
            certifiedBy: address(0),
            certifiedAt: 0
        });

        dataHashToOriginId[dataHash] = originId;
        emit OriginRegistered(originId, msg.sender, dataHash, source);
    }

    /// @notice Add a transformation step to an origin
    /// @param originId The origin to add transformation to
    /// @param transformType Description of the transformation
    /// @param outputHash Hash of the transformed output data
    /// @return transformId The ID of the transformation
    function addTransformation(
        uint256 originId,
        string calldata transformType,
        bytes32 outputHash
    ) external whenNotPaused returns (uint256 transformId) {
        Origin storage origin = origins[originId];
        if (origin.registrar == address(0)) revert OriginNotFound();
        if (outputHash == bytes32(0)) revert InvalidDataHash();

        transformId = nextTransformId++;

        // Determine input hash: last transform's output or origin's data hash
        uint256[] storage transforms = _originTransformations[originId];
        bytes32 inputHash;
        if (transforms.length > 0) {
            inputHash = transformations[transforms[transforms.length - 1]].outputHash;
        } else {
            inputHash = origin.dataHash;
        }

        transformations[transformId] = Transformation({
            id: transformId,
            originId: originId,
            transformer: msg.sender,
            transformType: transformType,
            inputHash: inputHash,
            outputHash: outputHash,
            timestamp: block.timestamp
        });

        transforms.push(transformId);
        dataHashToTransformId[outputHash] = transformId;

        emit TransformationAdded(transformId, originId, transformType, outputHash);
    }

    /// @notice Verify the provenance chain for a data hash
    /// @param dataHash The data hash to verify
    /// @return originId The origin ID
    /// @return transformIds The transformation chain
    /// @return certified Whether the origin is certified
    function verifyProvenance(bytes32 dataHash) external view returns (
        uint256 originId,
        uint256[] memory transformIds,
        bool certified
    ) {
        // Check if it's an origin hash
        originId = dataHashToOriginId[dataHash];
        if (originId != 0) {
            transformIds = _originTransformations[originId];
            certified = origins[originId].certified;
            return (originId, transformIds, certified);
        }

        // Check if it's a transformation output
        uint256 transformId = dataHashToTransformId[dataHash];
        if (transformId != 0) {
            Transformation storage t = transformations[transformId];
            originId = t.originId;
            transformIds = _originTransformations[originId];
            certified = origins[originId].certified;
            return (originId, transformIds, certified);
        }

        revert DataHashNotFound();
    }

    /// @notice Certify a data origin (auditors only)
    /// @param dataHash The data hash to certify
    function certifyData(bytes32 dataHash) external whenNotPaused {
        if (!authorizedAuditors[msg.sender]) revert NotAuthorizedAuditor();

        uint256 originId = dataHashToOriginId[dataHash];
        if (originId == 0) revert DataHashNotFound();

        Origin storage origin = origins[originId];
        if (origin.certified) revert AlreadyCertified();

        origin.certified = true;
        origin.certifiedBy = msg.sender;
        origin.certifiedAt = block.timestamp;
        auditorCertCount[msg.sender]++;

        emit DataCertified(originId, msg.sender, block.timestamp);
    }

    /// @notice Get transformation chain for an origin
    /// @param originId The origin ID
    /// @return Array of transformation IDs
    function getTransformationChain(uint256 originId) external view returns (uint256[] memory) {
        if (origins[originId].registrar == address(0)) revert OriginNotFound();
        return _originTransformations[originId];
    }

    /// @notice Get total registered origins
    function totalOrigins() external view returns (uint256) {
        return nextOriginId;
    }

    /// @notice Get total transformations
    function totalTransformations() external view returns (uint256) {
        return nextTransformId;
    }
}
