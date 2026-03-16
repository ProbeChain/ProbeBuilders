// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ModelServing
 * @author ProbeChain
 * @notice Decentralized model serving platform on ProbeChain Rydberg Testnet
 * @dev Host models with staking, call models with payment, submit responses, dispute results
 */
contract ModelServing {
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
    enum CallStatus { Pending, Responded, Disputed, Resolved }

    struct HostedModel {
        address host;
        bytes32 modelHash;
        string endpoint;
        uint256 pricePerCall;
        uint256 stakeAmount;
        bool active;
        uint256 totalCalls;
        uint256 successfulCalls;
        uint256 hostedAt;
    }

    struct ModelCall {
        uint256 modelId;
        address caller;
        bytes32 inputHash;
        bytes32 outputHash;
        uint256 payment;
        CallStatus status;
        uint256 createdAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => HostedModel) public models;
    mapping(uint256 => ModelCall) public calls;
    mapping(address => uint256) public pendingWithdrawals;
    uint256 public nextModelId;
    uint256 public nextCallId;
    uint256 public minStake = 0.1 ether;
    uint256 public platformFee = 200; // 2%
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public responseTimeout = 30 minutes;

    // ─── Events ─────────────────────────────────────────────────────────
    event ModelHosted(uint256 indexed modelId, address indexed host, bytes32 modelHash, uint256 stakeAmount);
    event ModelCalled(uint256 indexed callId, uint256 indexed modelId, address indexed caller, bytes32 inputHash);
    event ResponseSubmitted(uint256 indexed callId, bytes32 outputHash);
    event ResponseDisputed(uint256 indexed callId, address indexed disputer);
    event DisputeResolved(uint256 indexed callId, bool callerWins);
    event ModelDeactivated(uint256 indexed modelId, uint256 stakeReturned);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Host a model with stake
     * @param modelHash Hash of the model weights
     * @param endpoint Off-chain serving endpoint
     * @param pricePerCall Price per inference call in wei
     */
    function hostModel(
        bytes32 modelHash,
        string calldata endpoint,
        uint256 pricePerCall
    ) external payable whenNotPaused returns (uint256) {
        require(modelHash != bytes32(0), "Empty model hash");
        require(bytes(endpoint).length > 0, "Empty endpoint");
        require(pricePerCall > 0, "Zero price");
        require(msg.value >= minStake, "Below min stake");

        uint256 id = nextModelId++;
        models[id] = HostedModel({
            host: msg.sender,
            modelHash: modelHash,
            endpoint: endpoint,
            pricePerCall: pricePerCall,
            stakeAmount: msg.value,
            active: true,
            totalCalls: 0,
            successfulCalls: 0,
            hostedAt: block.timestamp
        });

        emit ModelHosted(id, msg.sender, modelHash, msg.value);
        return id;
    }

    /**
     * @notice Call a hosted model
     * @param modelId The model to call
     * @param inputHash Hash of input data
     */
    function callModel(
        uint256 modelId,
        bytes32 inputHash
    ) external payable whenNotPaused returns (uint256) {
        HostedModel storage m = models[modelId];
        require(m.active, "Model not active");
        require(inputHash != bytes32(0), "Empty input");
        require(msg.value >= m.pricePerCall, "Insufficient payment");

        m.totalCalls++;

        uint256 id = nextCallId++;
        calls[id] = ModelCall({
            modelId: modelId,
            caller: msg.sender,
            inputHash: inputHash,
            outputHash: bytes32(0),
            payment: m.pricePerCall,
            status: CallStatus.Pending,
            createdAt: block.timestamp
        });

        if (msg.value > m.pricePerCall) {
            payable(msg.sender).transfer(msg.value - m.pricePerCall);
        }

        emit ModelCalled(id, modelId, msg.sender, inputHash);
        return id;
    }

    /**
     * @notice Submit response for a model call
     * @param callId The call to respond to
     * @param outputHash Hash of the output data
     */
    function submitResponse(uint256 callId, bytes32 outputHash) external whenNotPaused nonReentrant {
        ModelCall storage c = calls[callId];
        require(c.status == CallStatus.Pending, "Not pending");
        HostedModel storage m = models[c.modelId];
        require(msg.sender == m.host, "Not host");

        c.outputHash = outputHash;
        c.status = CallStatus.Responded;
        m.successfulCalls++;

        uint256 fee = (c.payment * platformFee) / FEE_DENOMINATOR;
        pendingWithdrawals[_owner] += fee;
        pendingWithdrawals[m.host] += c.payment - fee;

        emit ResponseSubmitted(callId, outputHash);
    }

    /**
     * @notice Dispute a response
     * @param callId The call to dispute
     */
    function disputeResponse(uint256 callId) external whenNotPaused {
        ModelCall storage c = calls[callId];
        require(c.status == CallStatus.Responded, "Not responded");
        require(msg.sender == c.caller, "Not caller");

        c.status = CallStatus.Disputed;
        emit ResponseDisputed(callId, msg.sender);
    }

    /**
     * @notice Resolve a dispute (owner only)
     * @param callId The disputed call
     * @param callerWins True if caller wins dispute
     */
    function resolveDispute(uint256 callId, bool callerWins) external onlyOwner nonReentrant {
        ModelCall storage c = calls[callId];
        require(c.status == CallStatus.Disputed, "Not disputed");

        c.status = CallStatus.Resolved;
        HostedModel storage m = models[c.modelId];

        if (callerWins) {
            // Refund caller, slash part of host stake
            pendingWithdrawals[c.caller] += c.payment;
            uint256 slash = c.payment;
            if (slash > m.stakeAmount) slash = m.stakeAmount;
            m.stakeAmount -= slash;
            pendingWithdrawals[c.caller] += slash;
        }

        emit DisputeResolved(callId, callerWins);
    }

    /**
     * @notice Claim refund for timed-out call
     * @param callId The timed-out call
     */
    function claimTimeout(uint256 callId) external nonReentrant {
        ModelCall storage c = calls[callId];
        require(c.status == CallStatus.Pending, "Not pending");
        require(msg.sender == c.caller, "Not caller");
        require(block.timestamp > c.createdAt + responseTimeout, "Not timed out");

        c.status = CallStatus.Resolved;
        payable(msg.sender).transfer(c.payment);
    }

    /**
     * @notice Deactivate a model and return stake
     * @param modelId The model to deactivate
     */
    function deactivateModel(uint256 modelId) external nonReentrant {
        HostedModel storage m = models[modelId];
        require(msg.sender == m.host, "Not host");
        require(m.active, "Not active");

        m.active = false;
        uint256 stake = m.stakeAmount;
        m.stakeAmount = 0;

        if (stake > 0) {
            payable(msg.sender).transfer(stake);
        }

        emit ModelDeactivated(modelId, stake);
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
     * @notice Update minimum stake
     */
    function setMinStake(uint256 newMin) external onlyOwner {
        minStake = newMin;
    }
}
