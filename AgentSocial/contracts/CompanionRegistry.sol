// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CompanionRegistry
 * @author ProbeChain
 * @notice AI companion registry — owners register on-chain AI companions with personality
 *         metadata and model hashes. Users interact (pay-per-interaction) and rate companions.
 *         Interaction fees flow to the companion owner.
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London).
 */

// ── Ownable ────────────────────────────────────────────────────────────────────
abstract contract Ownable {
    address private _owner;
    error OwnableUnauthorized(address account);
    error OwnableInvalidOwner(address owner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    function owner() public view virtual returns (address) { return _owner; }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorized(msg.sender); _; }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ── ReentrancyGuard ────────────────────────────────────────────────────────────
abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status != 1) revert ReentrancyGuardReentrantCall();
        _status = 2; _; _status = 1;
    }
}

// ── Pausable ───────────────────────────────────────────────────────────────────
abstract contract Pausable is Ownable {
    bool private _paused;
    error EnforcedPause(); error ExpectedPause();
    event Paused(address account); event Unpaused(address account);
    function paused() public view returns (bool) { return _paused; }
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    modifier whenPaused() { if (!_paused) revert ExpectedPause(); _; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

// ── CompanionRegistry ──────────────────────────────────────────────────────────
contract CompanionRegistry is Ownable, ReentrancyGuard, Pausable {

    struct Companion {
        uint256 id;
        address companionOwner;
        string name;
        string personality;
        string modelHash;
        uint256 interactionFee;
        uint256 totalInteractions;
        uint256 totalRatings;
        uint256 ratingSum;
        uint256 createdAt;
        bool active;
    }

    struct Interaction {
        uint256 companionId;
        address user;
        uint256 timestamp;
        uint256 feePaid;
    }

    uint256 public nextCompanionId;
    uint256 public platformFeeBps = 500; // 5 %
    uint256 public registrationFee;

    mapping(uint256 => Companion) public companions;
    mapping(address => uint256[]) private _ownedCompanions;
    mapping(uint256 => Interaction[]) private _interactions;
    mapping(address => mapping(uint256 => bool)) public hasRated;
    mapping(address => uint256) public ownerBalance;

    // ── Events ─────────────────────────────────────────────────────────────────
    event CompanionRegistered(uint256 indexed companionId, address indexed companionOwner, string name);
    event CompanionUpdated(uint256 indexed companionId, string name, string personality, string modelHash);
    event InteractionRecorded(uint256 indexed companionId, address indexed user, uint256 feePaid);
    event CompanionRated(uint256 indexed companionId, address indexed rater, uint256 rating);
    event CompanionDeactivated(uint256 indexed companionId);
    event CompanionReactivated(uint256 indexed companionId);
    event OwnerWithdrew(address indexed companionOwner, uint256 amount);
    event RegistrationFeeUpdated(uint256 newFee);
    event PlatformFeeUpdated(uint256 newBps);

    // ── Errors ─────────────────────────────────────────────────────────────────
    error EmptyName();
    error EmptyModelHash();
    error CompanionNotFound();
    error CompanionNotActive();
    error InsufficientPayment();
    error NotCompanionOwner();
    error AlreadyRated();
    error InvalidRating();
    error NothingToWithdraw();
    error TransferFailed();

    // ── Register ───────────────────────────────────────────────────────────────
    /// @notice Register a new AI companion.
    /// @param name           Display name.
    /// @param personality    Personality description or JSON config hash.
    /// @param modelHash      IPFS / hash of the model weights or config.
    /// @param interactionFee Fee per interaction in wei.
    function registerCompanion(
        string calldata name,
        string calldata personality,
        string calldata modelHash,
        uint256 interactionFee
    ) external payable whenNotPaused returns (uint256 companionId) {
        if (bytes(name).length == 0) revert EmptyName();
        if (bytes(modelHash).length == 0) revert EmptyModelHash();
        if (msg.value < registrationFee) revert InsufficientPayment();

        companionId = nextCompanionId++;
        companions[companionId] = Companion({
            id: companionId,
            companionOwner: msg.sender,
            name: name,
            personality: personality,
            modelHash: modelHash,
            interactionFee: interactionFee,
            totalInteractions: 0,
            totalRatings: 0,
            ratingSum: 0,
            createdAt: block.timestamp,
            active: true
        });

        _ownedCompanions[msg.sender].push(companionId);
        emit CompanionRegistered(companionId, msg.sender, name);
    }

    // ── Update ─────────────────────────────────────────────────────────────────
    /// @notice Companion owner updates metadata.
    function updateCompanion(
        uint256 companionId,
        string calldata name,
        string calldata personality,
        string calldata modelHash,
        uint256 interactionFee
    ) external whenNotPaused {
        Companion storage c = companions[companionId];
        if (c.createdAt == 0) revert CompanionNotFound();
        if (msg.sender != c.companionOwner) revert NotCompanionOwner();

        if (bytes(name).length > 0) c.name = name;
        if (bytes(personality).length > 0) c.personality = personality;
        if (bytes(modelHash).length > 0) c.modelHash = modelHash;
        c.interactionFee = interactionFee;

        emit CompanionUpdated(companionId, c.name, c.personality, c.modelHash);
    }

    // ── Interact ───────────────────────────────────────────────────────────────
    /// @notice Interact with a companion — pays the interaction fee.
    function interactWith(uint256 companionId) external payable nonReentrant whenNotPaused {
        Companion storage c = companions[companionId];
        if (c.createdAt == 0) revert CompanionNotFound();
        if (!c.active) revert CompanionNotActive();
        if (msg.value < c.interactionFee) revert InsufficientPayment();

        c.totalInteractions++;
        _interactions[companionId].push(Interaction({
            companionId: companionId,
            user: msg.sender,
            timestamp: block.timestamp,
            feePaid: msg.value
        }));

        uint256 fee = (msg.value * platformFeeBps) / 10_000;
        ownerBalance[c.companionOwner] += msg.value - fee;

        emit InteractionRecorded(companionId, msg.sender, msg.value);
    }

    // ── Rate ───────────────────────────────────────────────────────────────────
    /// @notice Rate a companion (1-5 stars, one rating per user per companion).
    function rateCompanion(uint256 companionId, uint256 rating) external whenNotPaused {
        if (rating < 1 || rating > 5) revert InvalidRating();
        Companion storage c = companions[companionId];
        if (c.createdAt == 0) revert CompanionNotFound();
        if (hasRated[msg.sender][companionId]) revert AlreadyRated();

        hasRated[msg.sender][companionId] = true;
        c.totalRatings++;
        c.ratingSum += rating;

        emit CompanionRated(companionId, msg.sender, rating);
    }

    // ── Deactivate / Reactivate ────────────────────────────────────────────────
    /// @notice Deactivate a companion (owner or admin).
    function deactivateCompanion(uint256 companionId) external whenNotPaused {
        Companion storage c = companions[companionId];
        if (c.createdAt == 0) revert CompanionNotFound();
        if (msg.sender != c.companionOwner && msg.sender != owner()) revert NotCompanionOwner();
        c.active = false;
        emit CompanionDeactivated(companionId);
    }

    /// @notice Reactivate a companion.
    function reactivateCompanion(uint256 companionId) external whenNotPaused {
        Companion storage c = companions[companionId];
        if (c.createdAt == 0) revert CompanionNotFound();
        if (msg.sender != c.companionOwner) revert NotCompanionOwner();
        c.active = true;
        emit CompanionReactivated(companionId);
    }

    // ── Withdraw ───────────────────────────────────────────────────────────────
    /// @notice Companion owner withdraws accumulated interaction revenue.
    function withdrawOwnerBalance() external nonReentrant whenNotPaused {
        uint256 amount = ownerBalance[msg.sender];
        if (amount == 0) revert NothingToWithdraw();
        ownerBalance[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit OwnerWithdrew(msg.sender, amount);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────
    /// @notice Set registration fee.
    function setRegistrationFee(uint256 fee) external onlyOwner {
        registrationFee = fee;
        emit RegistrationFeeUpdated(fee);
    }

    /// @notice Set platform fee (max 10 %).
    function setPlatformFee(uint256 newBps) external onlyOwner {
        if (newBps > 1000) revert InvalidRating();
        platformFeeBps = newBps;
        emit PlatformFeeUpdated(newBps);
    }

    /// @notice Withdraw platform fees.
    function withdrawPlatformFees() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        if (bal == 0) revert NothingToWithdraw();
        (bool ok, ) = payable(owner()).call{value: bal}("");
        if (!ok) revert TransferFailed();
    }

    // ── Views ──────────────────────────────────────────────────────────────────
    /// @notice Get companions owned by an address.
    function getOwnedCompanions(address user) external view returns (uint256[] memory) {
        return _ownedCompanions[user];
    }

    /// @notice Get average rating (multiplied by 100 for precision, e.g. 450 = 4.50).
    function getAverageRating(uint256 companionId) external view returns (uint256) {
        Companion storage c = companions[companionId];
        if (c.totalRatings == 0) return 0;
        return (c.ratingSum * 100) / c.totalRatings;
    }

    /// @notice Get interaction history for a companion.
    function getInteractions(uint256 companionId) external view returns (Interaction[] memory) {
        return _interactions[companionId];
    }
}
