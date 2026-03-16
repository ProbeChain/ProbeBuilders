// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MigrationTracker
 * @author ProbeChain Team
 * @notice Cross-chain contract migration tracking and status management
 * @dev Records migration steps with transaction hashes for full audit trail
 */
contract MigrationTracker {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "MigrationTracker: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "MigrationTracker: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "MigrationTracker: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums ──────────────────────────────────────────────────────────
    enum MigrationStatus { InProgress, Completed, Failed, Cancelled }
    enum StepStatus { Pending, Success, Failed, Skipped }

    // ─── Structs ────────────────────────────────────────────────────────
    struct Migration {
        uint256 id;
        address initiator;
        string sourceChain;
        address sourceContract;
        address targetContract;
        MigrationStatus status;
        uint256 stepCount;
        uint256 startedAt;
        uint256 completedAt;
    }

    struct MigrationStep {
        uint256 id;
        uint256 migrationId;
        string stepName;
        StepStatus status;
        bytes32 txHash;
        string notes;
        uint256 timestamp;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public migrationCount;
    uint256 public stepCount;

    mapping(uint256 => Migration) public migrations;
    mapping(uint256 => MigrationStep) public steps;
    mapping(uint256 => uint256[]) public migrationSteps;
    mapping(address => uint256[]) public userMigrations;
    mapping(address => bool) public authorizedAgents;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a new migration is started
    event MigrationStarted(uint256 indexed migrationId, address indexed initiator, string sourceChain, address sourceContract, address targetContract);
    /// @notice Emitted when a migration step is recorded
    event StepRecorded(uint256 indexed stepId, uint256 indexed migrationId, string stepName, StepStatus status);
    /// @notice Emitted when a migration is completed
    event MigrationCompleted(uint256 indexed migrationId, uint256 totalSteps);
    /// @notice Emitted when a migration fails
    event MigrationFailed(uint256 indexed migrationId, string reason);
    /// @notice Emitted when agent authorization changes
    event AgentAuthorized(address indexed agent, bool status);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Agent Management ───────────────────────────────────────────────
    /**
     * @notice Authorize or revoke a migration agent
     * @param agent Agent address
     * @param status Authorization status
     */
    function setAuthorizedAgent(address agent, bool status) external onlyOwner {
        authorizedAgents[agent] = status;
        emit AgentAuthorized(agent, status);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Start a new cross-chain migration
     * @param sourceChain Name of the source blockchain
     * @param sourceContract Address on the source chain
     * @param targetContract Address on the target chain
     * @return migrationId The ID of the new migration
     */
    function startMigration(
        string calldata sourceChain,
        address sourceContract,
        address targetContract
    ) external whenNotPaused returns (uint256 migrationId) {
        require(bytes(sourceChain).length > 0, "MigrationTracker: empty source chain");
        require(sourceContract != address(0), "MigrationTracker: zero source");
        require(targetContract != address(0), "MigrationTracker: zero target");

        migrationCount++;
        migrationId = migrationCount;

        migrations[migrationId] = Migration({
            id: migrationId,
            initiator: msg.sender,
            sourceChain: sourceChain,
            sourceContract: sourceContract,
            targetContract: targetContract,
            status: MigrationStatus.InProgress,
            stepCount: 0,
            startedAt: block.timestamp,
            completedAt: 0
        });

        userMigrations[msg.sender].push(migrationId);
        emit MigrationStarted(migrationId, msg.sender, sourceChain, sourceContract, targetContract);
    }

    /**
     * @notice Record a step in a migration
     * @param migrationId Migration to record the step for
     * @param stepName Human-readable step name
     * @param status Step outcome
     * @param txHash Transaction hash on the relevant chain
     * @param notes Optional notes
     */
    function recordStep(
        uint256 migrationId,
        string calldata stepName,
        StepStatus status,
        bytes32 txHash,
        string calldata notes
    ) external whenNotPaused {
        Migration storage m = migrations[migrationId];
        require(m.status == MigrationStatus.InProgress, "MigrationTracker: not in progress");
        require(
            msg.sender == m.initiator || authorizedAgents[msg.sender],
            "MigrationTracker: unauthorized"
        );
        require(bytes(stepName).length > 0, "MigrationTracker: empty step name");

        stepCount++;
        steps[stepCount] = MigrationStep({
            id: stepCount,
            migrationId: migrationId,
            stepName: stepName,
            status: status,
            txHash: txHash,
            notes: notes,
            timestamp: block.timestamp
        });

        m.stepCount++;
        migrationSteps[migrationId].push(stepCount);

        emit StepRecorded(stepCount, migrationId, stepName, status);

        if (status == StepStatus.Failed) {
            m.status = MigrationStatus.Failed;
            emit MigrationFailed(migrationId, stepName);
        }
    }

    /**
     * @notice Mark a migration as completed
     * @param migrationId Migration to complete
     */
    function completeMigration(uint256 migrationId) external {
        Migration storage m = migrations[migrationId];
        require(m.status == MigrationStatus.InProgress, "MigrationTracker: not in progress");
        require(
            msg.sender == m.initiator || authorizedAgents[msg.sender],
            "MigrationTracker: unauthorized"
        );

        m.status = MigrationStatus.Completed;
        m.completedAt = block.timestamp;

        emit MigrationCompleted(migrationId, m.stepCount);
    }

    /**
     * @notice Cancel a migration
     * @param migrationId Migration to cancel
     */
    function cancelMigration(uint256 migrationId) external {
        Migration storage m = migrations[migrationId];
        require(m.status == MigrationStatus.InProgress, "MigrationTracker: not in progress");
        require(msg.sender == m.initiator || msg.sender == _owner, "MigrationTracker: unauthorized");

        m.status = MigrationStatus.Cancelled;
        m.completedAt = block.timestamp;
    }

    /**
     * @notice Get all steps for a migration
     * @param migrationId Migration ID
     * @return stepIds Array of step IDs
     */
    function getMigrationStatus(uint256 migrationId) external view returns (
        MigrationStatus status,
        uint256 totalSteps,
        uint256[] memory stepIds
    ) {
        Migration storage m = migrations[migrationId];
        return (m.status, m.stepCount, migrationSteps[migrationId]);
    }

    /**
     * @notice Get user's migration count
     * @param user User address
     * @return count Number of migrations
     */
    function getUserMigrationCount(address user) external view returns (uint256 count) {
        return userMigrations[user].length;
    }
}
