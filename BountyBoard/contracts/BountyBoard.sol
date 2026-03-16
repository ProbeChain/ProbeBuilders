// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title BountyBoard — Decentralized bounty platform for ProbeChain
/// @author ProbeBuilders
/// @notice Create bounties with escrow, submit work, approve or dispute outcomes
/// @dev Implements ReentrancyGuard and Ownable inline. Rydberg Testnet (Chain ID 8004).
contract BountyBoard {
    // ─── ReentrancyGuard ─────────────────────────────────────────────────
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _reentrancyStatus = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_reentrancyStatus != _ENTERED, "BountyBoard: reentrant call");
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    // ─── Enums & Structs ─────────────────────────────────────────────────
    enum BountyStatus { Open, InProgress, Completed, Disputed, Cancelled, Expired }

    struct Bounty {
        uint256 id;
        address creator;
        string description;
        uint256 reward;
        uint256 deadline;
        BountyStatus status;
        uint256 submissionCount;
        uint256 winningSubmissionId;
        uint256 createdAt;
        uint256 resolvedAt;
    }

    struct Submission {
        uint256 id;
        uint256 bountyId;
        address submitter;
        bytes32 proofHash;
        string proofURI;
        bool approved;
        bool rejected;
        uint256 submittedAt;
    }

    struct Dispute {
        uint256 bountyId;
        address disputedBy;
        string reason;
        bool resolved;
        address resolvedInFavorOf;
        uint256 createdAt;
        uint256 resolvedAt;
    }

    // ─── State ───────────────────────────────────────────────────────────
    address public owner;
    bool public paused;

    uint256 private _nextBountyId = 1;
    uint256 private _nextSubmissionId = 1;

    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => Submission) public submissions;
    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => uint256[]) private _bountySubmissions;
    mapping(address => uint256[]) private _creatorBounties;
    mapping(address => uint256[]) private _submitterSubmissions;

    uint256 public platformFeeBps = 200; // 2%
    uint256 public constant MAX_FEE_BPS = 500; // 5%
    uint256 public totalBounties;
    uint256 public totalBountiesCompleted;

    // ─── Events ──────────────────────────────────────────────────────────
    event BountyCreated(uint256 indexed bountyId, address indexed creator, uint256 reward, uint256 deadline, string description);
    event WorkSubmitted(uint256 indexed submissionId, uint256 indexed bountyId, address indexed submitter, bytes32 proofHash);
    event BountyApproved(uint256 indexed bountyId, uint256 indexed submissionId, address indexed winner, uint256 payout);
    event BountyDisputed(uint256 indexed bountyId, address indexed disputedBy, string reason);
    event DisputeResolved(uint256 indexed bountyId, address indexed resolvedInFavorOf, uint256 amount);
    event BountyCancelled(uint256 indexed bountyId, address indexed creator, uint256 refund);
    event BountyExpired(uint256 indexed bountyId);
    event SubmissionRejected(uint256 indexed submissionId, uint256 indexed bountyId);
    event PlatformFeeUpdated(uint256 oldBps, uint256 newBps);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "BountyBoard: not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "BountyBoard: paused");
        _;
    }

    modifier bountyExists(uint256 bountyId) {
        require(bounties[bountyId].createdAt != 0, "BountyBoard: bounty not found");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Bounty Lifecycle ────────────────────────────────────────────────

    /// @notice Create a bounty with escrowed reward
    /// @param description Bounty description
    /// @param deadline Unix timestamp deadline
    /// @return bountyId The new bounty ID
    function createBounty(
        string calldata description,
        uint256 deadline
    ) external payable whenNotPaused returns (uint256 bountyId) {
        require(msg.value > 0, "BountyBoard: reward required");
        require(bytes(description).length > 0 && bytes(description).length <= 4096, "BountyBoard: invalid description");
        require(deadline > block.timestamp + 1 hours, "BountyBoard: deadline too soon");

        bountyId = _nextBountyId++;

        bounties[bountyId] = Bounty({
            id: bountyId,
            creator: msg.sender,
            description: description,
            reward: msg.value,
            deadline: deadline,
            status: BountyStatus.Open,
            submissionCount: 0,
            winningSubmissionId: 0,
            createdAt: block.timestamp,
            resolvedAt: 0
        });

        _creatorBounties[msg.sender].push(bountyId);
        totalBounties++;

        emit BountyCreated(bountyId, msg.sender, msg.value, deadline, description);
    }

    /// @notice Submit work for a bounty
    /// @param bountyId The bounty to submit to
    /// @param proofHash Hash of the proof/deliverable
    /// @param proofURI URI pointing to the proof/deliverable
    /// @return submissionId The submission ID
    function submitWork(
        uint256 bountyId,
        bytes32 proofHash,
        string calldata proofURI
    ) external whenNotPaused bountyExists(bountyId) returns (uint256 submissionId) {
        Bounty storage bounty = bounties[bountyId];
        require(bounty.status == BountyStatus.Open || bounty.status == BountyStatus.InProgress, "BountyBoard: not accepting submissions");
        require(block.timestamp <= bounty.deadline, "BountyBoard: deadline passed");
        require(msg.sender != bounty.creator, "BountyBoard: creator cannot submit");
        require(proofHash != bytes32(0), "BountyBoard: empty proof hash");

        submissionId = _nextSubmissionId++;

        submissions[submissionId] = Submission({
            id: submissionId,
            bountyId: bountyId,
            submitter: msg.sender,
            proofHash: proofHash,
            proofURI: proofURI,
            approved: false,
            rejected: false,
            submittedAt: block.timestamp
        });

        _bountySubmissions[bountyId].push(submissionId);
        _submitterSubmissions[msg.sender].push(submissionId);
        bounty.submissionCount++;

        if (bounty.status == BountyStatus.Open) {
            bounty.status = BountyStatus.InProgress;
        }

        emit WorkSubmitted(submissionId, bountyId, msg.sender, proofHash);
    }

    /// @notice Approve a submission and pay the bounty
    /// @param bountyId The bounty
    /// @param submissionId The winning submission
    function approveBounty(uint256 bountyId, uint256 submissionId)
        external
        bountyExists(bountyId)
        nonReentrant
    {
        Bounty storage bounty = bounties[bountyId];
        require(bounty.creator == msg.sender, "BountyBoard: not bounty creator");
        require(
            bounty.status == BountyStatus.Open || bounty.status == BountyStatus.InProgress,
            "BountyBoard: cannot approve"
        );

        Submission storage sub = submissions[submissionId];
        require(sub.bountyId == bountyId, "BountyBoard: submission mismatch");
        require(!sub.rejected, "BountyBoard: submission rejected");

        sub.approved = true;
        bounty.status = BountyStatus.Completed;
        bounty.winningSubmissionId = submissionId;
        bounty.resolvedAt = block.timestamp;
        totalBountiesCompleted++;

        // Calculate payout
        uint256 fee = (bounty.reward * platformFeeBps) / 10000;
        uint256 payout = bounty.reward - fee;

        // Pay winner
        (bool ok, ) = payable(sub.submitter).call{value: payout}("");
        require(ok, "BountyBoard: payout failed");

        // Fee to platform
        if (fee > 0) {
            (bool feeOk, ) = payable(owner).call{value: fee}("");
            require(feeOk, "BountyBoard: fee transfer failed");
        }

        emit BountyApproved(bountyId, submissionId, sub.submitter, payout);
    }

    /// @notice Reject a submission
    /// @param submissionId The submission to reject
    function rejectSubmission(uint256 submissionId) external {
        Submission storage sub = submissions[submissionId];
        require(sub.submittedAt != 0, "BountyBoard: submission not found");
        require(bounties[sub.bountyId].creator == msg.sender, "BountyBoard: not bounty creator");
        require(!sub.approved, "BountyBoard: already approved");

        sub.rejected = true;
        emit SubmissionRejected(submissionId, sub.bountyId);
    }

    /// @notice Dispute a bounty outcome
    /// @param bountyId The bounty to dispute
    /// @param reason Dispute reason
    function disputeBounty(uint256 bountyId, string calldata reason) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(
            bounty.status == BountyStatus.InProgress || bounty.status == BountyStatus.Completed,
            "BountyBoard: cannot dispute"
        );
        require(bytes(reason).length > 0, "BountyBoard: reason required");

        // Only submitters or creator can dispute
        bool isParticipant = (msg.sender == bounty.creator);
        if (!isParticipant) {
            uint256[] storage subIds = _bountySubmissions[bountyId];
            for (uint256 i; i < subIds.length; ++i) {
                if (submissions[subIds[i]].submitter == msg.sender) {
                    isParticipant = true;
                    break;
                }
            }
        }
        require(isParticipant, "BountyBoard: not a participant");

        bounty.status = BountyStatus.Disputed;

        disputes[bountyId] = Dispute({
            bountyId: bountyId,
            disputedBy: msg.sender,
            reason: reason,
            resolved: false,
            resolvedInFavorOf: address(0),
            createdAt: block.timestamp,
            resolvedAt: 0
        });

        emit BountyDisputed(bountyId, msg.sender, reason);
    }

    /// @notice Resolve a dispute (admin only)
    /// @param bountyId The disputed bounty
    /// @param inFavorOf Address to receive the reward (creator for refund, or submitter for payout)
    function resolveDispute(uint256 bountyId, address inFavorOf) external onlyOwner bountyExists(bountyId) nonReentrant {
        Bounty storage bounty = bounties[bountyId];
        require(bounty.status == BountyStatus.Disputed, "BountyBoard: not disputed");

        Dispute storage d = disputes[bountyId];
        d.resolved = true;
        d.resolvedInFavorOf = inFavorOf;
        d.resolvedAt = block.timestamp;

        bounty.status = BountyStatus.Completed;
        bounty.resolvedAt = block.timestamp;

        uint256 amount = bounty.reward;

        (bool ok, ) = payable(inFavorOf).call{value: amount}("");
        require(ok, "BountyBoard: resolution transfer failed");

        emit DisputeResolved(bountyId, inFavorOf, amount);
    }

    /// @notice Cancel a bounty (creator, before any submissions)
    /// @param bountyId The bounty to cancel
    function cancelBounty(uint256 bountyId) external bountyExists(bountyId) nonReentrant {
        Bounty storage bounty = bounties[bountyId];
        require(bounty.creator == msg.sender, "BountyBoard: not creator");
        require(bounty.status == BountyStatus.Open, "BountyBoard: cannot cancel");
        require(bounty.submissionCount == 0, "BountyBoard: has submissions");

        bounty.status = BountyStatus.Cancelled;
        bounty.resolvedAt = block.timestamp;

        (bool ok, ) = payable(msg.sender).call{value: bounty.reward}("");
        require(ok, "BountyBoard: refund failed");

        emit BountyCancelled(bountyId, msg.sender, bounty.reward);
    }

    /// @notice Mark an expired bounty and refund creator
    /// @param bountyId The bounty
    function expireBounty(uint256 bountyId) external bountyExists(bountyId) nonReentrant {
        Bounty storage bounty = bounties[bountyId];
        require(block.timestamp > bounty.deadline, "BountyBoard: not expired");
        require(
            bounty.status == BountyStatus.Open || bounty.status == BountyStatus.InProgress,
            "BountyBoard: cannot expire"
        );

        bounty.status = BountyStatus.Expired;
        bounty.resolvedAt = block.timestamp;

        (bool ok, ) = payable(bounty.creator).call{value: bounty.reward}("");
        require(ok, "BountyBoard: refund failed");

        emit BountyExpired(bountyId);
    }

    // ─── View Functions ──────────────────────────────────────────────────

    /// @notice Get submissions for a bounty
    function getBountySubmissions(uint256 bountyId) external view returns (uint256[] memory) {
        return _bountySubmissions[bountyId];
    }

    /// @notice Get bounties created by an address
    function getCreatorBounties(address creator) external view returns (uint256[] memory) {
        return _creatorBounties[creator];
    }

    /// @notice Get submissions by an address
    function getSubmitterSubmissions(address submitter) external view returns (uint256[] memory) {
        return _submitterSubmissions[submitter];
    }

    // ─── Admin ───────────────────────────────────────────────────────────

    function setPlatformFee(uint256 newBps) external onlyOwner {
        require(newBps <= MAX_FEE_BPS, "BountyBoard: fee too high");
        uint256 old = platformFeeBps;
        platformFeeBps = newBps;
        emit PlatformFeeUpdated(old, newBps);
    }

    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "BountyBoard: zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
