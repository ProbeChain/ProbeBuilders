// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AutoScaler
 * @author ProbeChain
 * @notice Auto-scaling inference endpoint manager on ProbeChain Rydberg Testnet
 * @dev Register endpoints, request scaling, process inference requests, submit responses
 */
contract AutoScaler {
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
    enum RequestStatus { Pending, Fulfilled, Expired }

    struct Endpoint {
        address provider;
        bytes32 modelId;
        uint256 maxRPS;
        uint256 currentRPS;
        uint256 pricePerRequest;
        bool active;
        uint256 totalRequests;
        uint256 registeredAt;
    }

    struct ScaleEvent {
        uint256 endpointId;
        uint256 targetRPS;
        uint256 timestamp;
        address requester;
    }

    struct InferRequest {
        uint256 endpointId;
        address requester;
        bytes32 inputHash;
        bytes32 outputHash;
        uint256 payment;
        RequestStatus status;
        uint256 createdAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => Endpoint) public endpoints;
    mapping(uint256 => InferRequest) public inferRequests;
    mapping(address => uint256) public pendingWithdrawals;
    ScaleEvent[] public scaleHistory;
    uint256 public nextEndpointId;
    uint256 public nextRequestId;
    uint256 public platformFee = 200; // 2%
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public requestTimeout = 5 minutes;

    // ─── Events ─────────────────────────────────────────────────────────
    event EndpointRegistered(uint256 indexed endpointId, address indexed provider, bytes32 modelId, uint256 maxRPS);
    event ScaleRequested(uint256 indexed endpointId, uint256 targetRPS, address indexed requester);
    event RequestProcessed(uint256 indexed requestId, uint256 indexed endpointId, address indexed requester);
    event ResponseSubmitted(uint256 indexed requestId, bytes32 outputHash);
    event RequestExpired(uint256 indexed requestId);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register an inference endpoint
     * @param modelId Model identifier hash
     * @param maxRPS Maximum requests per second capacity
     * @param pricePerRequest Price per request in wei
     */
    function registerEndpoint(
        bytes32 modelId,
        uint256 maxRPS,
        uint256 pricePerRequest
    ) external whenNotPaused returns (uint256) {
        require(modelId != bytes32(0), "Empty model ID");
        require(maxRPS > 0, "Zero RPS");
        require(pricePerRequest > 0, "Zero price");

        uint256 id = nextEndpointId++;
        endpoints[id] = Endpoint({
            provider: msg.sender,
            modelId: modelId,
            maxRPS: maxRPS,
            currentRPS: 0,
            pricePerRequest: pricePerRequest,
            active: true,
            totalRequests: 0,
            registeredAt: block.timestamp
        });

        emit EndpointRegistered(id, msg.sender, modelId, maxRPS);
        return id;
    }

    /**
     * @notice Request scaling for an endpoint
     * @param endpointId The endpoint to scale
     * @param targetRPS Target requests per second
     */
    function requestScale(uint256 endpointId, uint256 targetRPS) external whenNotPaused {
        Endpoint storage e = endpoints[endpointId];
        require(e.active, "Endpoint not active");
        require(msg.sender == e.provider || msg.sender == _owner, "Not authorized");
        require(targetRPS <= e.maxRPS, "Exceeds max RPS");

        e.currentRPS = targetRPS;
        scaleHistory.push(ScaleEvent({
            endpointId: endpointId,
            targetRPS: targetRPS,
            timestamp: block.timestamp,
            requester: msg.sender
        }));

        emit ScaleRequested(endpointId, targetRPS, msg.sender);
    }

    /**
     * @notice Submit an inference request
     * @param endpointId The endpoint to query
     * @param inputHash Hash of input data
     */
    function processRequest(
        uint256 endpointId,
        bytes32 inputHash
    ) external payable whenNotPaused returns (uint256) {
        Endpoint storage e = endpoints[endpointId];
        require(e.active, "Endpoint not active");
        require(inputHash != bytes32(0), "Empty input");
        require(msg.value >= e.pricePerRequest, "Insufficient payment");

        uint256 id = nextRequestId++;
        inferRequests[id] = InferRequest({
            endpointId: endpointId,
            requester: msg.sender,
            inputHash: inputHash,
            outputHash: bytes32(0),
            payment: e.pricePerRequest,
            status: RequestStatus.Pending,
            createdAt: block.timestamp
        });

        e.totalRequests++;

        if (msg.value > e.pricePerRequest) {
            payable(msg.sender).transfer(msg.value - e.pricePerRequest);
        }

        emit RequestProcessed(id, endpointId, msg.sender);
        return id;
    }

    /**
     * @notice Submit a response to an inference request
     * @param requestId The request to respond to
     * @param outputHash Hash of the output data
     */
    function submitResponse(uint256 requestId, bytes32 outputHash) external whenNotPaused nonReentrant {
        InferRequest storage r = inferRequests[requestId];
        require(r.status == RequestStatus.Pending, "Not pending");
        Endpoint storage e = endpoints[r.endpointId];
        require(msg.sender == e.provider, "Not endpoint provider");

        r.outputHash = outputHash;
        r.status = RequestStatus.Fulfilled;

        uint256 fee = (r.payment * platformFee) / FEE_DENOMINATOR;
        pendingWithdrawals[_owner] += fee;
        pendingWithdrawals[e.provider] += r.payment - fee;

        emit ResponseSubmitted(requestId, outputHash);
    }

    /**
     * @notice Reclaim payment for expired requests
     * @param requestId The expired request
     */
    function claimExpired(uint256 requestId) external nonReentrant {
        InferRequest storage r = inferRequests[requestId];
        require(r.status == RequestStatus.Pending, "Not pending");
        require(block.timestamp > r.createdAt + requestTimeout, "Not expired");
        require(msg.sender == r.requester, "Not requester");

        r.status = RequestStatus.Expired;
        payable(msg.sender).transfer(r.payment);
        emit RequestExpired(requestId);
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
     * @notice Deactivate an endpoint
     */
    function deactivateEndpoint(uint256 endpointId) external {
        require(msg.sender == endpoints[endpointId].provider || msg.sender == _owner, "Not authorized");
        endpoints[endpointId].active = false;
    }

    /**
     * @notice Get scale history length
     */
    function getScaleHistoryLength() external view returns (uint256) {
        return scaleHistory.length;
    }
}
