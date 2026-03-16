// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CourseMarket
 * @author ProbeChain Team
 * @notice Decentralized course marketplace with enrollment and rating system
 * @dev Instructors publish courses, students enroll with payment, rate after completion
 */
contract CourseMarket {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "CourseMarket: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "CourseMarket: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _guardStatus = 1;
    modifier nonReentrant() {
        require(_guardStatus == 1, "CourseMarket: reentrant call");
        _guardStatus = 2;
        _;
        _guardStatus = 1;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "CourseMarket: paused"); _; }
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
        bytes32 contentHash;
        uint256 price;
        string category;
        uint256 enrolledCount;
        uint256 completedCount;
        uint256 totalRating;
        uint256 ratingCount;
        uint256 revenue;
        uint256 createdAt;
        bool active;
    }

    struct Enrollment {
        bool enrolled;
        bool completed;
        bool rated;
        uint256 enrolledAt;
        uint256 completedAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public courseCount;
    uint256 public platformFeePercent = 3;
    uint256 public collectedFees;

    mapping(uint256 => Course) public courses;
    mapping(uint256 => mapping(address => Enrollment)) public enrollments;
    mapping(address => uint256[]) public instructorCourses;
    mapping(address => uint256[]) public studentEnrollments;
    mapping(string => uint256[]) public categoryCourses;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a course is published
    event CoursePublished(uint256 indexed courseId, address indexed instructor, string title, uint256 price, string category);
    /// @notice Emitted when a student enrolls
    event StudentEnrolled(uint256 indexed courseId, address indexed student, uint256 pricePaid);
    /// @notice Emitted when a student completes a course
    event CourseCompleted(uint256 indexed courseId, address indexed student);
    /// @notice Emitted when a course is rated
    event CourseRated(uint256 indexed courseId, address indexed student, uint256 score);
    /// @notice Emitted when instructor withdraws revenue
    event RevenueWithdrawn(address indexed instructor, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Publish a new course
     * @param title Course title
     * @param contentHash Hash of course content (IPFS)
     * @param price Enrollment price in wei
     * @param category Course category string
     */
    function publishCourse(
        string calldata title,
        bytes32 contentHash,
        uint256 price,
        string calldata category
    ) external whenNotPaused {
        require(bytes(title).length > 0 && bytes(title).length <= 128, "CourseMarket: invalid title");
        require(contentHash != bytes32(0), "CourseMarket: empty content hash");
        require(bytes(category).length > 0, "CourseMarket: empty category");

        courseCount++;
        courses[courseCount] = Course({
            id: courseCount,
            instructor: msg.sender,
            title: title,
            contentHash: contentHash,
            price: price,
            category: category,
            enrolledCount: 0,
            completedCount: 0,
            totalRating: 0,
            ratingCount: 0,
            revenue: 0,
            createdAt: block.timestamp,
            active: true
        });

        instructorCourses[msg.sender].push(courseCount);
        categoryCourses[category].push(courseCount);

        emit CoursePublished(courseCount, msg.sender, title, price, category);
    }

    /**
     * @notice Enroll in a course
     * @param courseId Course to enroll in
     */
    function enrollInCourse(uint256 courseId) external payable whenNotPaused nonReentrant {
        Course storage course = courses[courseId];
        require(course.active, "CourseMarket: course not active");
        require(msg.value >= course.price, "CourseMarket: insufficient payment");

        Enrollment storage e = enrollments[courseId][msg.sender];
        require(!e.enrolled, "CourseMarket: already enrolled");

        e.enrolled = true;
        e.enrolledAt = block.timestamp;
        course.enrolledCount++;

        if (course.price > 0) {
            uint256 fee = (msg.value * platformFeePercent) / 100;
            collectedFees += fee;
            course.revenue += msg.value - fee;
        }

        studentEnrollments[msg.sender].push(courseId);
        emit StudentEnrolled(courseId, msg.sender, msg.value);
    }

    /**
     * @notice Mark a student as having completed a course (instructor only)
     * @param courseId Course ID
     * @param student Student address
     */
    function completeCourse(uint256 courseId, address student) external {
        Course storage course = courses[courseId];
        require(msg.sender == course.instructor, "CourseMarket: not instructor");

        Enrollment storage e = enrollments[courseId][student];
        require(e.enrolled, "CourseMarket: not enrolled");
        require(!e.completed, "CourseMarket: already completed");

        e.completed = true;
        e.completedAt = block.timestamp;
        course.completedCount++;

        emit CourseCompleted(courseId, student);
    }

    /**
     * @notice Rate a completed course (1-5)
     * @param courseId Course ID
     * @param score Rating (1-5)
     */
    function rateCourse(uint256 courseId, uint256 score) external {
        require(score >= 1 && score <= 5, "CourseMarket: invalid score");

        Enrollment storage e = enrollments[courseId][msg.sender];
        require(e.completed, "CourseMarket: not completed");
        require(!e.rated, "CourseMarket: already rated");

        e.rated = true;
        courses[courseId].totalRating += score;
        courses[courseId].ratingCount++;

        emit CourseRated(courseId, msg.sender, score);
    }

    /**
     * @notice Get top courses by enrollment count (up to 10)
     * @param category Category to filter by
     * @return ids Array of course IDs
     */
    function getTopCourses(string calldata category) external view returns (uint256[] memory ids) {
        uint256[] storage catCourses = categoryCourses[category];
        uint256 len = catCourses.length > 10 ? 10 : catCourses.length;
        ids = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            ids[i] = catCourses[catCourses.length - 1 - i];
        }
    }

    /**
     * @notice Withdraw instructor revenue
     */
    function withdrawRevenue() external nonReentrant {
        uint256 total = 0;
        uint256[] storage myCourses = instructorCourses[msg.sender];

        for (uint256 i = 0; i < myCourses.length; i++) {
            Course storage c = courses[myCourses[i]];
            total += c.revenue;
            c.revenue = 0;
        }

        require(total > 0, "CourseMarket: no revenue");
        (bool success, ) = payable(msg.sender).call{value: total}("");
        require(success, "CourseMarket: withdrawal failed");

        emit RevenueWithdrawn(msg.sender, total);
    }

    /**
     * @notice Withdraw platform fees
     * @param to Recipient address
     */
    function withdrawFees(address to) external onlyOwner nonReentrant {
        uint256 amount = collectedFees;
        collectedFees = 0;
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "CourseMarket: withdrawal failed");
    }

    /**
     * @notice Get average rating for a course
     * @param courseId Course ID
     * @return avg Average rating x100
     */
    function getAverageRating(uint256 courseId) external view returns (uint256 avg) {
        Course storage c = courses[courseId];
        if (c.ratingCount == 0) return 0;
        return (c.totalRating * 100) / c.ratingCount;
    }
}
