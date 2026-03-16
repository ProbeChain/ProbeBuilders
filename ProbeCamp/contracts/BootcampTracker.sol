// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title BootcampTracker
 * @author ProbeChain Team
 * @notice On-chain bootcamp progress tracking with certificate issuance
 * @dev Tracks courses, modules, student enrollment, and completion certificates
 */
contract BootcampTracker {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "BootcampTracker: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "BootcampTracker: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "BootcampTracker: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Structs ────────────────────────────────────────────────────────
    struct Course {
        uint256 id;
        address instructor;
        string title;
        uint256 moduleCount;
        uint256 certificateReward;
        uint256 enrolledCount;
        uint256 graduatedCount;
        uint256 createdAt;
        bool active;
    }

    struct StudentProgress {
        bool enrolled;
        uint256 completedModules;
        bool certified;
        uint256 enrolledAt;
        uint256 certifiedAt;
    }

    struct ModuleCompletion {
        bytes32 proofHash;
        uint256 completedAt;
        bool verified;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public courseCount;
    uint256 public totalCertificates;

    mapping(uint256 => Course) public courses;
    mapping(uint256 => string[]) public courseModules;
    mapping(uint256 => mapping(address => StudentProgress)) public studentProgress;
    mapping(uint256 => mapping(address => mapping(uint256 => ModuleCompletion))) public moduleCompletions;
    mapping(address => uint256[]) public studentCourses;
    mapping(address => uint256) public certificateCount;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a new course is created
    event CourseCreated(uint256 indexed courseId, address indexed instructor, string title, uint256 moduleCount);
    /// @notice Emitted when a student enrolls
    event StudentEnrolled(uint256 indexed courseId, address indexed student);
    /// @notice Emitted when a module is completed
    event ModuleCompleted(uint256 indexed courseId, address indexed student, uint256 moduleIndex, bytes32 proofHash);
    /// @notice Emitted when a certificate is issued
    event CertificateIssued(uint256 indexed courseId, address indexed student, uint256 timestamp);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Create a new bootcamp course
     * @param title Course title
     * @param modules Array of module names
     * @param certificateReward Token reward for completion (informational)
     */
    function createCourse(
        string calldata title,
        string[] calldata modules,
        uint256 certificateReward
    ) external whenNotPaused {
        require(bytes(title).length > 0 && bytes(title).length <= 128, "BootcampTracker: invalid title");
        require(modules.length > 0 && modules.length <= 50, "BootcampTracker: invalid module count");

        courseCount++;
        courses[courseCount] = Course({
            id: courseCount,
            instructor: msg.sender,
            title: title,
            moduleCount: modules.length,
            certificateReward: certificateReward,
            enrolledCount: 0,
            graduatedCount: 0,
            createdAt: block.timestamp,
            active: true
        });

        for (uint256 i = 0; i < modules.length; i++) {
            courseModules[courseCount].push(modules[i]);
        }

        emit CourseCreated(courseCount, msg.sender, title, modules.length);
    }

    /**
     * @notice Enroll a student in a course
     * @param courseId Course to enroll in
     */
    function enrollStudent(uint256 courseId) external whenNotPaused {
        Course storage course = courses[courseId];
        require(course.active, "BootcampTracker: course not active");

        StudentProgress storage progress = studentProgress[courseId][msg.sender];
        require(!progress.enrolled, "BootcampTracker: already enrolled");

        progress.enrolled = true;
        progress.enrolledAt = block.timestamp;
        course.enrolledCount++;
        studentCourses[msg.sender].push(courseId);

        emit StudentEnrolled(courseId, msg.sender);
    }

    /**
     * @notice Complete a module with proof of work
     * @param courseId Course ID
     * @param moduleIndex Index of the module (0-based)
     * @param proofHash Hash of the completion proof
     */
    function completeModule(
        uint256 courseId,
        uint256 moduleIndex,
        bytes32 proofHash
    ) external whenNotPaused {
        Course storage course = courses[courseId];
        require(course.active, "BootcampTracker: course not active");
        require(moduleIndex < course.moduleCount, "BootcampTracker: invalid module");

        StudentProgress storage progress = studentProgress[courseId][msg.sender];
        require(progress.enrolled, "BootcampTracker: not enrolled");
        require(!progress.certified, "BootcampTracker: already certified");
        require(proofHash != bytes32(0), "BootcampTracker: empty proof");

        ModuleCompletion storage completion = moduleCompletions[courseId][msg.sender][moduleIndex];
        require(!completion.verified, "BootcampTracker: module already completed");

        completion.proofHash = proofHash;
        completion.completedAt = block.timestamp;
        completion.verified = true;
        progress.completedModules++;

        emit ModuleCompleted(courseId, msg.sender, moduleIndex, proofHash);
    }

    /**
     * @notice Issue a certificate to a student who completed all modules
     * @param courseId Course ID
     * @param student Student address
     */
    function issueCertificate(uint256 courseId, address student) external {
        Course storage course = courses[courseId];
        require(msg.sender == course.instructor, "BootcampTracker: not instructor");

        StudentProgress storage progress = studentProgress[courseId][student];
        require(progress.enrolled, "BootcampTracker: not enrolled");
        require(!progress.certified, "BootcampTracker: already certified");
        require(
            progress.completedModules == course.moduleCount,
            "BootcampTracker: modules incomplete"
        );

        progress.certified = true;
        progress.certifiedAt = block.timestamp;
        course.graduatedCount++;
        totalCertificates++;
        certificateCount[student]++;

        emit CertificateIssued(courseId, student, block.timestamp);
    }

    /**
     * @notice Check if a student is certified for a course
     * @param courseId Course ID
     * @param student Student address
     * @return certified Whether the student has a certificate
     */
    function isCertified(uint256 courseId, address student) external view returns (bool certified) {
        return studentProgress[courseId][student].certified;
    }

    /**
     * @notice Get student progress for a course
     * @param courseId Course ID
     * @param student Student address
     * @return enrolled Whether enrolled
     * @return completedModules Number of completed modules
     * @return totalModules Total modules in the course
     * @return certified Whether certified
     */
    function getProgress(uint256 courseId, address student) external view returns (
        bool enrolled,
        uint256 completedModules,
        uint256 totalModules,
        bool certified
    ) {
        StudentProgress storage p = studentProgress[courseId][student];
        return (p.enrolled, p.completedModules, courses[courseId].moduleCount, p.certified);
    }

    /**
     * @notice Get module names for a course
     * @param courseId Course ID
     * @return modules Array of module names
     */
    function getModules(uint256 courseId) external view returns (string[] memory modules) {
        return courseModules[courseId];
    }

    /**
     * @notice Deactivate a course
     * @param courseId Course to deactivate
     */
    function deactivateCourse(uint256 courseId) external {
        require(
            courses[courseId].instructor == msg.sender || msg.sender == _owner,
            "BootcampTracker: unauthorized"
        );
        courses[courseId].active = false;
    }
}
