// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DataGovernance
 * @author ProbeChain
 * @notice Community data governance with policy proposals, voting, and curator rewards
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London)
 */

// --- Inline Ownable ---
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorized(address account);
    error OwnableInvalidOwner(address owner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorized(msg.sender);
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(newOwner);
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// --- Inline ReentrancyGuard ---
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

// --- Inline Pausable ---
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();

    modifier whenNotPaused() {
        if (_paused) revert ContractPaused();
        _;
    }

    function paused() public view returns (bool) { return _paused; }

    function pause() external onlyOwner {
        if (_paused) revert ContractPaused();
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        if (!_paused) revert ContractNotPaused();
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract DataGovernance is Ownable, ReentrancyGuard, Pausable {
    // --- Types ---
    enum ProposalStatus { Active, Passed, Rejected, Executed, Cancelled }
    enum DataStatus { Pending, Approved, Rejected }

    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        bytes32 policyHash;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        ProposalStatus status;
        bool executed;
    }

    struct DataSubmission {
        uint256 id;
        address submitter;
        bytes32 dataHash;
        string category;
        DataStatus status;
        uint256 approvals;
        uint256 rejections;
        uint256 submittedAt;
    }

    // --- State ---
    uint256 public nextProposalId;
    uint256 public nextDataId;
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant MIN_MEMBER_STAKE = 0.01 ether;
    uint256 public constant CURATOR_APPROVAL_THRESHOLD = 3;
    uint256 public curatorRewardPool;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => DataSubmission) public dataSubmissions;
    mapping(address => uint256) public memberStakes;
    mapping(address => bool) public isCurator;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(address => bool)) public hasCurated;
    mapping(address => uint256) public curatorRewards;
    uint256 public memberCount;

    // --- Events ---
    event MemberJoined(address indexed member, uint256 stake);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description, bytes32 policyHash);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event DataSubmitted(uint256 indexed dataId, address indexed submitter, bytes32 dataHash, string category);
    event DataApproved(uint256 indexed dataId, address indexed curator);
    event DataRejected(uint256 indexed dataId, address indexed curator);
    event CuratorAdded(address indexed curator);
    event CuratorRemoved(address indexed curator);
    event CuratorRewardClaimed(address indexed curator, uint256 amount);
    event RewardPoolFunded(uint256 amount);

    // --- Errors ---
    error NotMember();
    error NotCurator();
    error ProposalNotFound();
    error ProposalNotActive();
    error ProposalStillActive();
    error AlreadyVoted();
    error AlreadyCurated();
    error DataNotFound();
    error DataNotPending();
    error InsufficientStake();
    error NoRewardsToClaim();

    // --- Membership ---

    /// @notice Join the DAO by staking
    function joinDAO() external payable whenNotPaused {
        if (msg.value < MIN_MEMBER_STAKE) revert InsufficientStake();
        if (memberStakes[msg.sender] == 0) memberCount++;
        memberStakes[msg.sender] += msg.value;
        emit MemberJoined(msg.sender, msg.value);
    }

    /// @notice Fund the curator reward pool
    function fundRewardPool() external payable onlyOwner {
        curatorRewardPool += msg.value;
        emit RewardPoolFunded(msg.value);
    }

    /// @notice Add a curator
    function addCurator(address curator) external onlyOwner {
        isCurator[curator] = true;
        emit CuratorAdded(curator);
    }

    /// @notice Remove a curator
    function removeCurator(address curator) external onlyOwner {
        isCurator[curator] = false;
        emit CuratorRemoved(curator);
    }

    // --- Proposals ---

    /// @notice Propose a policy change
    /// @param description Human-readable description of the policy change
    /// @param policyHash Hash of the full policy document
    /// @return proposalId The ID of the created proposal
    function proposePolicyChange(
        string calldata description,
        bytes32 policyHash
    ) external whenNotPaused returns (uint256 proposalId) {
        if (memberStakes[msg.sender] == 0) revert NotMember();

        proposalId = nextProposalId++;
        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            description: description,
            policyHash: policyHash,
            forVotes: 0,
            againstVotes: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + VOTING_PERIOD,
            status: ProposalStatus.Active,
            executed: false
        });

        emit ProposalCreated(proposalId, msg.sender, description, policyHash);
    }

    /// @notice Vote on a policy proposal
    /// @param proposalId The proposal to vote on
    /// @param support True for yes, false for no
    function voteOnPolicy(uint256 proposalId, bool support) external whenNotPaused {
        if (memberStakes[msg.sender] == 0) revert NotMember();

        Proposal storage prop = proposals[proposalId];
        if (prop.proposer == address(0)) revert ProposalNotFound();
        if (prop.status != ProposalStatus.Active) revert ProposalNotActive();
        if (block.timestamp > prop.endTime) revert ProposalNotActive();
        if (hasVoted[proposalId][msg.sender]) revert AlreadyVoted();

        hasVoted[proposalId][msg.sender] = true;
        uint256 weight = memberStakes[msg.sender];

        if (support) {
            prop.forVotes += weight;
        } else {
            prop.againstVotes += weight;
        }

        emit VoteCast(proposalId, msg.sender, support, weight);
    }

    /// @notice Execute a passed proposal
    /// @param proposalId The proposal to execute
    function executePolicy(uint256 proposalId) external whenNotPaused {
        Proposal storage prop = proposals[proposalId];
        if (prop.proposer == address(0)) revert ProposalNotFound();
        if (block.timestamp <= prop.endTime) revert ProposalStillActive();
        if (prop.executed) revert ProposalNotActive();

        prop.executed = true;

        if (prop.forVotes > prop.againstVotes) {
            prop.status = ProposalStatus.Passed;
            emit ProposalExecuted(proposalId);
        } else {
            prop.status = ProposalStatus.Rejected;
        }
    }

    // --- Data Submissions ---

    /// @notice Submit data for community review
    /// @param dataHash Hash of the submitted data
    /// @param category Data category label
    /// @return dataId The ID of the data submission
    function submitData(bytes32 dataHash, string calldata category) external whenNotPaused returns (uint256 dataId) {
        if (memberStakes[msg.sender] == 0) revert NotMember();

        dataId = nextDataId++;
        dataSubmissions[dataId] = DataSubmission({
            id: dataId,
            submitter: msg.sender,
            dataHash: dataHash,
            category: category,
            status: DataStatus.Pending,
            approvals: 0,
            rejections: 0,
            submittedAt: block.timestamp
        });

        emit DataSubmitted(dataId, msg.sender, dataHash, category);
    }

    /// @notice Approve or reject a data submission (curators only)
    /// @param dataId The data submission to curate
    /// @param approve True to approve, false to reject
    function approveData(uint256 dataId, bool approve) external whenNotPaused {
        if (!isCurator[msg.sender]) revert NotCurator();

        DataSubmission storage data = dataSubmissions[dataId];
        if (data.submitter == address(0)) revert DataNotFound();
        if (data.status != DataStatus.Pending) revert DataNotPending();
        if (hasCurated[dataId][msg.sender]) revert AlreadyCurated();

        hasCurated[dataId][msg.sender] = true;

        if (approve) {
            data.approvals++;
            emit DataApproved(dataId, msg.sender);
            if (data.approvals >= CURATOR_APPROVAL_THRESHOLD) {
                data.status = DataStatus.Approved;
            }
        } else {
            data.rejections++;
            emit DataRejected(dataId, msg.sender);
            if (data.rejections >= CURATOR_APPROVAL_THRESHOLD) {
                data.status = DataStatus.Rejected;
            }
        }

        // Reward curator
        uint256 reward = 0.001 ether;
        if (curatorRewardPool >= reward) {
            curatorRewardPool -= reward;
            curatorRewards[msg.sender] += reward;
        }
    }

    /// @notice Claim accumulated curator rewards
    function claimCuratorReward() external nonReentrant {
        uint256 amount = curatorRewards[msg.sender];
        if (amount == 0) revert NoRewardsToClaim();
        curatorRewards[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit CuratorRewardClaimed(msg.sender, amount);
    }
}
