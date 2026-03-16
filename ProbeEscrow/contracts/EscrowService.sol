// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title EscrowService
 * @author ProbeChain
 * @notice Three-party escrow service with dispute resolution
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() { _status = _NOT_ENTERED; }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

abstract contract Pausable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function _pause() internal whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function _unpause() internal whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

contract EscrowService is Ownable, ReentrancyGuard, Pausable {
    /// @notice Escrow status
    enum EscrowStatus { Active, Released, Refunded, Disputed, Resolved }

    /// @notice Escrow record
    struct Escrow {
        uint256 id;
        address buyer;
        address seller;
        address arbiter;
        uint256 amount;
        EscrowStatus status;
        uint256 createdAt;
        string description;
    }

    /// @dev Escrow counter
    uint256 private _nextEscrowId;

    /// @dev Platform fee basis points
    uint256 public platformFeeBPS;

    /// @dev Escrow ID => Escrow
    mapping(uint256 => Escrow) private _escrows;

    /// @dev All escrow IDs
    uint256[] private _escrowIds;

    /// @dev User => escrow IDs (as buyer, seller, or arbiter)
    mapping(address => uint256[]) private _userEscrows;

    /// @dev Total escrowed value
    uint256 public totalEscrowed;

    /// @dev Collected fees
    uint256 public collectedFees;

    // ───────── Events ─────────

    /// @notice Emitted when an escrow is created
    event EscrowCreated(uint256 indexed escrowId, address indexed buyer, address indexed seller, address arbiter, uint256 amount);

    /// @notice Emitted when funds are released to seller
    event ReleasedToSeller(uint256 indexed escrowId, address indexed seller, uint256 amount);

    /// @notice Emitted when funds are refunded to buyer
    event RefundedToBuyer(uint256 indexed escrowId, address indexed buyer, uint256 amount);

    /// @notice Emitted when a dispute is raised
    event DisputeRaised(uint256 indexed escrowId, address indexed disputedBy);

    /// @notice Emitted when a dispute is resolved
    event DisputeResolved(uint256 indexed escrowId, address indexed resolvedBy, bool releasedToSeller);

    /// @notice Emitted when platform fee is updated
    event PlatformFeeUpdated(uint256 newFeeBPS);

    // ───────── Constructor ─────────

    constructor() {
        _nextEscrowId = 1;
        platformFeeBPS = 100; // 1%
    }

    // ───────── Admin ─────────

    function setPlatformFee(uint256 feeBPS) external onlyOwner {
        require(feeBPS <= 500, "Escrow: fee too high"); // Max 5%
        platformFeeBPS = feeBPS;
        emit PlatformFeeUpdated(feeBPS);
    }

    function withdrawFees(address payable to) external onlyOwner nonReentrant {
        require(collectedFees > 0, "Escrow: no fees");
        uint256 amount = collectedFees;
        collectedFees = 0;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Escrow: transfer failed");
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Create a new escrow
    /// @param seller The seller address
    /// @param arbiter The arbiter for disputes
    /// @param description Description of the deal
    /// @return escrowId The new escrow ID
    function createEscrow(
        address seller,
        address arbiter,
        string calldata description
    ) external payable whenNotPaused returns (uint256 escrowId) {
        require(msg.value > 0, "Escrow: zero amount");
        require(seller != address(0), "Escrow: zero seller");
        require(arbiter != address(0), "Escrow: zero arbiter");
        require(seller != msg.sender, "Escrow: buyer is seller");
        require(arbiter != msg.sender && arbiter != seller, "Escrow: arbiter conflict");

        escrowId = _nextEscrowId++;

        _escrows[escrowId] = Escrow({
            id: escrowId,
            buyer: msg.sender,
            seller: seller,
            arbiter: arbiter,
            amount: msg.value,
            status: EscrowStatus.Active,
            createdAt: block.timestamp,
            description: description
        });

        _escrowIds.push(escrowId);
        _userEscrows[msg.sender].push(escrowId);
        _userEscrows[seller].push(escrowId);
        _userEscrows[arbiter].push(escrowId);
        totalEscrowed += msg.value;

        emit EscrowCreated(escrowId, msg.sender, seller, arbiter, msg.value);
    }

    /// @notice Release funds to seller (buyer or arbiter)
    /// @param escrowId The escrow to release
    function releaseToSeller(uint256 escrowId) external whenNotPaused nonReentrant {
        Escrow storage e = _escrows[escrowId];
        require(e.id != 0, "Escrow: not found");
        require(
            e.status == EscrowStatus.Active || e.status == EscrowStatus.Disputed,
            "Escrow: invalid status"
        );
        require(
            msg.sender == e.buyer || msg.sender == e.arbiter,
            "Escrow: not authorized"
        );

        e.status = (e.status == EscrowStatus.Disputed) ? EscrowStatus.Resolved : EscrowStatus.Released;

        uint256 fee = (e.amount * platformFeeBPS) / 10000;
        uint256 payment = e.amount - fee;
        collectedFees += fee;
        totalEscrowed -= e.amount;

        (bool sent, ) = e.seller.call{value: payment}("");
        require(sent, "Escrow: transfer failed");

        emit ReleasedToSeller(escrowId, e.seller, payment);
    }

    /// @notice Refund buyer (arbiter only, or buyer if active)
    /// @param escrowId The escrow to refund
    function refundBuyer(uint256 escrowId) external whenNotPaused nonReentrant {
        Escrow storage e = _escrows[escrowId];
        require(e.id != 0, "Escrow: not found");
        require(
            e.status == EscrowStatus.Active || e.status == EscrowStatus.Disputed,
            "Escrow: invalid status"
        );
        require(msg.sender == e.arbiter, "Escrow: not arbiter");

        e.status = (e.status == EscrowStatus.Disputed) ? EscrowStatus.Resolved : EscrowStatus.Refunded;
        totalEscrowed -= e.amount;

        (bool sent, ) = e.buyer.call{value: e.amount}("");
        require(sent, "Escrow: transfer failed");

        emit RefundedToBuyer(escrowId, e.buyer, e.amount);
    }

    /// @notice Raise a dispute (buyer or seller)
    /// @param escrowId The escrow to dispute
    function disputeEscrow(uint256 escrowId) external whenNotPaused {
        Escrow storage e = _escrows[escrowId];
        require(e.id != 0, "Escrow: not found");
        require(e.status == EscrowStatus.Active, "Escrow: not active");
        require(
            msg.sender == e.buyer || msg.sender == e.seller,
            "Escrow: not party"
        );

        e.status = EscrowStatus.Disputed;
        emit DisputeRaised(escrowId, msg.sender);
    }

    // ───────── View Functions ─────────

    /// @notice Get escrow details
    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        require(_escrows[escrowId].id != 0, "Escrow: not found");
        return _escrows[escrowId];
    }

    /// @notice Get user's escrow IDs
    function getUserEscrows(address user) external view returns (uint256[] memory) {
        return _userEscrows[user];
    }

    /// @notice Total escrows created
    function totalEscrows() external view returns (uint256) {
        return _nextEscrowId - 1;
    }

    /// @notice Get contract balance
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
