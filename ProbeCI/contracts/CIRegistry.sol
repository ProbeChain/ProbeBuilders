// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CIRegistry
 * @author ProbeChain Team
 * @notice Immutable CI/CD build result registry for on-chain build provenance
 * @dev Records pipelines, builds, and artifact hashes for verifiable build history
 */
contract CIRegistry {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "CIRegistry: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "CIRegistry: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "CIRegistry: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums ──────────────────────────────────────────────────────────
    enum BuildStatus { Success, Failed, Cancelled, Running }

    // ─── Structs ────────────────────────────────────────────────────────
    struct Pipeline {
        uint256 id;
        string name;
        bytes32 repoHash;
        address maintainer;
        uint256 buildCount;
        uint256 successCount;
        uint256 createdAt;
        bool active;
    }

    struct Build {
        uint256 id;
        uint256 pipelineId;
        bytes32 commitHash;
        BuildStatus status;
        bytes32 artifactHash;
        uint256 timestamp;
        uint256 duration;
        address triggeredBy;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public pipelineCount;
    uint256 public buildCount;

    mapping(uint256 => Pipeline) public pipelines;
    mapping(uint256 => Build) public builds;
    mapping(uint256 => uint256[]) public pipelineBuilds;
    mapping(address => uint256[]) public maintainerPipelines;
    mapping(address => bool) public authorizedRunners;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a new pipeline is registered
    event PipelineRegistered(uint256 indexed pipelineId, string name, bytes32 repoHash, address indexed maintainer);
    /// @notice Emitted when a build is recorded
    event BuildRecorded(uint256 indexed buildId, uint256 indexed pipelineId, bytes32 commitHash, BuildStatus status);
    /// @notice Emitted when a build artifact is verified
    event ArtifactVerified(uint256 indexed buildId, bytes32 artifactHash, bool valid);
    /// @notice Emitted when runner authorization changes
    event RunnerAuthorized(address indexed runner, bool status);
    /// @notice Emitted when a pipeline is deactivated
    event PipelineDeactivated(uint256 indexed pipelineId);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Runner Management ──────────────────────────────────────────────
    /**
     * @notice Authorize or revoke a CI runner
     * @param runner Address of the runner
     * @param status Authorization status
     */
    function setAuthorizedRunner(address runner, bool status) external onlyOwner {
        authorizedRunners[runner] = status;
        emit RunnerAuthorized(runner, status);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register a new CI/CD pipeline
     * @param name Pipeline name
     * @param repoHash Hash of the repository URL or identifier
     * @return pipelineId The ID of the created pipeline
     */
    function registerPipeline(
        string calldata name,
        bytes32 repoHash
    ) external whenNotPaused returns (uint256 pipelineId) {
        require(bytes(name).length > 0 && bytes(name).length <= 128, "CIRegistry: invalid name");
        require(repoHash != bytes32(0), "CIRegistry: empty repo hash");

        pipelineCount++;
        pipelineId = pipelineCount;

        pipelines[pipelineId] = Pipeline({
            id: pipelineId,
            name: name,
            repoHash: repoHash,
            maintainer: msg.sender,
            buildCount: 0,
            successCount: 0,
            createdAt: block.timestamp,
            active: true
        });

        maintainerPipelines[msg.sender].push(pipelineId);
        emit PipelineRegistered(pipelineId, name, repoHash, msg.sender);
    }

    /**
     * @notice Record a build result for a pipeline
     * @param pipelineId Pipeline to record the build for
     * @param commitHash Git commit hash
     * @param status Build outcome
     * @param artifactHash Hash of the build artifact
     * @param buildTimestamp Timestamp when the build ran
     * @param duration Build duration in seconds
     */
    function recordBuild(
        uint256 pipelineId,
        bytes32 commitHash,
        BuildStatus status,
        bytes32 artifactHash,
        uint256 buildTimestamp,
        uint256 duration
    ) external whenNotPaused {
        Pipeline storage pipeline = pipelines[pipelineId];
        require(pipeline.active, "CIRegistry: pipeline not active");
        require(
            msg.sender == pipeline.maintainer || authorizedRunners[msg.sender],
            "CIRegistry: unauthorized"
        );
        require(commitHash != bytes32(0), "CIRegistry: empty commit hash");

        buildCount++;
        builds[buildCount] = Build({
            id: buildCount,
            pipelineId: pipelineId,
            commitHash: commitHash,
            status: status,
            artifactHash: artifactHash,
            timestamp: buildTimestamp,
            duration: duration,
            triggeredBy: msg.sender
        });

        pipeline.buildCount++;
        if (status == BuildStatus.Success) {
            pipeline.successCount++;
        }

        pipelineBuilds[pipelineId].push(buildCount);
        emit BuildRecorded(buildCount, pipelineId, commitHash, status);
    }

    /**
     * @notice Get build history for a pipeline (last N builds)
     * @param pipelineId Pipeline ID
     * @param limit Maximum number of builds to return
     * @return buildIds Array of build IDs (most recent first)
     */
    function getBuildHistory(
        uint256 pipelineId,
        uint256 limit
    ) external view returns (uint256[] memory buildIds) {
        uint256[] storage allBuilds = pipelineBuilds[pipelineId];
        uint256 len = allBuilds.length > limit ? limit : allBuilds.length;
        buildIds = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            buildIds[i] = allBuilds[allBuilds.length - 1 - i];
        }
    }

    /**
     * @notice Verify a build artifact hash
     * @param buildId Build to verify
     * @param artifactHash Hash to check
     * @return valid True if the hash matches
     */
    function verifyArtifact(uint256 buildId, bytes32 artifactHash) external returns (bool valid) {
        valid = builds[buildId].artifactHash == artifactHash;
        emit ArtifactVerified(buildId, artifactHash, valid);
    }

    /**
     * @notice Get success rate for a pipeline
     * @param pipelineId Pipeline ID
     * @return rate Success rate as percentage (0-100)
     */
    function getSuccessRate(uint256 pipelineId) external view returns (uint256 rate) {
        Pipeline storage p = pipelines[pipelineId];
        if (p.buildCount == 0) return 0;
        return (p.successCount * 100) / p.buildCount;
    }

    /**
     * @notice Deactivate a pipeline
     * @param pipelineId Pipeline to deactivate
     */
    function deactivatePipeline(uint256 pipelineId) external {
        require(
            pipelines[pipelineId].maintainer == msg.sender || msg.sender == _owner,
            "CIRegistry: unauthorized"
        );
        pipelines[pipelineId].active = false;
        emit PipelineDeactivated(pipelineId);
    }
}
