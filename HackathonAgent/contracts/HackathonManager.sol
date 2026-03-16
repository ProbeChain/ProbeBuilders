// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title HackathonManager
 * @author ProbeChain Team
 * @notice Decentralized hackathon platform with team registration, judging, and prizes
 * @dev Full hackathon lifecycle: creation, registration, submission, judging, prize distribution
 */
contract HackathonManager {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "HackathonManager: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "HackathonManager: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _guardStatus = 1;
    modifier nonReentrant() {
        require(_guardStatus == 1, "HackathonManager: reentrant call");
        _guardStatus = 2;
        _;
        _guardStatus = 1;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "HackathonManager: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums ──────────────────────────────────────────────────────────
    enum HackathonStatus { Registration, Active, Judging, Completed, Cancelled }

    // ─── Structs ────────────────────────────────────────────────────────
    struct Hackathon {
        uint256 id;
        address organizer;
        string name;
        uint256 prizePool;
        uint256 maxTeams;
        uint256 deadline;
        HackathonStatus status;
        uint256 teamCount;
        uint256 createdAt;
    }

    struct Team {
        uint256 id;
        uint256 hackathonId;
        string name;
        address lead;
        address[] members;
        bytes32 projectHash;
        uint256 totalScore;
        uint256 judgeCount;
        bool submitted;
        uint256 registeredAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public hackathonCount;
    uint256 public teamCount;

    mapping(uint256 => Hackathon) public hackathons;
    mapping(uint256 => Team) public teams;
    mapping(uint256 => uint256[]) public hackathonTeams;
    mapping(uint256 => mapping(address => bool)) public isJudge;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public hasJudged;
    mapping(address => uint256[]) public userTeams;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a hackathon is created
    event HackathonCreated(uint256 indexed hackathonId, string name, uint256 prizePool, uint256 maxTeams, uint256 deadline);
    /// @notice Emitted when a team registers
    event TeamRegistered(uint256 indexed teamId, uint256 indexed hackathonId, string name, address indexed lead);
    /// @notice Emitted when a project is submitted
    event ProjectSubmitted(uint256 indexed teamId, uint256 indexed hackathonId, bytes32 projectHash);
    /// @notice Emitted when a project is judged
    event ProjectJudged(uint256 indexed teamId, uint256 indexed hackathonId, address indexed judge, uint256 score);
    /// @notice Emitted when prizes are distributed
    event PrizesDistributed(uint256 indexed hackathonId, uint256 indexed winnerTeamId, uint256 prize);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Create a new hackathon with prize pool
     * @param name Hackathon name
     * @param maxTeams Maximum number of teams
     * @param deadline Submission deadline timestamp
     */
    function createHackathon(
        string calldata name,
        uint256 maxTeams,
        uint256 deadline
    ) external payable whenNotPaused {
        require(bytes(name).length > 0 && bytes(name).length <= 128, "HackathonManager: invalid name");
        require(msg.value > 0, "HackathonManager: prize required");
        require(maxTeams > 0 && maxTeams <= 500, "HackathonManager: invalid max teams");
        require(deadline > block.timestamp, "HackathonManager: deadline past");

        hackathonCount++;
        hackathons[hackathonCount] = Hackathon({
            id: hackathonCount,
            organizer: msg.sender,
            name: name,
            prizePool: msg.value,
            maxTeams: maxTeams,
            deadline: deadline,
            status: HackathonStatus.Registration,
            teamCount: 0,
            createdAt: block.timestamp
        });

        emit HackathonCreated(hackathonCount, name, msg.value, maxTeams, deadline);
    }

    /**
     * @notice Add a judge to a hackathon
     * @param hackathonId Hackathon ID
     * @param judge Judge address
     */
    function addJudge(uint256 hackathonId, address judge) external {
        require(msg.sender == hackathons[hackathonId].organizer, "HackathonManager: not organizer");
        isJudge[hackathonId][judge] = true;
    }

    /**
     * @notice Register a team for a hackathon
     * @param hackathonId Hackathon to join
     * @param name Team name
     * @param members Array of team member addresses
     */
    function registerTeam(
        uint256 hackathonId,
        string calldata name,
        address[] calldata members
    ) external whenNotPaused {
        Hackathon storage h = hackathons[hackathonId];
        require(h.status == HackathonStatus.Registration, "HackathonManager: not in registration");
        require(h.teamCount < h.maxTeams, "HackathonManager: max teams reached");
        require(bytes(name).length > 0, "HackathonManager: empty name");
        require(members.length > 0 && members.length <= 10, "HackathonManager: invalid member count");

        teamCount++;
        teams[teamCount] = Team({
            id: teamCount,
            hackathonId: hackathonId,
            name: name,
            lead: msg.sender,
            members: members,
            projectHash: bytes32(0),
            totalScore: 0,
            judgeCount: 0,
            submitted: false,
            registeredAt: block.timestamp
        });

        h.teamCount++;
        hackathonTeams[hackathonId].push(teamCount);
        userTeams[msg.sender].push(teamCount);

        emit TeamRegistered(teamCount, hackathonId, name, msg.sender);
    }

    /**
     * @notice Start the hackathon (move to active phase)
     * @param hackathonId Hackathon to start
     */
    function startHackathon(uint256 hackathonId) external {
        Hackathon storage h = hackathons[hackathonId];
        require(msg.sender == h.organizer, "HackathonManager: not organizer");
        require(h.status == HackathonStatus.Registration, "HackathonManager: not in registration");
        h.status = HackathonStatus.Active;
    }

    /**
     * @notice Submit a project for a team
     * @param hackathonId Hackathon ID
     * @param projectHash Hash of the project submission
     */
    function submitProject(uint256 hackathonId, bytes32 projectHash) external whenNotPaused {
        Hackathon storage h = hackathons[hackathonId];
        require(h.status == HackathonStatus.Active, "HackathonManager: not active");
        require(block.timestamp <= h.deadline, "HackathonManager: deadline passed");
        require(projectHash != bytes32(0), "HackathonManager: empty hash");

        // Find team by lead
        uint256[] storage tIds = hackathonTeams[hackathonId];
        uint256 teamId = 0;
        for (uint256 i = 0; i < tIds.length; i++) {
            if (teams[tIds[i]].lead == msg.sender) {
                teamId = tIds[i];
                break;
            }
        }
        require(teamId > 0, "HackathonManager: team not found");

        Team storage team = teams[teamId];
        require(!team.submitted, "HackathonManager: already submitted");

        team.projectHash = projectHash;
        team.submitted = true;

        emit ProjectSubmitted(teamId, hackathonId, projectHash);
    }

    /**
     * @notice Start judging phase
     * @param hackathonId Hackathon ID
     */
    function startJudging(uint256 hackathonId) external {
        Hackathon storage h = hackathons[hackathonId];
        require(msg.sender == h.organizer, "HackathonManager: not organizer");
        require(h.status == HackathonStatus.Active, "HackathonManager: not active");
        h.status = HackathonStatus.Judging;
    }

    /**
     * @notice Judge a team's project (score 0-100)
     * @param hackathonId Hackathon ID
     * @param teamId Team to judge
     * @param score Score (0-100)
     */
    function judgeProject(uint256 hackathonId, uint256 teamId, uint256 score) external {
        require(isJudge[hackathonId][msg.sender], "HackathonManager: not judge");
        require(hackathons[hackathonId].status == HackathonStatus.Judging, "HackathonManager: not judging");
        require(score <= 100, "HackathonManager: invalid score");
        require(!hasJudged[hackathonId][teamId][msg.sender], "HackathonManager: already judged");
        require(teams[teamId].submitted, "HackathonManager: no submission");

        hasJudged[hackathonId][teamId][msg.sender] = true;
        teams[teamId].totalScore += score;
        teams[teamId].judgeCount++;

        emit ProjectJudged(teamId, hackathonId, msg.sender, score);
    }

    /**
     * @notice Distribute prizes to the winning team
     * @param hackathonId Hackathon ID
     * @param winnerTeamId Winning team ID
     */
    function distributePrizes(uint256 hackathonId, uint256 winnerTeamId) external nonReentrant {
        Hackathon storage h = hackathons[hackathonId];
        require(msg.sender == h.organizer, "HackathonManager: not organizer");
        require(h.status == HackathonStatus.Judging, "HackathonManager: not in judging");

        Team storage winner = teams[winnerTeamId];
        require(winner.hackathonId == hackathonId, "HackathonManager: wrong hackathon");

        h.status = HackathonStatus.Completed;
        uint256 prize = h.prizePool;
        h.prizePool = 0;

        (bool success, ) = payable(winner.lead).call{value: prize}("");
        require(success, "HackathonManager: payment failed");

        emit PrizesDistributed(hackathonId, winnerTeamId, prize);
    }

    /**
     * @notice Get teams for a hackathon
     * @param hackathonId Hackathon ID
     * @return teamIds Array of team IDs
     */
    function getHackathonTeams(uint256 hackathonId) external view returns (uint256[] memory teamIds) {
        return hackathonTeams[hackathonId];
    }

    /**
     * @notice Get team members
     * @param teamId Team ID
     * @return members Array of member addresses
     */
    function getTeamMembers(uint256 teamId) external view returns (address[] memory members) {
        return teams[teamId].members;
    }
}
