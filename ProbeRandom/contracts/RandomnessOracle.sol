// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title RandomnessOracle
 * @author ProbeChain Team
 * @notice Verifiable randomness oracle (VRF-like) for ProbeChain Rydberg Testnet
 * @dev Request-fulfill pattern: users request random numbers, oracles fulfill with proof
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender); _; }
    function owner() public view virtual returns (address) { return _owner; }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner); _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardReentrantCall();
        _status = _ENTERED; _; _status = _NOT_ENTERED;
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

/// @notice Callback interface for random number consumers
interface IRandomConsumer {
    function fulfillRandomness(uint256 requestId, uint256 randomValue) external;
}

contract RandomnessOracle is Ownable, ReentrancyGuard, Pausable {
    enum RequestStatus { Pending, Fulfilled, Cancelled }

    /// @notice Randomness request
    struct RandomRequest {
        uint256 id;
        address requester;
        address callbackContract;
        uint256 seed;
        uint256 randomValue;
        bytes32 proof;
        RequestStatus status;
        uint256 requestedAt;
        uint256 fulfilledAt;
        uint256 blockNumber;
    }

    mapping(uint256 => RandomRequest) private _requests;
    mapping(address => uint256[]) private _userRequests;
    mapping(address => bool) private _oracles;

    uint256 private _nextRequestId = 1;
    uint256 public requestFee = 0.001 ether;
    uint256 public requestTimeout = 100; // blocks
    uint256 public totalRequests;
    uint256 public totalFulfilled;

    /// @notice Emitted when randomness is requested
    event RandomnessRequested(uint256 indexed requestId, address indexed requester, address callbackContract, uint256 seed);
    /// @notice Emitted when randomness is fulfilled
    event RandomnessFulfilled(uint256 indexed requestId, uint256 randomValue, bytes32 proof, address indexed oracle);
    /// @notice Emitted when a request is cancelled
    event RequestCancelled(uint256 indexed requestId);
    /// @notice Emitted when an oracle is updated
    event OracleUpdated(address indexed oracle, bool active);

    error RequestNotFound(uint256 requestId);
    error RequestNotPending(uint256 requestId);
    error RequestNotTimedOut(uint256 requestId);
    error NotOracle(address caller);
    error NotRequester(address caller);
    error InsufficientFee(uint256 sent, uint256 required);
    error InvalidProof();
    error ZeroAddress();

    modifier onlyOracle() {
        if (!_oracles[msg.sender]) revert NotOracle(msg.sender);
        _;
    }

    /**
     * @notice Request a random number
     * @param seed User-provided seed for randomness
     * @param callbackContract Contract to receive the random value callback
     * @return requestId The request identifier
     */
    function requestRandom(
        uint256 seed,
        address callbackContract
    ) external payable whenNotPaused returns (uint256 requestId) {
        if (callbackContract == address(0)) revert ZeroAddress();
        if (msg.value < requestFee) revert InsufficientFee(msg.value, requestFee);

        requestId = _nextRequestId++;
        _requests[requestId] = RandomRequest({
            id: requestId,
            requester: msg.sender,
            callbackContract: callbackContract,
            seed: seed,
            randomValue: 0,
            proof: bytes32(0),
            status: RequestStatus.Pending,
            requestedAt: block.timestamp,
            fulfilledAt: 0,
            blockNumber: block.number
        });

        _userRequests[msg.sender].push(requestId);
        totalRequests++;

        emit RandomnessRequested(requestId, msg.sender, callbackContract, seed);
    }

    /**
     * @notice Fulfill a randomness request with proof (oracle only)
     * @param requestId The request to fulfill
     * @param randomValue The generated random number
     * @param proof The VRF proof data
     */
    function fulfillRandom(
        uint256 requestId,
        uint256 randomValue,
        bytes32 proof
    ) external nonReentrant whenNotPaused onlyOracle {
        RandomRequest storage req = _requests[requestId];
        if (req.id == 0) revert RequestNotFound(requestId);
        if (req.status != RequestStatus.Pending) revert RequestNotPending(requestId);
        if (proof == bytes32(0)) revert InvalidProof();

        // Verify proof: simple hash verification for testnet
        bytes32 expectedProof = keccak256(abi.encodePacked(requestId, req.seed, randomValue, req.blockNumber));
        if (proof != expectedProof) revert InvalidProof();

        req.randomValue = randomValue;
        req.proof = proof;
        req.status = RequestStatus.Fulfilled;
        req.fulfilledAt = block.timestamp;
        totalFulfilled++;

        // Callback to consumer contract
        try IRandomConsumer(req.callbackContract).fulfillRandomness(requestId, randomValue) {
            // Success
        } catch {
            // Callback failed but fulfillment still recorded
        }

        emit RandomnessFulfilled(requestId, randomValue, proof, msg.sender);
    }

    /**
     * @notice Get the random result for a request
     * @param requestId The request to query
     * @return request The full request data
     */
    function getRandomResult(uint256 requestId) external view returns (RandomRequest memory request) {
        if (_requests[requestId].id == 0) revert RequestNotFound(requestId);
        return _requests[requestId];
    }

    /**
     * @notice Cancel a timed-out request and get refund
     * @param requestId The request to cancel
     */
    function cancelRequest(uint256 requestId) external nonReentrant whenNotPaused {
        RandomRequest storage req = _requests[requestId];
        if (req.id == 0) revert RequestNotFound(requestId);
        if (req.requester != msg.sender) revert NotRequester(msg.sender);
        if (req.status != RequestStatus.Pending) revert RequestNotPending(requestId);
        if (block.number < req.blockNumber + requestTimeout) revert RequestNotTimedOut(requestId);

        req.status = RequestStatus.Cancelled;

        (bool success, ) = msg.sender.call{value: requestFee}("");
        require(success, "Refund failed");

        emit RequestCancelled(requestId);
    }

    /**
     * @notice Get all requests for a user
     * @param user The user address
     * @return ids Array of request IDs
     */
    function getUserRequests(address user) external view returns (uint256[] memory ids) {
        return _userRequests[user];
    }

    /**
     * @notice Generate a proof hash (helper for oracles)
     * @param requestId The request ID
     * @param randomValue The random value
     * @return proofHash The expected proof hash
     */
    function generateProof(uint256 requestId, uint256 randomValue) external view returns (bytes32 proofHash) {
        RandomRequest storage req = _requests[requestId];
        if (req.id == 0) revert RequestNotFound(requestId);
        return keccak256(abi.encodePacked(requestId, req.seed, randomValue, req.blockNumber));
    }

    /// @notice Set oracle status
    function setOracle(address oracle, bool active) external onlyOwner {
        _oracles[oracle] = active;
        emit OracleUpdated(oracle, active);
    }

    /// @notice Check if address is an oracle
    function isOracle(address addr) external view returns (bool) { return _oracles[addr]; }

    /// @notice Update request fee
    function setRequestFee(uint256 fee) external onlyOwner { requestFee = fee; }

    /// @notice Update request timeout (blocks)
    function setRequestTimeout(uint256 timeout) external onlyOwner { requestTimeout = timeout; }

    /// @notice Withdraw collected fees
    function withdrawFees() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    receive() external payable {}
}
