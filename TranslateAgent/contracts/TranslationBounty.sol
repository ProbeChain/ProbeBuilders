// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title TranslationBounty
 * @author ProbeBuilders
 * @notice Translation bounty system with community quality voting
 * @dev Supports bounty creation, translation submission, approval, and dispute resolution
 */

abstract contract Ownable {
    address private _owner;
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert OwnableInvalidOwner(address(0));
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender);
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardReentrantCall();
        _status = 2;
        _;
        _status = 1;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
}

/// @title TranslationBounty — Translation bounty system with quality voting
contract TranslationBounty is Ownable, ReentrancyGuard, Pausable {

    enum BountyStatus { Open, Submitted, Approved, Disputed, Resolved, Cancelled }

    struct Bounty {
        address requester;
        bytes32 sourceTextHash;
        string sourceLang;
        string targetLang;
        uint256 reward;
        uint64 deadline;
        BountyStatus status;
    }

    struct Submission {
        address translator;
        bytes32 translatedHash;
        string proofURI;          // IPFS link to full translation
        uint32 qualityVotesUp;
        uint32 qualityVotesDown;
        uint64 submittedAt;
        bool accepted;
    }

    uint256 public nextBountyId = 1;
    uint64 public constant MIN_DEADLINE_DELTA = 1 days;
    uint64 public constant DISPUTE_PERIOD = 2 days;
    uint256 public disputeStake = 0.01 ether;
    uint256 public minReward = 0.001 ether;

    mapping(uint256 => Bounty) public bounties;
    /// @notice bountyId => submissions array
    mapping(uint256 => Submission[]) public submissions;
    /// @notice bountyId => chosen submission index
    mapping(uint256 => uint256) public chosenSubmission;
    /// @notice bountyId => submissionIndex => voter => voted
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public hasVoted;
    /// @notice Translator reputation score
    mapping(address => uint256) public translatorReputation;
    /// @notice Dispute stakes held
    mapping(uint256 => mapping(address => uint256)) public disputeStakes;

    event BountyCreated(uint256 indexed bountyId, address indexed requester, string sourceLang, string targetLang, uint256 reward);
    event TranslationSubmitted(uint256 indexed bountyId, uint256 submissionIndex, address indexed translator);
    event TranslationApproved(uint256 indexed bountyId, uint256 submissionIndex, address indexed translator, uint256 reward);
    event BountyDisputed(uint256 indexed bountyId, address indexed disputer);
    event DisputeResolved(uint256 indexed bountyId, bool translatorWins);
    event QualityVote(uint256 indexed bountyId, uint256 submissionIndex, address indexed voter, bool positive);
    event BountyCancelled(uint256 indexed bountyId);
    event ReputationUpdated(address indexed translator, uint256 newScore);

    error NotRequester();
    error BountyNotOpen();
    error BountyNotSubmitted();
    error InsufficientReward();
    error DeadlinePassed();
    error DeadlineTooSoon();
    error NoSubmissions();
    error AlreadyVoted();
    error TransferFailed();
    error InvalidSubmission();
    error NotInDispute();
    error InsufficientStake();

    constructor() Ownable(msg.sender) {}

    /// @notice Create a translation bounty
    /// @param sourceTextHash Hash of source text for verification
    /// @param sourceLang Source language code (e.g., "en")
    /// @param targetLang Target language code (e.g., "zh")
    /// @param deadline Deadline timestamp
    /// @return bountyId Created bounty ID
    function createBounty(
        bytes32 sourceTextHash,
        string calldata sourceLang,
        string calldata targetLang,
        uint64 deadline
    ) external payable whenNotPaused returns (uint256 bountyId) {
        if (msg.value < minReward) revert InsufficientReward();
        if (deadline < block.timestamp + MIN_DEADLINE_DELTA) revert DeadlineTooSoon();

        bountyId = nextBountyId++;
        bounties[bountyId] = Bounty({
            requester: msg.sender,
            sourceTextHash: sourceTextHash,
            sourceLang: sourceLang,
            targetLang: targetLang,
            reward: msg.value,
            deadline: deadline,
            status: BountyStatus.Open
        });

        emit BountyCreated(bountyId, msg.sender, sourceLang, targetLang, msg.value);
    }

    /// @notice Submit a translation for a bounty
    /// @param bountyId Bounty to submit for
    /// @param translatedHash Hash of translated text
    /// @param proofURI IPFS URI with full translation
    function submitTranslation(
        uint256 bountyId,
        bytes32 translatedHash,
        string calldata proofURI
    ) external whenNotPaused {
        Bounty storage b = bounties[bountyId];
        if (b.status != BountyStatus.Open) revert BountyNotOpen();
        if (block.timestamp > b.deadline) revert DeadlinePassed();
        require(msg.sender != b.requester, "Requester cannot submit");

        submissions[bountyId].push(Submission({
            translator: msg.sender,
            translatedHash: translatedHash,
            proofURI: proofURI,
            qualityVotesUp: 0,
            qualityVotesDown: 0,
            submittedAt: uint64(block.timestamp),
            accepted: false
        }));

        uint256 idx = submissions[bountyId].length - 1;
        emit TranslationSubmitted(bountyId, idx, msg.sender);
    }

    /// @notice Approve a translation and pay the translator
    /// @param bountyId Bounty ID
    /// @param submissionIndex Index of chosen submission
    function approveTranslation(uint256 bountyId, uint256 submissionIndex)
        external
        whenNotPaused
        nonReentrant
    {
        Bounty storage b = bounties[bountyId];
        if (b.requester != msg.sender) revert NotRequester();
        if (b.status != BountyStatus.Open) revert BountyNotOpen();
        if (submissionIndex >= submissions[bountyId].length) revert InvalidSubmission();

        b.status = BountyStatus.Approved;
        Submission storage s = submissions[bountyId][submissionIndex];
        s.accepted = true;
        chosenSubmission[bountyId] = submissionIndex;

        translatorReputation[s.translator] += 10;

        (bool ok, ) = payable(s.translator).call{value: b.reward}("");
        if (!ok) revert TransferFailed();

        emit TranslationApproved(bountyId, submissionIndex, s.translator, b.reward);
        emit ReputationUpdated(s.translator, translatorReputation[s.translator]);
    }

    /// @notice Dispute an approved translation
    /// @param bountyId Bounty to dispute
    function disputeTranslation(uint256 bountyId) external payable whenNotPaused {
        Bounty storage b = bounties[bountyId];
        require(
            b.status == BountyStatus.Approved || b.status == BountyStatus.Open,
            "Cannot dispute"
        );
        if (msg.value < disputeStake) revert InsufficientStake();

        b.status = BountyStatus.Disputed;
        disputeStakes[bountyId][msg.sender] = msg.value;

        emit BountyDisputed(bountyId, msg.sender);
    }

    /// @notice Resolve dispute (owner arbitration)
    /// @param bountyId Bounty in dispute
    /// @param translatorWins True if translator's work is valid
    function resolveDispute(uint256 bountyId, bool translatorWins)
        external
        onlyOwner
        nonReentrant
    {
        Bounty storage b = bounties[bountyId];
        if (b.status != BountyStatus.Disputed) revert NotInDispute();

        b.status = BountyStatus.Resolved;

        if (!translatorWins) {
            // Penalize translator reputation
            uint256 subIdx = chosenSubmission[bountyId];
            address translator = submissions[bountyId][subIdx].translator;
            if (translatorReputation[translator] >= 5) {
                translatorReputation[translator] -= 5;
            } else {
                translatorReputation[translator] = 0;
            }
            emit ReputationUpdated(translator, translatorReputation[translator]);
        }

        emit DisputeResolved(bountyId, translatorWins);
    }

    /// @notice Community quality vote on a submission
    /// @param bountyId Bounty ID
    /// @param submissionIndex Submission index
    /// @param positive True for upvote, false for downvote
    function voteQuality(uint256 bountyId, uint256 submissionIndex, bool positive) external whenNotPaused {
        if (submissionIndex >= submissions[bountyId].length) revert InvalidSubmission();
        if (hasVoted[bountyId][submissionIndex][msg.sender]) revert AlreadyVoted();

        hasVoted[bountyId][submissionIndex][msg.sender] = true;
        Submission storage s = submissions[bountyId][submissionIndex];

        if (positive) {
            s.qualityVotesUp++;
        } else {
            s.qualityVotesDown++;
        }

        emit QualityVote(bountyId, submissionIndex, msg.sender, positive);
    }

    /// @notice Cancel bounty and refund (requester only, if still open)
    function cancelBounty(uint256 bountyId) external nonReentrant {
        Bounty storage b = bounties[bountyId];
        if (b.requester != msg.sender) revert NotRequester();
        if (b.status != BountyStatus.Open) revert BountyNotOpen();
        require(submissions[bountyId].length == 0, "Has submissions");

        b.status = BountyStatus.Cancelled;
        (bool ok, ) = payable(msg.sender).call{value: b.reward}("");
        if (!ok) revert TransferFailed();

        emit BountyCancelled(bountyId);
    }

    /// @notice Get submission count for a bounty
    function getSubmissionCount(uint256 bountyId) external view returns (uint256) {
        return submissions[bountyId].length;
    }

    /// @notice Update dispute stake requirement
    function setDisputeStake(uint256 newStake) external onlyOwner {
        disputeStake = newStake;
    }

    /// @notice Update minimum reward
    function setMinReward(uint256 newMinReward) external onlyOwner {
        minReward = newMinReward;
    }
}
