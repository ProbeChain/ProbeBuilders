// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ZKVerifier
 * @author ProbeChain
 * @notice ZK proof verification registry — register circuits, submit and verify proofs
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

contract ZKVerifier is Ownable, ReentrancyGuard, Pausable {
    // --- Types ---
    enum VerificationStatus { Pending, Verified, Failed, Disputed }

    struct Circuit {
        uint256 id;
        address registrar;
        string name;
        address verifierAddress;
        string description;
        uint256 proofCount;
        bool active;
    }

    struct ProofSubmission {
        uint256 id;
        uint256 circuitId;
        address submitter;
        bytes32 proofHash;
        bytes32 publicInputsHash;
        VerificationStatus status;
        uint256 submittedAt;
        uint256 verifiedAt;
        address verifiedBy;
    }

    // --- State ---
    uint256 public nextCircuitId;
    uint256 public nextSubmissionId;
    uint256 public constant VERIFIER_STAKE = 0.05 ether;

    mapping(uint256 => Circuit) public circuits;
    mapping(uint256 => ProofSubmission) public submissions;
    mapping(address => uint256) public verifierStakes;
    mapping(address => bool) public authorizedVerifiers;
    mapping(uint256 => uint256[]) private _circuitSubmissions;

    // --- Events ---
    event CircuitRegistered(uint256 indexed circuitId, address indexed registrar, string name, address verifierAddress);
    event ProofSubmitted(uint256 indexed submissionId, uint256 indexed circuitId, address indexed submitter, bytes32 proofHash);
    event ProofVerified(uint256 indexed submissionId, VerificationStatus status, address verifiedBy);
    event VerifierAuthorized(address indexed verifier);
    event VerifierRevoked(address indexed verifier);
    event CircuitDeactivated(uint256 indexed circuitId);
    event VerifierStaked(address indexed verifier, uint256 amount);

    // --- Errors ---
    error CircuitNotFound();
    error CircuitNotActive();
    error SubmissionNotFound();
    error NotAuthorizedVerifier();
    error AlreadyVerified();
    error NotCircuitRegistrar();
    error InsufficientVerifierStake();
    error InvalidProof();

    // --- Verifier Management ---

    /// @notice Stake to become a verifier
    function stakeAsVerifier() external payable whenNotPaused {
        if (msg.value < VERIFIER_STAKE) revert InsufficientVerifierStake();
        verifierStakes[msg.sender] += msg.value;
        authorizedVerifiers[msg.sender] = true;
        emit VerifierStaked(msg.sender, msg.value);
        emit VerifierAuthorized(msg.sender);
    }

    /// @notice Owner can authorize a verifier directly
    function authorizeVerifier(address verifier) external onlyOwner {
        authorizedVerifiers[verifier] = true;
        emit VerifierAuthorized(verifier);
    }

    /// @notice Owner can revoke a verifier
    function revokeVerifier(address verifier) external onlyOwner {
        authorizedVerifiers[verifier] = false;
        emit VerifierRevoked(verifier);
    }

    // --- Circuit Management ---

    /// @notice Register a new ZK circuit
    /// @param name Human-readable circuit name
    /// @param verifierAddress On-chain verifier contract address
    /// @param description Description of the circuit's purpose
    /// @return circuitId The ID of the registered circuit
    function registerCircuit(
        string calldata name,
        address verifierAddress,
        string calldata description
    ) external whenNotPaused returns (uint256 circuitId) {
        circuitId = nextCircuitId++;
        circuits[circuitId] = Circuit({
            id: circuitId,
            registrar: msg.sender,
            name: name,
            verifierAddress: verifierAddress,
            description: description,
            proofCount: 0,
            active: true
        });
        emit CircuitRegistered(circuitId, msg.sender, name, verifierAddress);
    }

    /// @notice Submit a proof for a registered circuit
    /// @param circuitId The circuit to submit proof for
    /// @param proof The proof data hash
    /// @param publicInputs The public inputs hash
    /// @return submissionId The ID of the proof submission
    function submitProof(
        uint256 circuitId,
        bytes32 proof,
        bytes32 publicInputs
    ) external whenNotPaused returns (uint256 submissionId) {
        Circuit storage circuit = circuits[circuitId];
        if (circuit.registrar == address(0)) revert CircuitNotFound();
        if (!circuit.active) revert CircuitNotActive();
        if (proof == bytes32(0)) revert InvalidProof();

        submissionId = nextSubmissionId++;
        submissions[submissionId] = ProofSubmission({
            id: submissionId,
            circuitId: circuitId,
            submitter: msg.sender,
            proofHash: proof,
            publicInputsHash: publicInputs,
            status: VerificationStatus.Pending,
            submittedAt: block.timestamp,
            verifiedAt: 0,
            verifiedBy: address(0)
        });

        circuit.proofCount++;
        _circuitSubmissions[circuitId].push(submissionId);
        emit ProofSubmitted(submissionId, circuitId, msg.sender, proof);
    }

    /// @notice Verify a submitted proof
    /// @param submissionId The submission to verify
    /// @param valid Whether the proof is valid
    function verifyProof(uint256 submissionId, bool valid) external whenNotPaused {
        if (!authorizedVerifiers[msg.sender]) revert NotAuthorizedVerifier();
        ProofSubmission storage sub = submissions[submissionId];
        if (sub.submitter == address(0)) revert SubmissionNotFound();
        if (sub.status != VerificationStatus.Pending) revert AlreadyVerified();

        sub.status = valid ? VerificationStatus.Verified : VerificationStatus.Failed;
        sub.verifiedAt = block.timestamp;
        sub.verifiedBy = msg.sender;

        emit ProofVerified(submissionId, sub.status, msg.sender);
    }

    /// @notice Get verification history for a circuit
    /// @param circuitId The circuit to query
    /// @return submissionIds Array of submission IDs
    function getVerificationHistory(uint256 circuitId) external view returns (uint256[] memory) {
        if (circuits[circuitId].registrar == address(0)) revert CircuitNotFound();
        return _circuitSubmissions[circuitId];
    }

    /// @notice Deactivate a circuit
    /// @param circuitId The circuit to deactivate
    function deactivateCircuit(uint256 circuitId) external {
        Circuit storage circuit = circuits[circuitId];
        if (circuit.registrar != msg.sender && msg.sender != owner()) revert NotCircuitRegistrar();
        circuit.active = false;
        emit CircuitDeactivated(circuitId);
    }

    /// @notice Get submission details
    /// @param submissionId The submission ID
    /// @return The proof submission struct
    function getSubmission(uint256 submissionId) external view returns (ProofSubmission memory) {
        if (submissions[submissionId].submitter == address(0)) revert SubmissionNotFound();
        return submissions[submissionId];
    }
}
