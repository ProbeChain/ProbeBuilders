// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title NotaryService
 * @author ProbeBuilders
 * @notice Document notarization service for ProbeChain Rydberg Testnet.
 *         Provides timestamp proof with multi-party witness support.
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

contract NotaryService is Ownable, ReentrancyGuard, Pausable {

    /* ── Structs ── */

    /// @notice A notarized document record
    struct Document {
        bytes32  documentHash;
        address  notarizer;
        string   metadata;       // title, description, IPFS URI, etc.
        uint256  timestamp;
        uint256  blockNumber;
        bool     revoked;
        address[] witnesses;     // multi-party witnesses
    }

    /// @notice Witness attestation
    struct Attestation {
        address witness;
        uint256 timestamp;
        string  comment;
    }

    /* ── State ── */

    /// @notice documentHash => Document
    mapping(bytes32 => Document) private _documents;
    /// @notice documentHash => Attestation[]
    mapping(bytes32 => Attestation[]) private _attestations;
    /// @notice Track all document hashes for enumeration
    bytes32[] private _allHashes;
    /// @notice notarizer => documentHash[]
    mapping(address => bytes32[]) private _userDocuments;

    /// @notice Total notarized documents
    uint256 public totalDocuments;
    /// @notice Total attestations across all documents
    uint256 public totalAttestations;
    /// @notice Fee for notarization (can be 0)
    uint256 public notarizationFee;

    /* ── Events ── */

    /// @notice Emitted when a document is notarized
    event DocumentNotarized(bytes32 indexed documentHash, address indexed notarizer, string metadata, uint256 timestamp);
    /// @notice Emitted when a witness attests to a document
    event WitnessAttested(bytes32 indexed documentHash, address indexed witness, string comment);
    /// @notice Emitted when a notarization is revoked
    event NotarizationRevoked(bytes32 indexed documentHash, address indexed revokedBy);
    /// @notice Emitted when fee is updated
    event FeeUpdated(uint256 oldFee, uint256 newFee);

    /* ── Errors ── */

    error AlreadyNotarized();
    error NotNotarized();
    error NotNotarizer();
    error AlreadyRevoked();
    error AlreadyWitnessed();
    error InsufficientFee();

    /* ── Constructor ── */

    constructor() Ownable() {}

    /* ── Admin ── */

    /// @notice Set notarization fee
    function setFee(uint256 newFee) external onlyOwner {
        emit FeeUpdated(notarizationFee, newFee);
        notarizationFee = newFee;
    }

    /// @notice Withdraw collected fees
    function withdrawFees(address to) external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "no fees");
        (bool ok, ) = to.call{value: bal}("");
        require(ok, "transfer failed");
    }

    /* ── Core functions ── */

    /**
     * @notice Notarize a document by its hash
     * @param documentHash keccak256 hash of the document
     * @param metadata Human-readable metadata (title, IPFS URI, etc.)
     */
    function notarize(
        bytes32 documentHash,
        string calldata metadata
    ) external payable whenNotPaused {
        require(documentHash != bytes32(0), "zero hash");
        if (_documents[documentHash].timestamp != 0) revert AlreadyNotarized();
        if (msg.value < notarizationFee) revert InsufficientFee();

        address[] memory emptyWitnesses;

        _documents[documentHash] = Document({
            documentHash: documentHash,
            notarizer: msg.sender,
            metadata: metadata,
            timestamp: block.timestamp,
            blockNumber: block.number,
            revoked: false,
            witnesses: emptyWitnesses
        });

        _allHashes.push(documentHash);
        _userDocuments[msg.sender].push(documentHash);
        totalDocuments++;

        // Refund excess fee
        if (msg.value > notarizationFee) {
            (bool ok, ) = msg.sender.call{value: msg.value - notarizationFee}("");
            require(ok, "refund failed");
        }

        emit DocumentNotarized(documentHash, msg.sender, metadata, block.timestamp);
    }

    /**
     * @notice Add a witness attestation to a notarized document
     * @param documentHash The document to witness
     * @param comment Optional comment from the witness
     */
    function addWitness(
        bytes32 documentHash,
        string calldata comment
    ) external whenNotPaused {
        Document storage doc = _documents[documentHash];
        if (doc.timestamp == 0) revert NotNotarized();
        require(!doc.revoked, "revoked");

        // Prevent duplicate witness
        for (uint256 i = 0; i < doc.witnesses.length; i++) {
            if (doc.witnesses[i] == msg.sender) revert AlreadyWitnessed();
        }

        doc.witnesses.push(msg.sender);

        _attestations[documentHash].push(Attestation({
            witness: msg.sender,
            timestamp: block.timestamp,
            comment: comment
        }));

        totalAttestations++;

        emit WitnessAttested(documentHash, msg.sender, comment);
    }

    /**
     * @notice Verify a document's notarization
     * @param documentHash The hash to verify
     * @return timestamp The notarization timestamp (0 if not found)
     * @return notarizer The address that notarized it
     * @return isValid True if notarized and not revoked
     */
    function verify(bytes32 documentHash) external view returns (
        uint256 timestamp,
        address notarizer,
        bool isValid
    ) {
        Document storage doc = _documents[documentHash];
        timestamp = doc.timestamp;
        notarizer = doc.notarizer;
        isValid = doc.timestamp != 0 && !doc.revoked;
    }

    /**
     * @notice Revoke a notarization (only by original notarizer or owner)
     * @param documentHash The document to revoke
     */
    function revokeNotarization(bytes32 documentHash) external whenNotPaused {
        Document storage doc = _documents[documentHash];
        if (doc.timestamp == 0) revert NotNotarized();
        if (doc.notarizer != msg.sender && msg.sender != owner()) revert NotNotarizer();
        if (doc.revoked) revert AlreadyRevoked();

        doc.revoked = true;

        emit NotarizationRevoked(documentHash, msg.sender);
    }

    /* ── View helpers ── */

    /// @notice Get full document record
    function getDocument(bytes32 documentHash) external view returns (Document memory) {
        return _documents[documentHash];
    }

    /// @notice Get all attestations for a document
    function getAttestations(bytes32 documentHash) external view returns (Attestation[] memory) {
        return _attestations[documentHash];
    }

    /// @notice Get all document hashes notarized by a user
    function getUserDocuments(address user) external view returns (bytes32[] memory) {
        return _userDocuments[user];
    }

    /// @notice Get witness count for a document
    function getWitnessCount(bytes32 documentHash) external view returns (uint256) {
        return _documents[documentHash].witnesses.length;
    }

    /// @notice Check if an address has witnessed a document
    function hasWitnessed(bytes32 documentHash, address witness) external view returns (bool) {
        Document storage doc = _documents[documentHash];
        for (uint256 i = 0; i < doc.witnesses.length; i++) {
            if (doc.witnesses[i] == witness) return true;
        }
        return false;
    }

    /// @notice Allow contract to receive native currency (for fees)
    receive() external payable {}
}
