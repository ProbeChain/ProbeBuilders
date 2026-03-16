// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title ReputationSystem — On-chain multi-dimensional reputation for ProbeChain
/// @author ProbeBuilders
/// @notice Endorse agents across dimensions (reliability, speed, accuracy, cooperation), weighted scoring
/// @dev Rydberg Testnet (Chain ID 8004). Scores are 0-100, weighted by endorser reputation.
contract ReputationSystem {
    // ─── Enums & Structs ─────────────────────────────────────────────────
    /// @notice Scoring dimensions for agent reputation
    enum Dimension { Reliability, Speed, Accuracy, Cooperation }

    struct Endorsement {
        uint256 id;
        address endorser;
        uint256 agentId;
        Dimension dimension;
        uint8 score;        // 1-100
        uint256 weight;     // endorser's reputation at time of endorsement
        string comment;
        uint256 createdAt;
    }

    struct AgentReputation {
        uint256 agentId;
        address agentAddress;
        bool registered;
        uint256 totalEndorsements;
        uint256 registeredAt;
        // Per-dimension aggregates
        mapping(Dimension => uint256) dimensionScoreSum;
        mapping(Dimension => uint256) dimensionWeightSum;
        mapping(Dimension => uint256) dimensionCount;
    }

    struct ReputationView {
        uint256 agentId;
        address agentAddress;
        uint256 reliability;
        uint256 speed;
        uint256 accuracy;
        uint256 cooperation;
        uint256 overall;
        uint256 totalEndorsements;
    }

    // ─── State ───────────────────────────────────────────────────────────
    address public owner;
    bool public paused;

    uint256 private _nextEndorsementId = 1;
    uint256 private _nextAgentId = 1;

    mapping(uint256 => AgentReputation) private _agentReputations;
    mapping(address => uint256) public addressToAgentId;
    mapping(uint256 => Endorsement) public endorsements;
    mapping(uint256 => uint256[]) private _agentEndorsementIds;
    // endorser => agentId => dimension => endorsed
    mapping(address => mapping(uint256 => mapping(Dimension => bool))) private _hasEndorsed;

    uint256 public totalAgents;
    uint256 public totalEndorsements;

    // Dimension weights for overall score (sum = 100)
    uint256 public weightReliability = 30;
    uint256 public weightSpeed = 20;
    uint256 public weightAccuracy = 30;
    uint256 public weightCooperation = 20;

    uint256 public cooldownPeriod = 7 days; // time before re-endorsing same dimension

    // ─── Events ──────────────────────────────────────────────────────────
    event AgentRegistered(uint256 indexed agentId, address indexed agentAddress);
    event EndorsementCreated(uint256 indexed endorsementId, address indexed endorser, uint256 indexed agentId, Dimension dimension, uint8 score);
    event ReputationUpdated(uint256 indexed agentId, Dimension dimension, uint256 newWeightedAvg);
    event DimensionWeightsUpdated(uint256 reliability, uint256 speed, uint256 accuracy, uint256 cooperation);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "ReputationSystem: not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "ReputationSystem: paused");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Agent Registration ──────────────────────────────────────────────

    /// @notice Register an agent for reputation tracking
    /// @return agentId The assigned agent ID
    function registerAgent() external whenNotPaused returns (uint256 agentId) {
        require(addressToAgentId[msg.sender] == 0, "ReputationSystem: already registered");

        agentId = _nextAgentId++;
        AgentReputation storage rep = _agentReputations[agentId];
        rep.agentId = agentId;
        rep.agentAddress = msg.sender;
        rep.registered = true;
        rep.registeredAt = block.timestamp;

        addressToAgentId[msg.sender] = agentId;
        totalAgents++;

        emit AgentRegistered(agentId, msg.sender);
    }

    // ─── Endorsements ────────────────────────────────────────────────────

    /// @notice Endorse an agent on a specific dimension
    /// @param agentId The agent to endorse
    /// @param dimension The scoring dimension
    /// @param score Score from 1 to 100
    /// @param comment Optional comment
    /// @return endorsementId The endorsement ID
    function endorseAgent(
        uint256 agentId,
        Dimension dimension,
        uint8 score,
        string calldata comment
    ) external whenNotPaused returns (uint256 endorsementId) {
        AgentReputation storage rep = _agentReputations[agentId];
        require(rep.registered, "ReputationSystem: agent not registered");
        require(rep.agentAddress != msg.sender, "ReputationSystem: cannot self-endorse");
        require(score >= 1 && score <= 100, "ReputationSystem: score 1-100");
        require(!_hasEndorsed[msg.sender][agentId][dimension], "ReputationSystem: already endorsed this dimension");

        // Calculate endorser weight (higher rep = more influence)
        uint256 endorserAgentId = addressToAgentId[msg.sender];
        uint256 endorserWeight = 10; // default weight for non-agents
        if (endorserAgentId != 0) {
            uint256 endorserRep = _getOverallScore(endorserAgentId);
            endorserWeight = endorserRep > 0 ? endorserRep : 10;
        }

        endorsementId = _nextEndorsementId++;

        endorsements[endorsementId] = Endorsement({
            id: endorsementId,
            endorser: msg.sender,
            agentId: agentId,
            dimension: dimension,
            score: score,
            weight: endorserWeight,
            comment: comment,
            createdAt: block.timestamp
        });

        // Update dimension aggregates (weighted)
        rep.dimensionScoreSum[dimension] += uint256(score) * endorserWeight;
        rep.dimensionWeightSum[dimension] += endorserWeight;
        rep.dimensionCount[dimension]++;
        rep.totalEndorsements++;

        _agentEndorsementIds[agentId].push(endorsementId);
        _hasEndorsed[msg.sender][agentId][dimension] = true;
        totalEndorsements++;

        uint256 newAvg = rep.dimensionScoreSum[dimension] / rep.dimensionWeightSum[dimension];
        emit EndorsementCreated(endorsementId, msg.sender, agentId, dimension, score);
        emit ReputationUpdated(agentId, dimension, newAvg);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Get reputation for an agent across all dimensions
    /// @param agentId The agent to query
    /// @return view_ Full reputation breakdown
    function getReputation(uint256 agentId) external view returns (ReputationView memory view_) {
        AgentReputation storage rep = _agentReputations[agentId];
        require(rep.registered, "ReputationSystem: agent not found");

        view_.agentId = agentId;
        view_.agentAddress = rep.agentAddress;
        view_.reliability = _getDimensionScore(agentId, Dimension.Reliability);
        view_.speed = _getDimensionScore(agentId, Dimension.Speed);
        view_.accuracy = _getDimensionScore(agentId, Dimension.Accuracy);
        view_.cooperation = _getDimensionScore(agentId, Dimension.Cooperation);
        view_.overall = _getOverallScore(agentId);
        view_.totalEndorsements = rep.totalEndorsements;
    }

    /// @notice Get weighted average for a specific dimension
    /// @param agentId The agent
    /// @param dimension The dimension
    /// @return Weighted average score (0-100)
    function getDimensionScore(uint256 agentId, Dimension dimension) external view returns (uint256) {
        return _getDimensionScore(agentId, dimension);
    }

    /// @notice Get overall weighted score across all dimensions
    /// @param agentId The agent
    /// @return Overall score (0-100)
    function getOverallScore(uint256 agentId) external view returns (uint256) {
        return _getOverallScore(agentId);
    }

    /// @notice Get endorsements for an agent
    /// @param agentId The agent
    /// @return ids Array of endorsement IDs
    function getEndorsements(uint256 agentId) external view returns (uint256[] memory ids) {
        return _agentEndorsementIds[agentId];
    }

    /// @notice Check if endorser has endorsed agent on dimension
    function hasEndorsed(address endorser, uint256 agentId, Dimension dimension) external view returns (bool) {
        return _hasEndorsed[endorser][agentId][dimension];
    }

    // ─── Internal ────────────────────────────────────────────────────────

    function _getDimensionScore(uint256 agentId, Dimension dim) internal view returns (uint256) {
        AgentReputation storage rep = _agentReputations[agentId];
        if (rep.dimensionWeightSum[dim] == 0) return 0;
        return rep.dimensionScoreSum[dim] / rep.dimensionWeightSum[dim];
    }

    function _getOverallScore(uint256 agentId) internal view returns (uint256) {
        uint256 rel = _getDimensionScore(agentId, Dimension.Reliability);
        uint256 spd = _getDimensionScore(agentId, Dimension.Speed);
        uint256 acc = _getDimensionScore(agentId, Dimension.Accuracy);
        uint256 coop = _getDimensionScore(agentId, Dimension.Cooperation);

        uint256 totalWeight;
        uint256 weightedSum;

        if (rel > 0) { weightedSum += rel * weightReliability; totalWeight += weightReliability; }
        if (spd > 0) { weightedSum += spd * weightSpeed; totalWeight += weightSpeed; }
        if (acc > 0) { weightedSum += acc * weightAccuracy; totalWeight += weightAccuracy; }
        if (coop > 0) { weightedSum += coop * weightCooperation; totalWeight += weightCooperation; }

        if (totalWeight == 0) return 0;
        return weightedSum / totalWeight;
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    /// @notice Update dimension weights (must sum to 100)
    function setDimensionWeights(uint256 rel, uint256 spd, uint256 acc, uint256 coop) external onlyOwner {
        require(rel + spd + acc + coop == 100, "ReputationSystem: weights must sum to 100");
        weightReliability = rel;
        weightSpeed = spd;
        weightAccuracy = acc;
        weightCooperation = coop;
        emit DimensionWeightsUpdated(rel, spd, acc, coop);
    }

    function setCooldownPeriod(uint256 newPeriod) external onlyOwner {
        cooldownPeriod = newPeriod;
    }

    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ReputationSystem: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
