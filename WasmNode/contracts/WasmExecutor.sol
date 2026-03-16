// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title WasmExecutor
 * @author ProbeChain
 * @notice Decentralized WASM compute network on ProbeChain Rydberg Testnet
 * @dev Register runtimes with capabilities, execute WASM modules, submit and verify outputs
 */
contract WasmExecutor {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() { require(msg.sender == _owner, "Not owner"); _; }
    event OwnershipTransferred(address indexed prev, address indexed next_);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _locked = 1;
    modifier nonReentrant() { require(_locked == 1, "Reentrant"); _locked = 2; _; _locked = 1; }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "Paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums & Structs ────────────────────────────────────────────────
    enum ExecStatus { Pending, Submitted, Verified, Failed, Expired }

    struct WasmRuntime {
        address operator;
        bytes32 wasmHash;
        string[] capabilities;
        uint256 stakeAmount;
        bool active;
        uint256 totalExecutions;
        uint256 successCount;
        uint256 registeredAt;
    }

    struct Execution {
        uint256 runtimeId;
        address requester;
        bytes32 inputHash;
        bytes32 outputHash;
        uint256 gasLimit;
        uint256 payment;
        ExecStatus status;
        uint256 createdAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => WasmRuntime) private _runtimes;
    mapping(uint256 => string[]) private _runtimeCapabilities;
    mapping(uint256 => Execution) public executions;
    mapping(address => uint256) public pendingWithdrawals;
    mapping(address => bool) public verifiers;
    uint256 public nextRuntimeId;
    uint256 public nextExecId;
    uint256 public minStake = 0.05 ether;
    uint256 public platformFee = 250; // 2.5%
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public executionTimeout = 15 minutes;

    // ─── Events ─────────────────────────────────────────────────────────
    event RuntimeRegistered(uint256 indexed runtimeId, address indexed operator, bytes32 wasmHash, uint256 stake);
    event ExecutionRequested(uint256 indexed execId, uint256 indexed runtimeId, address indexed requester, bytes32 inputHash);
    event OutputSubmitted(uint256 indexed execId, bytes32 outputHash);
    event ExecutionVerified(uint256 indexed execId, address indexed verifier);
    event ExecutionFailed(uint256 indexed execId, string reason);
    event RuntimeDeactivated(uint256 indexed runtimeId);
    event VerifierUpdated(address indexed verifier, bool status);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Admin ──────────────────────────────────────────────────────────
    function setVerifier(address verifier, bool status) external onlyOwner {
        verifiers[verifier] = status;
        emit VerifierUpdated(verifier, status);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register a WASM runtime
     * @param wasmHash Hash of the WASM binary
     * @param capabilities List of supported capabilities
     */
    function registerRuntime(
        bytes32 wasmHash,
        string[] calldata capabilities
    ) external payable whenNotPaused returns (uint256) {
        require(wasmHash != bytes32(0), "Empty WASM hash");
        require(capabilities.length > 0, "No capabilities");
        require(msg.value >= minStake, "Below min stake");

        uint256 id = nextRuntimeId++;

        _runtimeCapabilities[id] = capabilities;
        _runtimes[id] = WasmRuntime({
            operator: msg.sender,
            wasmHash: wasmHash,
            capabilities: capabilities,
            stakeAmount: msg.value,
            active: true,
            totalExecutions: 0,
            successCount: 0,
            registeredAt: block.timestamp
        });

        emit RuntimeRegistered(id, msg.sender, wasmHash, msg.value);
        return id;
    }

    /**
     * @notice Request WASM execution
     * @param runtimeId The runtime to use
     * @param inputHash Hash of the input data
     * @param gasLimit Gas limit for execution
     */
    function executeWasm(
        uint256 runtimeId,
        bytes32 inputHash,
        uint256 gasLimit
    ) external payable whenNotPaused returns (uint256) {
        WasmRuntime storage r = _runtimes[runtimeId];
        require(r.active, "Runtime not active");
        require(inputHash != bytes32(0), "Empty input");
        require(gasLimit > 0, "Zero gas limit");
        require(msg.value > 0, "Zero payment");

        r.totalExecutions++;

        uint256 id = nextExecId++;
        executions[id] = Execution({
            runtimeId: runtimeId,
            requester: msg.sender,
            inputHash: inputHash,
            outputHash: bytes32(0),
            gasLimit: gasLimit,
            payment: msg.value,
            status: ExecStatus.Pending,
            createdAt: block.timestamp
        });

        emit ExecutionRequested(id, runtimeId, msg.sender, inputHash);
        return id;
    }

    /**
     * @notice Submit execution output
     * @param execId The execution to respond to
     * @param outputHash Hash of the output
     */
    function submitOutput(uint256 execId, bytes32 outputHash) external whenNotPaused {
        Execution storage e = executions[execId];
        require(e.status == ExecStatus.Pending, "Not pending");
        WasmRuntime storage r = _runtimes[e.runtimeId];
        require(msg.sender == r.operator, "Not operator");

        e.outputHash = outputHash;
        e.status = ExecStatus.Submitted;
        emit OutputSubmitted(execId, outputHash);
    }

    /**
     * @notice Verify an execution (verifier or requester)
     * @param execId The execution to verify
     */
    function verifyExecution(uint256 execId) external whenNotPaused nonReentrant {
        Execution storage e = executions[execId];
        require(e.status == ExecStatus.Submitted, "Not submitted");
        require(verifiers[msg.sender] || msg.sender == e.requester, "Not authorized");

        e.status = ExecStatus.Verified;
        WasmRuntime storage r = _runtimes[e.runtimeId];
        r.successCount++;

        uint256 fee = (e.payment * platformFee) / FEE_DENOMINATOR;
        pendingWithdrawals[_owner] += fee;
        pendingWithdrawals[r.operator] += e.payment - fee;

        emit ExecutionVerified(execId, msg.sender);
    }

    /**
     * @notice Mark execution as failed
     * @param execId The execution that failed
     * @param reason Failure reason
     */
    function markFailed(uint256 execId, string calldata reason) external whenNotPaused nonReentrant {
        Execution storage e = executions[execId];
        require(e.status == ExecStatus.Pending || e.status == ExecStatus.Submitted, "Invalid status");
        WasmRuntime storage r = _runtimes[e.runtimeId];
        require(msg.sender == r.operator || verifiers[msg.sender] || msg.sender == _owner, "Not authorized");

        e.status = ExecStatus.Failed;
        pendingWithdrawals[e.requester] += e.payment;
        emit ExecutionFailed(execId, reason);
    }

    /**
     * @notice Claim refund for expired execution
     * @param execId The expired execution
     */
    function claimExpired(uint256 execId) external nonReentrant {
        Execution storage e = executions[execId];
        require(e.status == ExecStatus.Pending, "Not pending");
        require(msg.sender == e.requester, "Not requester");
        require(block.timestamp > e.createdAt + executionTimeout, "Not expired");

        e.status = ExecStatus.Expired;
        payable(msg.sender).transfer(e.payment);
    }

    /**
     * @notice Deactivate runtime and return stake
     * @param runtimeId The runtime to deactivate
     */
    function deactivateRuntime(uint256 runtimeId) external nonReentrant {
        WasmRuntime storage r = _runtimes[runtimeId];
        require(msg.sender == r.operator, "Not operator");
        require(r.active, "Not active");

        r.active = false;
        uint256 stake = r.stakeAmount;
        r.stakeAmount = 0;
        if (stake > 0) payable(msg.sender).transfer(stake);
        emit RuntimeDeactivated(runtimeId);
    }

    /**
     * @notice Withdraw pending balance
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Get runtime capabilities
     */
    function getRuntimeCapabilities(uint256 runtimeId) external view returns (string[] memory) {
        return _runtimeCapabilities[runtimeId];
    }

    /**
     * @notice Get runtime info
     */
    function getRuntimeInfo(uint256 runtimeId) external view returns (
        address operator, bytes32 wasmHash, uint256 stakeAmount,
        bool active, uint256 totalExecutions, uint256 successCount
    ) {
        WasmRuntime storage r = _runtimes[runtimeId];
        return (r.operator, r.wasmHash, r.stakeAmount, r.active, r.totalExecutions, r.successCount);
    }
}
