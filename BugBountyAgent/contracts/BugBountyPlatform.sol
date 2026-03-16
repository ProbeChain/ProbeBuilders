// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title BugBountyPlatform
 * @author ProbeChain Team
 * @notice Decentralized bug bounty platform with severity-based rewards
 * @dev Supports program creation, bug submission, triage, and automated payouts
 */
contract BugBountyPlatform {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "BugBountyPlatform: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "BugBountyPlatform: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _guardStatus = 1;
    modifier nonReentrant() {
        require(_guardStatus == 1, "BugBountyPlatform: reentrant call");
        _guardStatus = 2;
        _;
        _guardStatus = 1;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "BugBountyPlatform: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums ──────────────────────────────────────────────────────────
    enum Severity { Info, Low, Medium, High, Critical }
    enum BugStatus { Submitted, Triaged, Accepted, Rejected, Paid }

    // ─── Structs ────────────────────────────────────────────────────────
    struct Program {
        uint256 id;
        address creator;
        string name;
        string scope;
        uint256 maxReward;
        uint256 balance;
        uint256 bugCount;
        uint256 paidCount;
        uint256 createdAt;
        bool active;
    }

    struct Bug {
        uint256 id;
        uint256 programId;
        address reporter;
        Severity severity;
        bytes32 reportHash;
        BugStatus status;
        uint256 reward;
        uint256 submittedAt;
        uint256 resolvedAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public programCount;
    uint256 public bugCount;

    mapping(uint256 => Program) public programs;
    mapping(uint256 => Bug) public bugs;
    mapping(uint256 => uint256[]) public programBugs;
    mapping(address => uint256[]) public reporterBugs;
    mapping(address => uint256) public reporterReputation;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a new bug bounty program is created
    event ProgramCreated(uint256 indexed programId, address indexed creator, string name, uint256 maxReward);
    /// @notice Emitted when a bug report is submitted
    event BugSubmitted(uint256 indexed bugId, uint256 indexed programId, address indexed reporter, Severity severity);
    /// @notice Emitted when a bug is triaged
    event BugTriaged(uint256 indexed bugId, bool accepted, uint256 reward);
    /// @notice Emitted when a bounty is paid
    event BountyPaid(uint256 indexed bugId, address indexed reporter, uint256 amount);
    /// @notice Emitted when a program receives additional funding
    event ProgramFunded(uint256 indexed programId, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Create a new bug bounty program
     * @param name Program name
     * @param scope Description of what's in scope
     * @param maxReward Maximum reward per bug
     */
    function createProgram(
        string calldata name,
        string calldata scope,
        uint256 maxReward
    ) external payable whenNotPaused {
        require(bytes(name).length > 0 && bytes(name).length <= 64, "BugBountyPlatform: invalid name");
        require(bytes(scope).length > 0, "BugBountyPlatform: empty scope");
        require(msg.value > 0, "BugBountyPlatform: funding required");
        require(maxReward > 0 && maxReward <= msg.value, "BugBountyPlatform: invalid max reward");

        programCount++;
        programs[programCount] = Program({
            id: programCount,
            creator: msg.sender,
            name: name,
            scope: scope,
            maxReward: maxReward,
            balance: msg.value,
            bugCount: 0,
            paidCount: 0,
            createdAt: block.timestamp,
            active: true
        });

        emit ProgramCreated(programCount, msg.sender, name, maxReward);
    }

    /**
     * @notice Add more funds to a program
     * @param programId Program to fund
     */
    function fundProgram(uint256 programId) external payable {
        require(msg.value > 0, "BugBountyPlatform: zero amount");
        programs[programId].balance += msg.value;
        emit ProgramFunded(programId, msg.value);
    }

    /**
     * @notice Submit a bug report
     * @param programId Program the bug is for
     * @param severity Bug severity level
     * @param reportHash Hash of the detailed bug report
     */
    function submitBug(
        uint256 programId,
        Severity severity,
        bytes32 reportHash
    ) external whenNotPaused {
        Program storage p = programs[programId];
        require(p.active, "BugBountyPlatform: program not active");
        require(reportHash != bytes32(0), "BugBountyPlatform: empty report");
        require(msg.sender != p.creator, "BugBountyPlatform: creator cannot report");

        bugCount++;
        bugs[bugCount] = Bug({
            id: bugCount,
            programId: programId,
            reporter: msg.sender,
            severity: severity,
            reportHash: reportHash,
            status: BugStatus.Submitted,
            reward: 0,
            submittedAt: block.timestamp,
            resolvedAt: 0
        });

        p.bugCount++;
        programBugs[programId].push(bugCount);
        reporterBugs[msg.sender].push(bugCount);

        emit BugSubmitted(bugCount, programId, msg.sender, severity);
    }

    /**
     * @notice Triage a submitted bug (accept or reject with reward amount)
     * @param bugId Bug to triage
     * @param accepted Whether the bug is accepted
     * @param reward Reward amount if accepted
     */
    function triageBug(uint256 bugId, bool accepted, uint256 reward) external {
        Bug storage bug = bugs[bugId];
        Program storage p = programs[bug.programId];
        require(msg.sender == p.creator, "BugBountyPlatform: not program creator");
        require(bug.status == BugStatus.Submitted, "BugBountyPlatform: not submitted");

        if (accepted) {
            require(reward > 0 && reward <= p.maxReward, "BugBountyPlatform: invalid reward");
            require(reward <= p.balance, "BugBountyPlatform: insufficient balance");
            bug.status = BugStatus.Accepted;
            bug.reward = reward;
        } else {
            bug.status = BugStatus.Rejected;
        }

        bug.resolvedAt = block.timestamp;
        emit BugTriaged(bugId, accepted, reward);
    }

    /**
     * @notice Pay the bounty for an accepted bug
     * @param bugId Bug to pay for
     */
    function payBounty(uint256 bugId) external nonReentrant {
        Bug storage bug = bugs[bugId];
        Program storage p = programs[bug.programId];
        require(msg.sender == p.creator, "BugBountyPlatform: not program creator");
        require(bug.status == BugStatus.Accepted, "BugBountyPlatform: not accepted");

        bug.status = BugStatus.Paid;
        p.balance -= bug.reward;
        p.paidCount++;
        reporterReputation[bug.reporter]++;

        (bool success, ) = payable(bug.reporter).call{value: bug.reward}("");
        require(success, "BugBountyPlatform: payment failed");

        emit BountyPaid(bugId, bug.reporter, bug.reward);
    }

    /**
     * @notice Close a program and withdraw remaining funds
     * @param programId Program to close
     */
    function closeProgram(uint256 programId) external nonReentrant {
        Program storage p = programs[programId];
        require(msg.sender == p.creator, "BugBountyPlatform: not creator");
        require(p.active, "BugBountyPlatform: already closed");

        p.active = false;
        uint256 remaining = p.balance;
        p.balance = 0;

        if (remaining > 0) {
            (bool success, ) = payable(msg.sender).call{value: remaining}("");
            require(success, "BugBountyPlatform: withdrawal failed");
        }
    }

    /**
     * @notice Get bugs for a program
     * @param programId Program ID
     * @return ids Array of bug IDs
     */
    function getProgramBugs(uint256 programId) external view returns (uint256[] memory ids) {
        return programBugs[programId];
    }

    /**
     * @notice Get reporter's bug history
     * @param reporter Reporter address
     * @return ids Array of bug IDs
     */
    function getReporterBugs(address reporter) external view returns (uint256[] memory ids) {
        return reporterBugs[reporter];
    }
}
