// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AirQualityDAO
 * @author ProbeChain
 * @notice Community-governed air quality monitoring DAO on ProbeChain Rydberg Testnet
 * @dev Sensor deployment, AQI reporting, area queries, and governance proposals
 */
contract AirQualityDAO {
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

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "Paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums & Structs ────────────────────────────────────────────────
    enum SensorType { Basic, Advanced, Industrial }
    enum ProposalStatus { Pending, Active, Passed, Rejected, Executed }

    struct AirSensor {
        address deployer;
        bytes32 locationHash;
        SensorType sensorType;
        bool active;
        uint256 reportCount;
        uint256 deployedAt;
    }

    struct AQIReport {
        uint256 pm25;
        uint256 pm10;
        uint256 o3;
        uint256 co2;
        uint256 timestamp;
    }

    struct Proposal {
        address proposer;
        string description;
        ProposalStatus status;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 deadline;
        uint256 createdAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => AirSensor) public sensors;
    mapping(uint256 => AQIReport[]) private _reports;
    mapping(bytes32 => uint256[]) public areaSensors;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(address => bool) public members;
    uint256 public nextSensorId;
    uint256 public nextProposalId;
    uint256 public memberCount;
    uint256 public votingDuration = 3 days;

    // ─── Events ─────────────────────────────────────────────────────────
    event SensorDeployed(uint256 indexed sensorId, address indexed deployer, bytes32 locationHash, SensorType sensorType);
    event AQIReported(uint256 indexed sensorId, uint256 pm25, uint256 pm10, uint256 o3, uint256 co2);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed proposalId, ProposalStatus status);
    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        members[msg.sender] = true;
        memberCount = 1;
        emit OwnershipTransferred(address(0), msg.sender);
        emit MemberAdded(msg.sender);
    }

    modifier onlyMember() { require(members[msg.sender], "Not member"); _; }

    // ─── Admin ──────────────────────────────────────────────────────────
    function addMember(address member) external onlyOwner {
        require(!members[member], "Already member");
        members[member] = true;
        memberCount++;
        emit MemberAdded(member);
    }

    function removeMember(address member) external onlyOwner {
        require(members[member], "Not member");
        require(member != _owner, "Cannot remove owner");
        members[member] = false;
        memberCount--;
        emit MemberRemoved(member);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Deploy a new air quality sensor
     * @param locationHash Geohash of sensor location
     * @param sensorType Type of sensor
     */
    function deploySensor(bytes32 locationHash, SensorType sensorType) external whenNotPaused onlyMember returns (uint256) {
        require(locationHash != bytes32(0), "Empty location");

        uint256 id = nextSensorId++;
        sensors[id] = AirSensor({
            deployer: msg.sender,
            locationHash: locationHash,
            sensorType: sensorType,
            active: true,
            reportCount: 0,
            deployedAt: block.timestamp
        });

        areaSensors[locationHash].push(id);
        emit SensorDeployed(id, msg.sender, locationHash, sensorType);
        return id;
    }

    /**
     * @notice Report air quality index data
     * @param sensorId The sensor reporting
     * @param pm25 PM2.5 concentration
     * @param pm10 PM10 concentration
     * @param o3 Ozone level
     * @param co2 CO2 level
     */
    function reportAQI(
        uint256 sensorId,
        uint256 pm25,
        uint256 pm10,
        uint256 o3,
        uint256 co2
    ) external whenNotPaused {
        AirSensor storage s = sensors[sensorId];
        require(s.active, "Sensor not active");
        require(msg.sender == s.deployer, "Not sensor deployer");

        _reports[sensorId].push(AQIReport({
            pm25: pm25,
            pm10: pm10,
            o3: o3,
            co2: co2,
            timestamp: block.timestamp
        }));
        s.reportCount++;

        emit AQIReported(sensorId, pm25, pm10, o3, co2);
    }

    /**
     * @notice Get sensor IDs for an area
     * @param locationHash The area to query
     */
    function getAreaQuality(bytes32 locationHash) external view returns (uint256[] memory) {
        return areaSensors[locationHash];
    }

    /**
     * @notice Get AQI reports for a sensor
     */
    function getSensorReports(uint256 sensorId, uint256 offset, uint256 limit)
        external view returns (AQIReport[] memory)
    {
        AQIReport[] storage reports = _reports[sensorId];
        if (offset >= reports.length) return new AQIReport[](0);
        uint256 end = offset + limit > reports.length ? reports.length : offset + limit;
        AQIReport[] memory result = new AQIReport[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = reports[i];
        }
        return result;
    }

    /**
     * @notice Propose an action for DAO vote
     * @param description Description of the proposal
     */
    function proposeAction(string calldata description) external whenNotPaused onlyMember returns (uint256) {
        require(bytes(description).length > 0, "Empty description");

        uint256 id = nextProposalId++;
        proposals[id] = Proposal({
            proposer: msg.sender,
            description: description,
            status: ProposalStatus.Active,
            votesFor: 0,
            votesAgainst: 0,
            deadline: block.timestamp + votingDuration,
            createdAt: block.timestamp
        });

        emit ProposalCreated(id, msg.sender, description);
        return id;
    }

    /**
     * @notice Vote on a proposal
     * @param proposalId The proposal to vote on
     * @param support True for yes, false for no
     */
    function voteOnAction(uint256 proposalId, bool support) external whenNotPaused onlyMember {
        Proposal storage p = proposals[proposalId];
        require(p.status == ProposalStatus.Active, "Not active");
        require(block.timestamp < p.deadline, "Voting ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted");

        hasVoted[proposalId][msg.sender] = true;
        if (support) {
            p.votesFor++;
        } else {
            p.votesAgainst++;
        }

        emit Voted(proposalId, msg.sender, support);
    }

    /**
     * @notice Finalize a proposal after voting ends
     * @param proposalId The proposal to finalize
     */
    function finalizeProposal(uint256 proposalId) external whenNotPaused {
        Proposal storage p = proposals[proposalId];
        require(p.status == ProposalStatus.Active, "Not active");
        require(block.timestamp >= p.deadline, "Voting ongoing");

        p.status = p.votesFor > p.votesAgainst ? ProposalStatus.Passed : ProposalStatus.Rejected;
        emit ProposalExecuted(proposalId, p.status);
    }
}
