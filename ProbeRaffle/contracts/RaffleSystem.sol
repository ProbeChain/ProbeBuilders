// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title RaffleSystem
 * @author ProbeChain
 * @notice On-chain raffle system with blockhash-based randomness
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

contract RaffleSystem is Ownable, ReentrancyGuard, Pausable {
    /// @notice Raffle status
    enum RaffleStatus { Active, Drawing, Completed, Cancelled }

    /// @notice Raffle record
    struct Raffle {
        uint256 id;
        address creator;
        string prize;
        uint256 ticketPrice;
        uint256 maxTickets;
        uint256 ticketsSold;
        uint256 endTime;
        RaffleStatus status;
        address winner;
        uint256 prizePool;
        uint256 createdAt;
        uint256 drawBlock;
    }

    /// @dev Raffle counter
    uint256 private _nextRaffleId;

    /// @dev Platform fee BPS
    uint256 public platformFeeBPS;

    /// @dev Raffle ID => Raffle
    mapping(uint256 => Raffle) private _raffles;

    /// @dev Raffle ID => ticket index => buyer address
    mapping(uint256 => mapping(uint256 => address)) private _tickets;

    /// @dev Raffle ID => buyer => ticket count
    mapping(uint256 => mapping(address => uint256)) private _userTickets;

    /// @dev All raffle IDs
    uint256[] private _raffleIds;

    /// @dev Collected fees
    uint256 public collectedFees;

    // ───────── Events ─────────

    /// @notice Emitted when a raffle is created
    event RaffleCreated(uint256 indexed raffleId, address indexed creator, string prize, uint256 ticketPrice, uint256 maxTickets);

    /// @notice Emitted when a ticket is purchased
    event TicketPurchased(uint256 indexed raffleId, address indexed buyer, uint256 ticketIndex);

    /// @notice Emitted when a winner is drawn
    event WinnerDrawn(uint256 indexed raffleId, address indexed winner, uint256 prizeAmount);

    /// @notice Emitted when prize is claimed
    event PrizeClaimed(uint256 indexed raffleId, address indexed winner, uint256 amount);

    /// @notice Emitted when a raffle is cancelled
    event RaffleCancelled(uint256 indexed raffleId);

    // ───────── Constructor ─────────

    constructor() {
        _nextRaffleId = 1;
        platformFeeBPS = 300; // 3%
    }

    // ───────── Admin ─────────

    function setPlatformFee(uint256 bps) external onlyOwner {
        require(bps <= 500, "Raffle: fee too high");
        platformFeeBPS = bps;
    }

    function withdrawFees(address payable to) external onlyOwner nonReentrant {
        require(collectedFees > 0, "Raffle: no fees");
        uint256 amount = collectedFees;
        collectedFees = 0;
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Raffle: transfer failed");
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Create a new raffle
    /// @param prize Description of the prize
    /// @param ticketPrice Price per ticket in wei
    /// @param maxTickets Maximum tickets available
    /// @param duration Duration in seconds
    /// @return raffleId The new raffle ID
    function createRaffle(
        string calldata prize,
        uint256 ticketPrice,
        uint256 maxTickets,
        uint256 duration
    ) external payable whenNotPaused returns (uint256 raffleId) {
        require(bytes(prize).length > 0, "Raffle: empty prize");
        require(ticketPrice > 0, "Raffle: zero price");
        require(maxTickets > 0 && maxTickets <= 10000, "Raffle: invalid max");
        require(duration >= 1 hours, "Raffle: too short");

        raffleId = _nextRaffleId++;

        _raffles[raffleId] = Raffle({
            id: raffleId,
            creator: msg.sender,
            prize: prize,
            ticketPrice: ticketPrice,
            maxTickets: maxTickets,
            ticketsSold: 0,
            endTime: block.timestamp + duration,
            status: RaffleStatus.Active,
            winner: address(0),
            prizePool: msg.value,
            createdAt: block.timestamp,
            drawBlock: 0
        });

        _raffleIds.push(raffleId);

        emit RaffleCreated(raffleId, msg.sender, prize, ticketPrice, maxTickets);
    }

    /// @notice Buy a raffle ticket
    /// @param raffleId The raffle to buy a ticket for
    function buyTicket(uint256 raffleId) external payable whenNotPaused nonReentrant {
        Raffle storage r = _raffles[raffleId];
        require(r.id != 0, "Raffle: not found");
        require(r.status == RaffleStatus.Active, "Raffle: not active");
        require(block.timestamp < r.endTime, "Raffle: ended");
        require(r.ticketsSold < r.maxTickets, "Raffle: sold out");
        require(msg.value >= r.ticketPrice, "Raffle: insufficient payment");

        uint256 ticketIndex = r.ticketsSold;
        _tickets[raffleId][ticketIndex] = msg.sender;
        _userTickets[raffleId][msg.sender]++;
        r.ticketsSold++;
        r.prizePool += r.ticketPrice;

        // Refund excess
        if (msg.value > r.ticketPrice) {
            (bool sent, ) = msg.sender.call{value: msg.value - r.ticketPrice}("");
            require(sent, "Raffle: refund failed");
        }

        emit TicketPurchased(raffleId, msg.sender, ticketIndex);
    }

    /// @notice Draw the winner using blockhash randomness
    /// @param raffleId The raffle to draw
    function drawWinner(uint256 raffleId) external whenNotPaused nonReentrant {
        Raffle storage r = _raffles[raffleId];
        require(r.id != 0, "Raffle: not found");
        require(r.status == RaffleStatus.Active, "Raffle: not active");
        require(
            block.timestamp >= r.endTime || r.ticketsSold >= r.maxTickets,
            "Raffle: not ended"
        );
        require(r.ticketsSold > 0, "Raffle: no tickets sold");
        require(
            msg.sender == r.creator || msg.sender == owner(),
            "Raffle: not authorized"
        );

        // Use blockhash for randomness
        uint256 randomSeed = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    r.ticketsSold,
                    msg.sender
                )
            )
        );

        uint256 winnerIndex = randomSeed % r.ticketsSold;
        r.winner = _tickets[raffleId][winnerIndex];
        r.status = RaffleStatus.Completed;
        r.drawBlock = block.number;

        // Calculate fee
        uint256 fee = (r.prizePool * platformFeeBPS) / 10000;
        collectedFees += fee;
        uint256 prizeAmount = r.prizePool - fee;

        // Transfer prize to winner
        (bool sent, ) = r.winner.call{value: prizeAmount}("");
        require(sent, "Raffle: prize transfer failed");

        emit WinnerDrawn(raffleId, r.winner, prizeAmount);
    }

    /// @notice Cancel a raffle with no tickets sold
    /// @param raffleId The raffle to cancel
    function cancelRaffle(uint256 raffleId) external whenNotPaused nonReentrant {
        Raffle storage r = _raffles[raffleId];
        require(r.id != 0, "Raffle: not found");
        require(r.status == RaffleStatus.Active, "Raffle: not active");
        require(msg.sender == r.creator, "Raffle: not creator");
        require(r.ticketsSold == 0, "Raffle: has tickets");

        r.status = RaffleStatus.Cancelled;

        // Refund initial prize pool
        if (r.prizePool > 0) {
            (bool sent, ) = r.creator.call{value: r.prizePool}("");
            require(sent, "Raffle: refund failed");
        }

        emit RaffleCancelled(raffleId);
    }

    // ───────── View Functions ─────────

    /// @notice Get raffle details
    function getRaffle(uint256 raffleId) external view returns (Raffle memory) {
        require(_raffles[raffleId].id != 0, "Raffle: not found");
        return _raffles[raffleId];
    }

    /// @notice Get ticket holder at index
    function getTicketHolder(uint256 raffleId, uint256 ticketIndex) external view returns (address) {
        return _tickets[raffleId][ticketIndex];
    }

    /// @notice Get user ticket count
    function getUserTicketCount(uint256 raffleId, address user) external view returns (uint256) {
        return _userTickets[raffleId][user];
    }

    /// @notice Total raffles
    function totalRaffles() external view returns (uint256) {
        return _nextRaffleId - 1;
    }
}
