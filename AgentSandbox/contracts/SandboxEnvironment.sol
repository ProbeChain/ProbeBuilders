// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SandboxEnvironment
 * @author ProbeChain Team
 * @notice Agent testing sandbox for safe experimentation on ProbeChain Rydberg Testnet
 * @dev Provides isolated sandboxes where AI agents can be tested before production deployment
 */

/// @notice Inline Ownable implementation
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

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/// @notice Inline ReentrancyGuard implementation
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

/// @notice Inline Pausable implementation
abstract contract Pausable is Ownable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    error EnforcedPause();
    error ExpectedPause();

    modifier whenNotPaused() {
        if (_paused) revert EnforcedPause();
        _;
    }

    modifier whenPaused() {
        if (!_paused) revert ExpectedPause();
        _;
    }

    function paused() public view returns (bool) {
        return _paused;
    }

    function pause() external onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract SandboxEnvironment is Ownable, ReentrancyGuard, Pausable {
    /// @notice Sandbox status enum
    enum SandboxStatus { Created, Running, Completed, Promoted, Terminated }

    /// @notice Sandbox configuration
    struct SandboxConfig {
        uint256 gasLimit;
        uint256 timeoutBlocks;
        bool allowExternalCalls;
        uint8 maxActions;
    }

    /// @notice Sandbox state
    struct Sandbox {
        uint256 id;
        address agentId;
        SandboxConfig config;
        SandboxStatus status;
        uint256 createdAt;
        uint256 actionCount;
        uint256 behaviorScore;
        bytes lastResult;
        address creator;
    }

    /// @dev Sandbox storage
    mapping(uint256 => Sandbox) private _sandboxes;
    /// @dev Agent to sandbox IDs mapping
    mapping(address => uint256[]) private _agentSandboxes;
    /// @dev Sandbox action log
    mapping(uint256 => bytes[]) private _actionLogs;

    uint256 private _nextSandboxId = 1;
    uint256 public minBehaviorScoreForPromotion = 70;

    /// @notice Emitted when a sandbox is created
    event SandboxCreated(uint256 indexed sandboxId, address indexed agentId, address indexed creator);
    /// @notice Emitted when an action is executed in sandbox
    event SandboxActionExecuted(uint256 indexed sandboxId, bytes actionData, bytes result);
    /// @notice Emitted when behavior is scored
    event BehaviorScored(uint256 indexed sandboxId, uint256 score);
    /// @notice Emitted when an agent is promoted to production
    event PromotedToProd(uint256 indexed sandboxId, address indexed agentId);
    /// @notice Emitted when a sandbox is terminated
    event SandboxTerminated(uint256 indexed sandboxId);

    error SandboxNotFound(uint256 sandboxId);
    error SandboxNotRunning(uint256 sandboxId);
    error SandboxAlreadyPromoted(uint256 sandboxId);
    error MaxActionsReached(uint256 sandboxId);
    error InsufficientBehaviorScore(uint256 score, uint256 required);
    error UnauthorizedCaller(address caller);

    /**
     * @notice Create a new testing sandbox for an agent
     * @param agentId The address of the agent to be tested
     * @param config The sandbox configuration parameters
     * @return sandboxId The unique identifier of the created sandbox
     */
    function createSandbox(
        address agentId,
        SandboxConfig calldata config
    ) external whenNotPaused returns (uint256 sandboxId) {
        sandboxId = _nextSandboxId++;

        _sandboxes[sandboxId] = Sandbox({
            id: sandboxId,
            agentId: agentId,
            config: config,
            status: SandboxStatus.Running,
            createdAt: block.timestamp,
            actionCount: 0,
            behaviorScore: 0,
            lastResult: "",
            creator: msg.sender
        });

        _agentSandboxes[agentId].push(sandboxId);
        emit SandboxCreated(sandboxId, agentId, msg.sender);
    }

    /**
     * @notice Execute an action inside a sandbox
     * @param sandboxId The sandbox to execute in
     * @param actionData The encoded action data
     * @return result The execution result
     */
    function executeInSandbox(
        uint256 sandboxId,
        bytes calldata actionData
    ) external nonReentrant whenNotPaused returns (bytes memory result) {
        Sandbox storage sb = _sandboxes[sandboxId];
        if (sb.id == 0) revert SandboxNotFound(sandboxId);
        if (sb.status != SandboxStatus.Running) revert SandboxNotRunning(sandboxId);
        if (sb.actionCount >= sb.config.maxActions) revert MaxActionsReached(sandboxId);

        // Simulate action execution — hash-based result for testing
        result = abi.encode(
            keccak256(abi.encodePacked(sandboxId, actionData, block.timestamp, sb.actionCount))
        );

        sb.actionCount++;
        sb.lastResult = result;
        _actionLogs[sandboxId].push(actionData);

        emit SandboxActionExecuted(sandboxId, actionData, result);
    }

    /**
     * @notice Get the current state of a sandbox
     * @param sandboxId The sandbox to query
     * @return sandbox The full sandbox state
     */
    function getSandboxState(uint256 sandboxId) external view returns (Sandbox memory sandbox) {
        if (_sandboxes[sandboxId].id == 0) revert SandboxNotFound(sandboxId);
        return _sandboxes[sandboxId];
    }

    /**
     * @notice Score the behavior of an agent in a sandbox
     * @param sandboxId The sandbox to score
     * @return score The computed behavior score (0-100)
     */
    function scoreBehavior(uint256 sandboxId) external whenNotPaused returns (uint256 score) {
        Sandbox storage sb = _sandboxes[sandboxId];
        if (sb.id == 0) revert SandboxNotFound(sandboxId);
        if (sb.creator != msg.sender && owner() != msg.sender) revert UnauthorizedCaller(msg.sender);

        // Score based on action count, config adherence, and pseudo-random factor
        uint256 actionRatio = sb.config.maxActions > 0
            ? (sb.actionCount * 100) / sb.config.maxActions
            : 0;
        uint256 timeFactor = ((block.timestamp - sb.createdAt) % 30) + 1;
        score = (actionRatio + timeFactor * 2) % 101;

        sb.behaviorScore = score;
        emit BehaviorScored(sandboxId, score);
    }

    /**
     * @notice Promote a tested agent to production status
     * @param sandboxId The sandbox containing the agent to promote
     */
    function promoteToProd(uint256 sandboxId) external whenNotPaused {
        Sandbox storage sb = _sandboxes[sandboxId];
        if (sb.id == 0) revert SandboxNotFound(sandboxId);
        if (sb.status == SandboxStatus.Promoted) revert SandboxAlreadyPromoted(sandboxId);
        if (sb.creator != msg.sender && owner() != msg.sender) revert UnauthorizedCaller(msg.sender);
        if (sb.behaviorScore < minBehaviorScoreForPromotion) {
            revert InsufficientBehaviorScore(sb.behaviorScore, minBehaviorScoreForPromotion);
        }

        sb.status = SandboxStatus.Promoted;
        emit PromotedToProd(sandboxId, sb.agentId);
    }

    /**
     * @notice Terminate a sandbox
     * @param sandboxId The sandbox to terminate
     */
    function terminateSandbox(uint256 sandboxId) external {
        Sandbox storage sb = _sandboxes[sandboxId];
        if (sb.id == 0) revert SandboxNotFound(sandboxId);
        if (sb.creator != msg.sender && owner() != msg.sender) revert UnauthorizedCaller(msg.sender);

        sb.status = SandboxStatus.Terminated;
        emit SandboxTerminated(sandboxId);
    }

    /**
     * @notice Get all sandbox IDs for an agent
     * @param agentId The agent address
     * @return ids Array of sandbox IDs
     */
    function getAgentSandboxes(address agentId) external view returns (uint256[] memory ids) {
        return _agentSandboxes[agentId];
    }

    /**
     * @notice Get action log for a sandbox
     * @param sandboxId The sandbox to query
     * @return logs Array of action data entries
     */
    function getActionLog(uint256 sandboxId) external view returns (bytes[] memory logs) {
        return _actionLogs[sandboxId];
    }

    /**
     * @notice Update minimum behavior score required for promotion
     * @param newMin The new minimum score (0-100)
     */
    function setMinBehaviorScore(uint256 newMin) external onlyOwner {
        require(newMin <= 100, "Score must be <= 100");
        minBehaviorScoreForPromotion = newMin;
    }
}
