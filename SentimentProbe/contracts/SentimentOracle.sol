// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SentimentOracle
 * @author ProbeBuilders
 * @notice Decentralized market sentiment oracle with reputation-weighted scoring
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */
contract SentimentOracle {
    // ─── Ownership ───────────────────────────────────────────────────
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "SentimentOracle: not owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "SentimentOracle: zero address");
        owner = newOwner;
    }

    // ─── Pausable ────────────────────────────────────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "SentimentOracle: paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ─── Reentrancy Guard ────────────────────────────────────────────
    uint256 private _status = 1;
    modifier nonReentrant() { require(_status != 2, "SentimentOracle: reentrant"); _status = 2; _; _status = 1; }

    // ─── Structs ─────────────────────────────────────────────────────

    /// @notice A sentiment data feed (e.g., "BTC/USD Sentiment", "ETH Market Fear")
    struct Feed {
        string name;
        string description;
        address creator;
        uint256 submissionCount;
        uint256 weightedScoreSum;  // sum of (score * reputation)
        uint256 weightedConfSum;   // sum of (confidence * reputation)
        uint256 totalWeight;       // sum of reputations
        uint256 lastUpdated;
        bool active;
    }

    /// @notice Reporter profile with staking and reputation
    struct Reporter {
        uint256 stake;
        uint256 reputation;        // 0-1000 (starts at 100)
        uint256 totalSubmissions;
        uint256 accurateSubmissions;
        uint256 joinedAt;
        bool active;
    }

    /// @notice A single sentiment submission
    struct Submission {
        uint256 feedId;
        address reporter;
        int256 score;              // -100 (extreme bearish) to +100 (extreme bullish)
        uint256 confidence;        // 0-100
        uint256 reporterReputation; // reputation at time of submission
        uint256 timestamp;
    }

    // ─── State ───────────────────────────────────────────────────────
    uint256 public nextFeedId = 1;
    uint256 public nextSubmissionId = 1;
    uint256 public minStake = 0.01 ether;
    uint256 public constant INITIAL_REPUTATION = 100;
    uint256 public constant MAX_REPUTATION = 1000;
    uint256 public constant SUBMISSION_COOLDOWN = 5 minutes;

    mapping(uint256 => Feed) public feeds;
    mapping(address => Reporter) public reporters;
    mapping(uint256 => Submission) public submissions;
    mapping(uint256 => uint256[]) public feedSubmissions; // feedId => submissionIds
    mapping(uint256 => mapping(address => uint256)) public lastSubmissionTime; // feedId => reporter => timestamp

    // ─── Events ──────────────────────────────────────────────────────
    event FeedCreated(uint256 indexed feedId, string name, address indexed creator);
    event FeedDeactivated(uint256 indexed feedId);
    event ReporterStaked(address indexed reporter, uint256 amount, uint256 totalStake);
    event ReporterUnstaked(address indexed reporter, uint256 amount);
    event SentimentSubmitted(
        uint256 indexed submissionId,
        uint256 indexed feedId,
        address indexed reporter,
        int256 score,
        uint256 confidence
    );
    event ReputationUpdated(address indexed reporter, uint256 oldReputation, uint256 newReputation);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
    }

    // ─── Feed Management ─────────────────────────────────────────────

    /// @notice Create a new sentiment feed
    /// @param name Feed name (e.g., "BTC Market Sentiment")
    /// @param description Brief description of what the feed tracks
    function createFeed(string calldata name, string calldata description) external whenNotPaused {
        require(bytes(name).length > 0 && bytes(name).length <= 64, "SentimentOracle: invalid name");
        require(bytes(description).length > 0 && bytes(description).length <= 256, "SentimentOracle: invalid desc");

        uint256 feedId = nextFeedId++;
        feeds[feedId] = Feed({
            name: name,
            description: description,
            creator: msg.sender,
            submissionCount: 0,
            weightedScoreSum: 0,
            weightedConfSum: 0,
            totalWeight: 0,
            lastUpdated: block.timestamp,
            active: true
        });

        emit FeedCreated(feedId, name, msg.sender);
    }

    /// @notice Deactivate a feed (owner or feed creator)
    function deactivateFeed(uint256 feedId) external {
        Feed storage feed = feeds[feedId];
        require(feed.active, "SentimentOracle: feed not active");
        require(msg.sender == owner || msg.sender == feed.creator, "SentimentOracle: not authorized");
        feed.active = false;
        emit FeedDeactivated(feedId);
    }

    // ─── Reporter Management ─────────────────────────────────────────

    /// @notice Stake native tokens to become a reporter
    function stakeAsReporter() external payable whenNotPaused {
        require(msg.value >= minStake, "SentimentOracle: insufficient stake");

        Reporter storage reporter = reporters[msg.sender];
        if (!reporter.active) {
            reporter.reputation = INITIAL_REPUTATION;
            reporter.joinedAt = block.timestamp;
            reporter.active = true;
        }
        reporter.stake += msg.value;

        emit ReporterStaked(msg.sender, msg.value, reporter.stake);
    }

    /// @notice Withdraw stake (deactivates reporter if full withdrawal)
    /// @param amount Amount to unstake
    function unstake(uint256 amount) external nonReentrant {
        Reporter storage reporter = reporters[msg.sender];
        require(reporter.active, "SentimentOracle: not a reporter");
        require(amount > 0 && amount <= reporter.stake, "SentimentOracle: invalid amount");

        reporter.stake -= amount;
        if (reporter.stake < minStake) {
            reporter.active = false;
        }

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "SentimentOracle: unstake failed");

        emit ReporterUnstaked(msg.sender, amount);
    }

    // ─── Sentiment Submission ────────────────────────────────────────

    /// @notice Submit a sentiment score for a feed
    /// @param feedId The feed to submit sentiment for
    /// @param score Sentiment score from -100 (bearish) to +100 (bullish)
    /// @param confidence Confidence level from 0 to 100
    function submitSentiment(uint256 feedId, int256 score, uint256 confidence) external whenNotPaused {
        require(reporters[msg.sender].active, "SentimentOracle: not active reporter");
        require(score >= -100 && score <= 100, "SentimentOracle: score out of range");
        require(confidence <= 100, "SentimentOracle: confidence out of range");

        Feed storage feed = feeds[feedId];
        require(feed.active, "SentimentOracle: feed not active");
        require(
            block.timestamp >= lastSubmissionTime[feedId][msg.sender] + SUBMISSION_COOLDOWN,
            "SentimentOracle: cooldown active"
        );

        Reporter storage reporter = reporters[msg.sender];
        uint256 rep = reporter.reputation;

        uint256 submissionId = nextSubmissionId++;
        submissions[submissionId] = Submission({
            feedId: feedId,
            reporter: msg.sender,
            score: score,
            confidence: confidence,
            reporterReputation: rep,
            timestamp: block.timestamp
        });
        feedSubmissions[feedId].push(submissionId);

        // Update weighted aggregates
        // Store score as shifted positive: score + 100 (0-200 range) to avoid signed math in aggregation
        uint256 shiftedScore = uint256(int256(score) + 100);
        feed.weightedScoreSum += shiftedScore * rep;
        feed.weightedConfSum += confidence * rep;
        feed.totalWeight += rep;
        feed.submissionCount++;
        feed.lastUpdated = block.timestamp;

        lastSubmissionTime[feedId][msg.sender] = block.timestamp;
        reporter.totalSubmissions++;

        emit SentimentSubmitted(submissionId, feedId, msg.sender, score, confidence);
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get the current weighted sentiment for a feed
    /// @param feedId The feed to query
    /// @return score Weighted average sentiment (-100 to +100)
    /// @return confidence Weighted average confidence (0-100)
    /// @return submissionCount Total number of submissions
    /// @return lastUpdated Timestamp of last update
    function getSentiment(uint256 feedId)
        external
        view
        returns (
            int256 score,
            uint256 confidence,
            uint256 submissionCount,
            uint256 lastUpdated
        )
    {
        Feed storage feed = feeds[feedId];
        if (feed.totalWeight == 0) {
            return (0, 0, 0, feed.lastUpdated);
        }

        // Reverse the shift: weighted average of (score+100), then subtract 100
        uint256 avgShifted = feed.weightedScoreSum / feed.totalWeight;
        score = int256(avgShifted) - 100;
        confidence = feed.weightedConfSum / feed.totalWeight;

        return (score, confidence, feed.submissionCount, feed.lastUpdated);
    }

    /// @notice Get submission IDs for a feed
    function getFeedSubmissions(uint256 feedId) external view returns (uint256[] memory) {
        return feedSubmissions[feedId];
    }

    /// @notice Get reporter info
    function getReporterInfo(address reporter_)
        external
        view
        returns (uint256 stake, uint256 reputation, uint256 totalSubmissions, bool active)
    {
        Reporter storage r = reporters[reporter_];
        return (r.stake, r.reputation, r.totalSubmissions, r.active);
    }

    // ─── Reputation Management (Owner) ───────────────────────────────

    /// @notice Adjust a reporter's reputation (owner only, for accuracy tracking)
    /// @param reporter_ The reporter address
    /// @param newReputation New reputation value (0-1000)
    function adjustReputation(address reporter_, uint256 newReputation) external onlyOwner {
        require(reporters[reporter_].active, "SentimentOracle: not active reporter");
        require(newReputation <= MAX_REPUTATION, "SentimentOracle: reputation too high");

        uint256 oldRep = reporters[reporter_].reputation;
        reporters[reporter_].reputation = newReputation;

        emit ReputationUpdated(reporter_, oldRep, newReputation);
    }

    /// @notice Update minimum stake requirement
    function setMinStake(uint256 newMinStake) external onlyOwner {
        require(newMinStake > 0, "SentimentOracle: zero stake");
        minStake = newMinStake;
    }

    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = payable(owner).call{value: address(this).balance}("");
        require(success, "SentimentOracle: withdraw failed");
    }

    receive() external payable {}
}
