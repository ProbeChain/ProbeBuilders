// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MentorPlatform
 * @author ProbeChain Team
 * @notice Decentralized mentorship matching with escrow payments and ratings
 * @dev Mentors register skills/rates, mentees request and pay for mentorship sessions
 */
contract MentorPlatform {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "MentorPlatform: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "MentorPlatform: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _guardStatus = 1;
    modifier nonReentrant() {
        require(_guardStatus == 1, "MentorPlatform: reentrant call");
        _guardStatus = 2;
        _;
        _guardStatus = 1;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "MentorPlatform: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums ──────────────────────────────────────────────────────────
    enum RequestStatus { Open, Matched, Active, Completed, Cancelled }

    // ─── Structs ────────────────────────────────────────────────────────
    struct Mentor {
        address wallet;
        string[] skills;
        uint256 hourlyRate;
        uint256 totalSessions;
        uint256 totalRating;
        uint256 ratingCount;
        uint256 registeredAt;
        bool active;
    }

    struct MentorRequest {
        uint256 id;
        address mentee;
        string skill;
        uint256 budget;
        RequestStatus status;
        address matchedMentor;
        uint256 createdAt;
        uint256 completedAt;
    }

    struct Mentorship {
        uint256 id;
        uint256 requestId;
        address mentor;
        address mentee;
        uint256 payment;
        bool mentorConfirmed;
        bool menteeConfirmed;
        uint256 startedAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public requestCount;
    uint256 public mentorshipCount;
    uint256 public mentorCount;
    uint256 public platformFeePercent = 5;
    uint256 public collectedFees;

    mapping(address => Mentor) public mentors;
    mapping(uint256 => MentorRequest) public requests;
    mapping(uint256 => Mentorship) public mentorships;
    mapping(string => address[]) public skillMentors;
    mapping(address => uint256[]) public menteeRequests;
    mapping(address => uint256[]) public mentorSessions;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a mentor registers
    event MentorRegistered(address indexed mentor, uint256 hourlyRate, uint256 skillCount);
    /// @notice Emitted when a mentorship request is created
    event MentorRequested(uint256 indexed requestId, address indexed mentee, string skill, uint256 budget);
    /// @notice Emitted when a mentor accepts a request
    event MentorshipAccepted(uint256 indexed mentorshipId, uint256 indexed requestId, address indexed mentor);
    /// @notice Emitted when a mentorship is completed
    event MentorshipCompleted(uint256 indexed mentorshipId, address indexed mentor, address indexed mentee, uint256 payment);
    /// @notice Emitted when a mentor is rated
    event MentorRated(address indexed mentor, address indexed mentee, uint256 score);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register as a mentor with skills and hourly rate
     * @param skills Array of skill strings
     * @param hourlyRate Rate per hour in wei
     */
    function registerMentor(
        string[] calldata skills,
        uint256 hourlyRate
    ) external whenNotPaused {
        require(skills.length > 0 && skills.length <= 10, "MentorPlatform: invalid skills");
        require(hourlyRate > 0, "MentorPlatform: zero rate");
        require(mentors[msg.sender].registeredAt == 0, "MentorPlatform: already registered");

        mentorCount++;
        Mentor storage m = mentors[msg.sender];
        m.wallet = msg.sender;
        m.hourlyRate = hourlyRate;
        m.registeredAt = block.timestamp;
        m.active = true;

        for (uint256 i = 0; i < skills.length; i++) {
            m.skills.push(skills[i]);
            skillMentors[skills[i]].push(msg.sender);
        }

        emit MentorRegistered(msg.sender, hourlyRate, skills.length);
    }

    /**
     * @notice Request a mentor for a specific skill
     * @param skill Skill needed
     */
    function requestMentor(
        string calldata skill
    ) external payable whenNotPaused {
        require(bytes(skill).length > 0, "MentorPlatform: empty skill");
        require(msg.value > 0, "MentorPlatform: budget required");

        requestCount++;
        requests[requestCount] = MentorRequest({
            id: requestCount,
            mentee: msg.sender,
            skill: skill,
            budget: msg.value,
            status: RequestStatus.Open,
            matchedMentor: address(0),
            createdAt: block.timestamp,
            completedAt: 0
        });

        menteeRequests[msg.sender].push(requestCount);
        emit MentorRequested(requestCount, msg.sender, skill, msg.value);
    }

    /**
     * @notice Accept a mentorship request
     * @param requestId Request to accept
     */
    function acceptMentorship(uint256 requestId) external whenNotPaused {
        MentorRequest storage req = requests[requestId];
        require(req.status == RequestStatus.Open, "MentorPlatform: not open");
        require(mentors[msg.sender].active, "MentorPlatform: not active mentor");

        req.status = RequestStatus.Active;
        req.matchedMentor = msg.sender;

        mentorshipCount++;
        mentorships[mentorshipCount] = Mentorship({
            id: mentorshipCount,
            requestId: requestId,
            mentor: msg.sender,
            mentee: req.mentee,
            payment: req.budget,
            mentorConfirmed: false,
            menteeConfirmed: false,
            startedAt: block.timestamp
        });

        mentorSessions[msg.sender].push(mentorshipCount);
        emit MentorshipAccepted(mentorshipCount, requestId, msg.sender);
    }

    /**
     * @notice Complete a mentorship (both parties must confirm)
     * @param mentorshipId Mentorship to complete
     */
    function completeMentorship(uint256 mentorshipId) external nonReentrant {
        Mentorship storage ms = mentorships[mentorshipId];
        require(
            msg.sender == ms.mentor || msg.sender == ms.mentee,
            "MentorPlatform: not participant"
        );

        if (msg.sender == ms.mentor) {
            ms.mentorConfirmed = true;
        } else {
            ms.menteeConfirmed = true;
        }

        if (ms.mentorConfirmed && ms.menteeConfirmed) {
            MentorRequest storage req = requests[ms.requestId];
            req.status = RequestStatus.Completed;
            req.completedAt = block.timestamp;

            uint256 fee = (ms.payment * platformFeePercent) / 100;
            collectedFees += fee;
            uint256 payout = ms.payment - fee;

            mentors[ms.mentor].totalSessions++;

            (bool success, ) = payable(ms.mentor).call{value: payout}("");
            require(success, "MentorPlatform: payment failed");

            emit MentorshipCompleted(mentorshipId, ms.mentor, ms.mentee, payout);
        }
    }

    /**
     * @notice Rate a mentor after completed session (1-5)
     * @param mentorAddr Mentor address
     * @param score Rating (1-5)
     */
    function rateMentor(address mentorAddr, uint256 score) external {
        require(score >= 1 && score <= 5, "MentorPlatform: invalid score");
        Mentor storage m = mentors[mentorAddr];
        require(m.registeredAt > 0, "MentorPlatform: not a mentor");

        m.totalRating += score;
        m.ratingCount++;

        emit MentorRated(mentorAddr, msg.sender, score);
    }

    /**
     * @notice Get mentors for a skill
     * @param skill Skill to search
     * @return addrs Array of mentor addresses
     */
    function getMentorsBySkill(string calldata skill) external view returns (address[] memory addrs) {
        return skillMentors[skill];
    }

    /**
     * @notice Get mentor's skills
     * @param mentor Mentor address
     * @return skills Array of skill strings
     */
    function getMentorSkills(address mentor) external view returns (string[] memory skills) {
        return mentors[mentor].skills;
    }

    /**
     * @notice Get average mentor rating
     * @param mentor Mentor address
     * @return avg Average rating x100
     */
    function getMentorRating(address mentor) external view returns (uint256 avg) {
        Mentor storage m = mentors[mentor];
        if (m.ratingCount == 0) return 0;
        return (m.totalRating * 100) / m.ratingCount;
    }

    /**
     * @notice Withdraw platform fees
     * @param to Recipient
     */
    function withdrawFees(address to) external onlyOwner nonReentrant {
        uint256 amount = collectedFees;
        collectedFees = 0;
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "MentorPlatform: withdrawal failed");
    }
}
