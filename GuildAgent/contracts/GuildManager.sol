// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title GuildManager
 * @author ProbeBuilders
 * @notice On-chain guild management with treasury voting and member roster
 * @dev Supports guild creation, membership, treasury proposals, and voting
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

/// @title GuildManager — On-chain guild management
contract GuildManager is Ownable, ReentrancyGuard, Pausable {

    enum ProposalStatus { Pending, Approved, Rejected, Executed }

    struct Guild {
        string name;
        address guildMaster;
        uint256 entryFee;
        uint256 treasury;
        uint32 memberCount;
        uint64 createdAt;
        bool active;
    }

    struct Proposal {
        uint256 guildId;
        address proposer;
        address recipient;
        uint256 amount;
        string description;
        uint32 votesFor;
        uint32 votesAgainst;
        uint64 deadline;
        ProposalStatus status;
    }

    uint256 public nextGuildId = 1;
    uint256 public nextProposalId = 1;
    uint64 public constant VOTE_DURATION = 3 days;
    uint256 public constant MAX_MEMBERS = 10000;

    mapping(uint256 => Guild) public guilds;
    mapping(uint256 => mapping(address => bool)) public isMember;
    mapping(uint256 => address[]) private _guildMembers;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event GuildCreated(uint256 indexed guildId, string name, address indexed guildMaster, uint256 entryFee);
    event MemberJoined(uint256 indexed guildId, address indexed member);
    event MemberLeft(uint256 indexed guildId, address indexed member);
    event ProposalCreated(uint256 indexed proposalId, uint256 indexed guildId, address indexed proposer, address recipient, uint256 amount);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed proposalId, address indexed recipient, uint256 amount);
    event ProposalRejected(uint256 indexed proposalId);
    event TreasuryDeposit(uint256 indexed guildId, address indexed depositor, uint256 amount);

    error NotGuildMaster();
    error NotGuildMember();
    error AlreadyMember();
    error GuildNotActive();
    error InsufficientFee();
    error ProposalNotPending();
    error VotingNotEnded();
    error VotingEnded();
    error AlreadyVoted();
    error InsufficientTreasury();
    error TransferFailed();

    constructor() Ownable(msg.sender) {}

    /// @notice Create a new guild
    /// @param name Guild name
    /// @param entryFee Fee to join in wei
    /// @return guildId The created guild ID
    function createGuild(string calldata name, uint256 entryFee)
        external
        whenNotPaused
        returns (uint256 guildId)
    {
        require(bytes(name).length > 0 && bytes(name).length <= 64, "Invalid name");

        guildId = nextGuildId++;
        guilds[guildId] = Guild({
            name: name,
            guildMaster: msg.sender,
            entryFee: entryFee,
            treasury: 0,
            memberCount: 1,
            createdAt: uint64(block.timestamp),
            active: true
        });

        isMember[guildId][msg.sender] = true;
        _guildMembers[guildId].push(msg.sender);

        emit GuildCreated(guildId, name, msg.sender, entryFee);
        emit MemberJoined(guildId, msg.sender);
    }

    /// @notice Join an existing guild by paying the entry fee
    /// @param guildId Guild to join
    function joinGuild(uint256 guildId) external payable whenNotPaused nonReentrant {
        Guild storage g = guilds[guildId];
        if (!g.active) revert GuildNotActive();
        if (isMember[guildId][msg.sender]) revert AlreadyMember();
        if (msg.value < g.entryFee) revert InsufficientFee();
        require(g.memberCount < MAX_MEMBERS, "Guild is full");

        isMember[guildId][msg.sender] = true;
        _guildMembers[guildId].push(msg.sender);
        g.memberCount++;
        g.treasury += msg.value;

        emit MemberJoined(guildId, msg.sender);
        emit TreasuryDeposit(guildId, msg.sender, msg.value);
    }

    /// @notice Leave a guild (no refund)
    /// @param guildId Guild to leave
    function leaveGuild(uint256 guildId) external {
        if (!isMember[guildId][msg.sender]) revert NotGuildMember();
        require(guilds[guildId].guildMaster != msg.sender, "Guild master cannot leave");

        isMember[guildId][msg.sender] = false;
        guilds[guildId].memberCount--;

        emit MemberLeft(guildId, msg.sender);
    }

    /// @notice Deposit additional funds to guild treasury
    function depositToTreasury(uint256 guildId) external payable whenNotPaused {
        if (!isMember[guildId][msg.sender]) revert NotGuildMember();
        require(msg.value > 0, "Must send value");

        guilds[guildId].treasury += msg.value;
        emit TreasuryDeposit(guildId, msg.sender, msg.value);
    }

    /// @notice Propose a treasury spend
    /// @param guildId Guild ID
    /// @param recipient Who receives funds
    /// @param amount Amount to send
    /// @param description Reason for proposal
    /// @return proposalId The created proposal ID
    function proposeTreasury(
        uint256 guildId,
        address recipient,
        uint256 amount,
        string calldata description
    ) external whenNotPaused returns (uint256 proposalId) {
        if (!isMember[guildId][msg.sender]) revert NotGuildMember();
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0 && amount <= guilds[guildId].treasury, "Invalid amount");

        proposalId = nextProposalId++;
        proposals[proposalId] = Proposal({
            guildId: guildId,
            proposer: msg.sender,
            recipient: recipient,
            amount: amount,
            description: description,
            votesFor: 0,
            votesAgainst: 0,
            deadline: uint64(block.timestamp + VOTE_DURATION),
            status: ProposalStatus.Pending
        });

        emit ProposalCreated(proposalId, guildId, msg.sender, recipient, amount);
    }

    /// @notice Vote on a treasury proposal
    /// @param proposalId Proposal to vote on
    /// @param support True for yes, false for no
    function voteOnProposal(uint256 proposalId, bool support) external whenNotPaused {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.Pending) revert ProposalNotPending();
        if (block.timestamp > p.deadline) revert VotingEnded();
        if (!isMember[p.guildId][msg.sender]) revert NotGuildMember();
        if (hasVoted[proposalId][msg.sender]) revert AlreadyVoted();

        hasVoted[proposalId][msg.sender] = true;

        if (support) {
            p.votesFor++;
        } else {
            p.votesAgainst++;
        }

        emit VoteCast(proposalId, msg.sender, support);
    }

    /// @notice Execute a proposal after voting period ends
    /// @param proposalId Proposal to execute
    function executeProposal(uint256 proposalId) external whenNotPaused nonReentrant {
        Proposal storage p = proposals[proposalId];
        if (p.status != ProposalStatus.Pending) revert ProposalNotPending();
        if (block.timestamp <= p.deadline) revert VotingNotEnded();

        Guild storage g = guilds[p.guildId];

        if (p.votesFor > p.votesAgainst) {
            if (g.treasury < p.amount) revert InsufficientTreasury();

            p.status = ProposalStatus.Executed;
            g.treasury -= p.amount;

            (bool success, ) = payable(p.recipient).call{value: p.amount}("");
            if (!success) revert TransferFailed();

            emit ProposalExecuted(proposalId, p.recipient, p.amount);
        } else {
            p.status = ProposalStatus.Rejected;
            emit ProposalRejected(proposalId);
        }
    }

    /// @notice Deactivate a guild (guild master only)
    function deactivateGuild(uint256 guildId) external {
        if (guilds[guildId].guildMaster != msg.sender) revert NotGuildMaster();
        guilds[guildId].active = false;
    }

    /// @notice Get guild members list
    function getGuildMembers(uint256 guildId) external view returns (address[] memory) {
        return _guildMembers[guildId];
    }

    /// @notice Transfer guild master role
    function transferGuildMaster(uint256 guildId, address newMaster) external {
        if (guilds[guildId].guildMaster != msg.sender) revert NotGuildMaster();
        require(isMember[guildId][newMaster], "New master must be member");
        guilds[guildId].guildMaster = newMaster;
    }
}
