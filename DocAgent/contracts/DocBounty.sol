// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DocBounty
 * @author ProbeChain Team
 * @notice Documentation bounty platform for incentivizing quality documentation
 * @dev Supports bounty creation, submission, approval/rejection with escrow payments
 */
contract DocBounty {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "DocBounty: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "DocBounty: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _guardStatus = 1;
    modifier nonReentrant() {
        require(_guardStatus == 1, "DocBounty: reentrant call");
        _guardStatus = 2;
        _;
        _guardStatus = 1;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "DocBounty: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums ──────────────────────────────────────────────────────────
    enum BountyStatus { Open, Claimed, Completed, Expired, Cancelled }
    enum SubmissionStatus { Pending, Approved, Rejected }

    // ─── Structs ────────────────────────────────────────────────────────
    struct Bounty {
        uint256 id;
        address creator;
        string topic;
        uint256 reward;
        uint256 deadline;
        BountyStatus status;
        uint256 submissionCount;
        uint256 createdAt;
    }

    struct Submission {
        uint256 id;
        uint256 bountyId;
        address author;
        bytes32 docHash;
        SubmissionStatus status;
        uint256 submittedAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public bountyCount;
    uint256 public submissionCount;
    uint256 public platformFeePercent = 2;
    uint256 public collectedFees;

    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => Submission) public submissions;
    mapping(uint256 => uint256[]) public bountySubmissions;
    mapping(address => uint256) public authorReputation;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a new documentation bounty is created
    event BountyCreated(uint256 indexed bountyId, address indexed creator, string topic, uint256 reward, uint256 deadline);
    /// @notice Emitted when a doc submission is made
    event DocSubmitted(uint256 indexed submissionId, uint256 indexed bountyId, address indexed author, bytes32 docHash);
    /// @notice Emitted when a submission is approved and paid
    event DocApproved(uint256 indexed submissionId, uint256 indexed bountyId, address indexed author, uint256 reward);
    /// @notice Emitted when a submission is rejected
    event DocRejected(uint256 indexed submissionId, uint256 indexed bountyId);
    /// @notice Emitted when a bounty is cancelled
    event BountyCancelled(uint256 indexed bountyId);
    /// @notice Emitted when fees are withdrawn
    event FeesWithdrawn(address indexed to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Create a new documentation bounty
     * @param topic Documentation topic description
     * @param deadline Unix timestamp when the bounty expires
     */
    function createDocBounty(
        string calldata topic,
        uint256 deadline
    ) external payable whenNotPaused {
        require(bytes(topic).length > 0 && bytes(topic).length <= 256, "DocBounty: invalid topic");
        require(msg.value > 0, "DocBounty: reward required");
        require(deadline > block.timestamp, "DocBounty: deadline must be future");

        bountyCount++;
        bounties[bountyCount] = Bounty({
            id: bountyCount,
            creator: msg.sender,
            topic: topic,
            reward: msg.value,
            deadline: deadline,
            status: BountyStatus.Open,
            submissionCount: 0,
            createdAt: block.timestamp
        });

        emit BountyCreated(bountyCount, msg.sender, topic, msg.value, deadline);
    }

    /**
     * @notice Submit documentation for a bounty
     * @param bountyId ID of the bounty
     * @param docHash IPFS hash of the documentation
     */
    function submitDoc(uint256 bountyId, bytes32 docHash) external whenNotPaused {
        Bounty storage bounty = bounties[bountyId];
        require(bounty.status == BountyStatus.Open, "DocBounty: bounty not open");
        require(block.timestamp <= bounty.deadline, "DocBounty: deadline passed");
        require(docHash != bytes32(0), "DocBounty: empty hash");
        require(msg.sender != bounty.creator, "DocBounty: creator cannot submit");

        submissionCount++;
        submissions[submissionCount] = Submission({
            id: submissionCount,
            bountyId: bountyId,
            author: msg.sender,
            docHash: docHash,
            status: SubmissionStatus.Pending,
            submittedAt: block.timestamp
        });

        bounty.submissionCount++;
        bountySubmissions[bountyId].push(submissionCount);

        emit DocSubmitted(submissionCount, bountyId, msg.sender, docHash);
    }

    /**
     * @notice Approve a submission and pay the bounty reward
     * @param submissionId ID of the submission to approve
     */
    function approveDoc(uint256 submissionId) external nonReentrant whenNotPaused {
        Submission storage sub = submissions[submissionId];
        Bounty storage bounty = bounties[sub.bountyId];

        require(msg.sender == bounty.creator, "DocBounty: not bounty creator");
        require(sub.status == SubmissionStatus.Pending, "DocBounty: not pending");
        require(bounty.status == BountyStatus.Open, "DocBounty: bounty not open");

        sub.status = SubmissionStatus.Approved;
        bounty.status = BountyStatus.Completed;

        uint256 fee = (bounty.reward * platformFeePercent) / 100;
        uint256 payout = bounty.reward - fee;
        collectedFees += fee;

        authorReputation[sub.author]++;

        (bool success, ) = payable(sub.author).call{value: payout}("");
        require(success, "DocBounty: payment failed");

        emit DocApproved(submissionId, sub.bountyId, sub.author, payout);
    }

    /**
     * @notice Reject a submission
     * @param submissionId ID of the submission to reject
     */
    function rejectDoc(uint256 submissionId) external {
        Submission storage sub = submissions[submissionId];
        Bounty storage bounty = bounties[sub.bountyId];

        require(msg.sender == bounty.creator, "DocBounty: not bounty creator");
        require(sub.status == SubmissionStatus.Pending, "DocBounty: not pending");

        sub.status = SubmissionStatus.Rejected;
        emit DocRejected(submissionId, sub.bountyId);
    }

    /**
     * @notice Cancel a bounty and refund (only if no approved submissions)
     * @param bountyId ID of the bounty to cancel
     */
    function cancelBounty(uint256 bountyId) external nonReentrant {
        Bounty storage bounty = bounties[bountyId];
        require(msg.sender == bounty.creator, "DocBounty: not creator");
        require(bounty.status == BountyStatus.Open, "DocBounty: not open");

        bounty.status = BountyStatus.Cancelled;
        (bool success, ) = payable(bounty.creator).call{value: bounty.reward}("");
        require(success, "DocBounty: refund failed");

        emit BountyCancelled(bountyId);
    }

    /**
     * @notice Withdraw collected platform fees
     * @param to Address to receive fees
     */
    function withdrawFees(address to) external onlyOwner nonReentrant {
        require(to != address(0), "DocBounty: zero address");
        uint256 amount = collectedFees;
        collectedFees = 0;
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "DocBounty: withdrawal failed");
        emit FeesWithdrawn(to, amount);
    }

    /**
     * @notice Set the platform fee percentage
     * @param newFee New fee percentage (max 10%)
     */
    function setPlatformFee(uint256 newFee) external onlyOwner {
        require(newFee <= 10, "DocBounty: fee too high");
        platformFeePercent = newFee;
    }

    /**
     * @notice Get submission IDs for a bounty
     * @param bountyId Bounty ID
     * @return ids Array of submission IDs
     */
    function getBountySubmissions(uint256 bountyId) external view returns (uint256[] memory ids) {
        return bountySubmissions[bountyId];
    }
}
