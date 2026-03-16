// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title InferenceNetwork
 * @author ProbeChain
 * @notice Decentralized AI inference network on ProbeChain Rydberg Testnet
 * @dev Register models, request inference, submit results with proofs, verify and pay
 */
contract InferenceNetwork {
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
    enum RequestStatus { Pending, Fulfilled, Disputed, Resolved }

    struct Model {
        address provider;
        bytes32 modelHash;
        string inputSpec;
        string outputSpec;
        uint256 pricePerQuery;
        bool active;
        uint256 totalQueries;
        uint256 registeredAt;
    }

    struct InferenceRequest {
        uint256 modelId;
        address requester;
        bytes32 inputHash;
        bytes32 outputHash;
        bytes32 proofHash;
        uint256 payment;
        RequestStatus status;
        address fulfiller;
        uint256 createdAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => Model) public models;
    mapping(uint256 => InferenceRequest) public requests;
    mapping(address => uint256) public pendingWithdrawals;
    uint256 public nextModelId;
    uint256 public nextRequestId;
    uint256 public platformFee = 250; // 2.5%
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public disputeTimeout = 1 hours;

    // ─── Events ─────────────────────────────────────────────────────────
    event ModelRegistered(uint256 indexed modelId, address indexed provider, bytes32 modelHash);
    event InferenceRequested(uint256 indexed requestId, uint256 indexed modelId, address indexed requester, bytes32 inputHash);
    event ResultSubmitted(uint256 indexed requestId, bytes32 outputHash, bytes32 proofHash);
    event PaymentReleased(uint256 indexed requestId, address indexed provider, uint256 amount);
    event ResultDisputed(uint256 indexed requestId, address indexed disputer);
    event DisputeResolved(uint256 indexed requestId, bool inFavorOfRequester);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register an AI model for inference
     * @param modelHash Hash of the model weights
     * @param inputSpec Description of expected input format
     * @param outputSpec Description of output format
     * @param pricePerQuery Price per inference query in wei
     */
    function registerModel(
        bytes32 modelHash,
        string calldata inputSpec,
        string calldata outputSpec,
        uint256 pricePerQuery
    ) external whenNotPaused returns (uint256) {
        require(modelHash != bytes32(0), "Empty model hash");
        require(bytes(inputSpec).length > 0, "Empty input spec");
        require(bytes(outputSpec).length > 0, "Empty output spec");
        require(pricePerQuery > 0, "Zero price");

        uint256 id = nextModelId++;
        models[id] = Model({
            provider: msg.sender,
            modelHash: modelHash,
            inputSpec: inputSpec,
            outputSpec: outputSpec,
            pricePerQuery: pricePerQuery,
            active: true,
            totalQueries: 0,
            registeredAt: block.timestamp
        });

        emit ModelRegistered(id, msg.sender, modelHash);
        return id;
    }

    /**
     * @notice Request an inference
     * @param modelId The model to query
     * @param inputHash Hash of the input data
     */
    function requestInference(
        uint256 modelId,
        bytes32 inputHash
    ) external payable whenNotPaused returns (uint256) {
        Model storage m = models[modelId];
        require(m.active, "Model not active");
        require(inputHash != bytes32(0), "Empty input");
        require(msg.value >= m.pricePerQuery, "Insufficient payment");

        uint256 id = nextRequestId++;
        requests[id] = InferenceRequest({
            modelId: modelId,
            requester: msg.sender,
            inputHash: inputHash,
            outputHash: bytes32(0),
            proofHash: bytes32(0),
            payment: m.pricePerQuery,
            status: RequestStatus.Pending,
            fulfiller: address(0),
            createdAt: block.timestamp
        });

        if (msg.value > m.pricePerQuery) {
            payable(msg.sender).transfer(msg.value - m.pricePerQuery);
        }

        emit InferenceRequested(id, modelId, msg.sender, inputHash);
        return id;
    }

    /**
     * @notice Submit inference result with proof
     * @param requestId The request to fulfill
     * @param outputHash Hash of the output data
     * @param proofHash Hash of the computation proof
     */
    function submitResult(
        uint256 requestId,
        bytes32 outputHash,
        bytes32 proofHash
    ) external whenNotPaused {
        InferenceRequest storage r = requests[requestId];
        require(r.status == RequestStatus.Pending, "Not pending");
        Model storage m = models[r.modelId];
        require(msg.sender == m.provider, "Not model provider");

        r.outputHash = outputHash;
        r.proofHash = proofHash;
        r.fulfiller = msg.sender;
        r.status = RequestStatus.Fulfilled;
        m.totalQueries++;

        emit ResultSubmitted(requestId, outputHash, proofHash);
    }

    /**
     * @notice Verify and release payment (auto after timeout or by requester)
     * @param requestId The fulfilled request
     */
    function verifyAndPay(uint256 requestId) external whenNotPaused nonReentrant {
        InferenceRequest storage r = requests[requestId];
        require(r.status == RequestStatus.Fulfilled, "Not fulfilled");
        require(
            msg.sender == r.requester ||
            block.timestamp > r.createdAt + disputeTimeout,
            "Wait for timeout"
        );

        uint256 fee = (r.payment * platformFee) / FEE_DENOMINATOR;
        pendingWithdrawals[_owner] += fee;
        pendingWithdrawals[r.fulfiller] += r.payment - fee;

        r.status = RequestStatus.Resolved;
        emit PaymentReleased(requestId, r.fulfiller, r.payment - fee);
    }

    /**
     * @notice Dispute a result (requester only, before timeout)
     * @param requestId The request to dispute
     */
    function disputeResult(uint256 requestId) external whenNotPaused {
        InferenceRequest storage r = requests[requestId];
        require(r.status == RequestStatus.Fulfilled, "Not fulfilled");
        require(msg.sender == r.requester, "Not requester");
        require(block.timestamp <= r.createdAt + disputeTimeout, "Timeout passed");

        r.status = RequestStatus.Disputed;
        emit ResultDisputed(requestId, msg.sender);
    }

    /**
     * @notice Resolve a dispute (owner only)
     * @param requestId The disputed request
     * @param inFavorOfRequester True to refund requester
     */
    function resolveDispute(uint256 requestId, bool inFavorOfRequester) external onlyOwner nonReentrant {
        InferenceRequest storage r = requests[requestId];
        require(r.status == RequestStatus.Disputed, "Not disputed");

        r.status = RequestStatus.Resolved;
        if (inFavorOfRequester) {
            pendingWithdrawals[r.requester] += r.payment;
        } else {
            uint256 fee = (r.payment * platformFee) / FEE_DENOMINATOR;
            pendingWithdrawals[_owner] += fee;
            pendingWithdrawals[r.fulfiller] += r.payment - fee;
        }

        emit DisputeResolved(requestId, inFavorOfRequester);
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
     * @notice Deactivate a model
     */
    function deactivateModel(uint256 modelId) external {
        require(msg.sender == models[modelId].provider || msg.sender == _owner, "Not authorized");
        models[modelId].active = false;
    }
}
