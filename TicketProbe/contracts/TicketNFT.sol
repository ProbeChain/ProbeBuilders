// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TicketNFT
 * @author ProbeChain Rydberg Testnet
 * @notice ERC-721 event tickets with anti-scalping (max 1.5x original price), validation, and event management
 * @dev Create events, mint tickets, validate at venue, anti-scalp transfer restrictions
 */

// ---------- Inlined Ownable ----------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: caller is not the owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner); _owner = newOwner;
    }
}

// ---------- Inlined ReentrancyGuard ----------
abstract contract ReentrancyGuard {
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    constructor() { _status = _NOT_ENTERED; }
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED; _; _status = _NOT_ENTERED;
    }
}

// ---------- Inlined Pausable ----------
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

// ---------- Minimal ERC-721 ----------
abstract contract ERC721 {
    string public name;
    string public symbol;
    mapping(uint256 => address) internal _owners;
    mapping(address => uint256) internal _balances;
    mapping(uint256 => address) internal _tokenApprovals;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(string memory _name, string memory _symbol) { name = _name; symbol = _symbol; }

    function balanceOf(address o) public view returns (uint256) { return _balances[o]; }
    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _owners[tokenId]; require(o != address(0), "ERC721: nonexistent"); return o;
    }
    function approve(address to, uint256 tokenId) public {
        address o = ownerOf(tokenId);
        require(msg.sender == o || _operatorApprovals[o][msg.sender], "Not authorized");
        _tokenApprovals[tokenId] = to; emit Approval(o, to, tokenId);
    }
    function setApprovalForAll(address op, bool approved) public {
        _operatorApprovals[msg.sender][op] = approved; emit ApprovalForAll(msg.sender, op, approved);
    }
    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0) && _owners[tokenId] == address(0), "Invalid mint");
        _balances[to]++; _owners[tokenId] = to; emit Transfer(address(0), to, tokenId);
    }
    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from && to != address(0), "Invalid transfer");
        _tokenApprovals[tokenId] = address(0); _balances[from]--; _balances[to]++;
        _owners[tokenId] = to; emit Transfer(from, to, tokenId);
    }
    function _isApprovedOrOwner(address s, uint256 t) internal view returns (bool) {
        address o = ownerOf(t);
        return (s == o || _tokenApprovals[t] == s || _operatorApprovals[o][s]);
    }
}

contract TicketNFT is ERC721, Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum EventStatus { Active, SoldOut, Ended, Cancelled }
    enum TicketStatus { Valid, Used, Refunded }

    // ---------- Structs ----------
    struct EventInfo {
        uint256 id;
        address organizer;
        string eventName;
        uint256 date;
        string venue;
        uint256 maxTickets;
        uint256 price;
        uint256 ticketsSold;
        EventStatus status;
        uint256 createdAt;
    }

    struct Ticket {
        uint256 ticketId;
        uint256 eventId;
        uint256 originalPrice;
        TicketStatus status;
        uint256 mintedAt;
        uint256 validatedAt;
        address originalBuyer;
    }

    // ---------- State ----------
    uint256 public nextEventId;
    uint256 public nextTicketId;
    uint256 public platformFeeBPS;
    uint256 public constant ANTI_SCALP_MULTIPLIER_BPS = 15000; // 1.5x = 150%

    mapping(uint256 => EventInfo) public events;
    mapping(uint256 => Ticket) public tickets;
    mapping(uint256 => uint256[]) public eventTickets;
    mapping(address => bool) public authorizedScanners;
    mapping(address => uint256) public organizerEarnings;
    mapping(uint256 => uint256) public ticketResalePrice;

    // ---------- Events ----------
    /// @notice Emitted when an event is created
    event EventCreated(uint256 indexed eventId, address indexed organizer, string eventName, uint256 maxTickets, uint256 price);
    /// @notice Emitted when a ticket is minted
    event TicketMinted(uint256 indexed ticketId, uint256 indexed eventId, address indexed buyer, uint256 price);
    /// @notice Emitted when a ticket is validated at venue
    event TicketValidated(uint256 indexed ticketId, address indexed scanner, uint256 timestamp);
    /// @notice Emitted when a ticket is transferred with anti-scalp enforcement
    event TicketTransferred(uint256 indexed ticketId, address indexed from, address indexed to, uint256 resalePrice);
    /// @notice Emitted when an event is cancelled and refunds issued
    event EventCancelled(uint256 indexed eventId);
    /// @notice Emitted when a ticket is refunded
    event TicketRefunded(uint256 indexed ticketId, address indexed holder, uint256 amount);

    // ---------- Constructor ----------
    constructor(uint256 _feeBPS)
        ERC721("ProbeTicketNFT", "PTKT")
        Ownable() ReentrancyGuard() Pausable()
    {
        require(_feeBPS <= 1000, "Fee too high");
        platformFeeBPS = _feeBPS;
        nextEventId = 1;
        nextTicketId = 1;
    }

    /**
     * @notice Authorize a ticket scanner
     * @param scanner The scanner address
     */
    function authorizeScanner(address scanner) external onlyOwner {
        require(scanner != address(0), "Zero address");
        authorizedScanners[scanner] = true;
    }

    /**
     * @notice Create a new event
     * @param eventName Name of the event
     * @param date Event date (timestamp)
     * @param venue Venue name
     * @param maxTickets Maximum tickets available
     * @param price Ticket price in wei
     * @return eventId The created event ID
     */
    function createEvent(
        string calldata eventName,
        uint256 date,
        string calldata venue,
        uint256 maxTickets,
        uint256 price
    )
        external
        whenNotPaused
        returns (uint256 eventId)
    {
        require(bytes(eventName).length > 0 && bytes(eventName).length <= 128, "Invalid name");
        require(date > block.timestamp, "Date in the past");
        require(bytes(venue).length > 0 && bytes(venue).length <= 256, "Invalid venue");
        require(maxTickets > 0 && maxTickets <= 100000, "Invalid ticket count");

        eventId = nextEventId++;
        EventInfo storage e = events[eventId];
        e.id = eventId;
        e.organizer = msg.sender;
        e.eventName = eventName;
        e.date = date;
        e.venue = venue;
        e.maxTickets = maxTickets;
        e.price = price;
        e.status = EventStatus.Active;
        e.createdAt = block.timestamp;

        emit EventCreated(eventId, msg.sender, eventName, maxTickets, price);
    }

    /**
     * @notice Mint a ticket for an event
     * @param eventId The event to buy a ticket for
     * @return ticketId The minted ticket ID
     */
    function mintTicket(uint256 eventId) external payable nonReentrant whenNotPaused returns (uint256 ticketId) {
        EventInfo storage e = events[eventId];
        require(e.status == EventStatus.Active, "Event not active");
        require(e.ticketsSold < e.maxTickets, "Sold out");
        require(msg.value >= e.price, "Insufficient payment");
        require(block.timestamp < e.date, "Event already started");

        ticketId = nextTicketId++;
        Ticket storage t = tickets[ticketId];
        t.ticketId = ticketId;
        t.eventId = eventId;
        t.originalPrice = e.price;
        t.status = TicketStatus.Valid;
        t.mintedAt = block.timestamp;
        t.originalBuyer = msg.sender;

        _mint(msg.sender, ticketId);
        e.ticketsSold++;
        eventTickets[eventId].push(ticketId);

        uint256 fee = (msg.value * platformFeeBPS) / 10000;
        organizerEarnings[e.organizer] += msg.value - fee;

        if (e.ticketsSold == e.maxTickets) {
            e.status = EventStatus.SoldOut;
        }

        emit TicketMinted(ticketId, eventId, msg.sender, msg.value);
    }

    /**
     * @notice Validate a ticket at the event venue (scanner only)
     * @param ticketId The ticket to validate
     */
    function validateTicket(uint256 ticketId) external whenNotPaused {
        require(authorizedScanners[msg.sender], "Not an authorized scanner");
        Ticket storage t = tickets[ticketId];
        require(t.status == TicketStatus.Valid, "Ticket not valid");

        t.status = TicketStatus.Used;
        t.validatedAt = block.timestamp;
        emit TicketValidated(ticketId, msg.sender, block.timestamp);
    }

    /**
     * @notice Transfer a ticket with anti-scalping price cap (max 1.5x original)
     * @param to Recipient address
     * @param ticketId The ticket to transfer
     * @param resalePrice The resale price (must be <= 1.5x original)
     */
    function transferTicket(address to, uint256 ticketId, uint256 resalePrice)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(_isApprovedOrOwner(msg.sender, ticketId), "Not authorized");
        Ticket storage t = tickets[ticketId];
        require(t.status == TicketStatus.Valid, "Ticket not valid");

        uint256 maxResalePrice = (t.originalPrice * ANTI_SCALP_MULTIPLIER_BPS) / 10000;
        require(resalePrice <= maxResalePrice, "Exceeds anti-scalp price cap (1.5x)");

        ticketResalePrice[ticketId] = resalePrice;
        _transfer(msg.sender, to, ticketId);
        emit TicketTransferred(ticketId, msg.sender, to, resalePrice);
    }

    /**
     * @notice Cancel an event (organizer only)
     * @param eventId The event to cancel
     */
    function cancelEvent(uint256 eventId) external {
        EventInfo storage e = events[eventId];
        require(e.organizer == msg.sender || msg.sender == owner(), "Not authorized");
        require(e.status == EventStatus.Active || e.status == EventStatus.SoldOut, "Cannot cancel");
        e.status = EventStatus.Cancelled;
        emit EventCancelled(eventId);
    }

    /**
     * @notice Refund a ticket for a cancelled event
     * @param ticketId The ticket to refund
     */
    function refundTicket(uint256 ticketId) external nonReentrant {
        Ticket storage t = tickets[ticketId];
        require(ownerOf(ticketId) == msg.sender, "Not ticket owner");
        require(t.status == TicketStatus.Valid, "Not valid");
        EventInfo storage e = events[t.eventId];
        require(e.status == EventStatus.Cancelled, "Event not cancelled");

        t.status = TicketStatus.Refunded;
        uint256 refund = t.originalPrice;
        organizerEarnings[e.organizer] -= refund;
        (bool ok, ) = msg.sender.call{value: refund}("");
        require(ok, "Refund failed");
        emit TicketRefunded(ticketId, msg.sender, refund);
    }

    /**
     * @notice Organizer claims earnings
     */
    function claimEarnings() external nonReentrant {
        uint256 amount = organizerEarnings[msg.sender];
        require(amount > 0, "No earnings");
        organizerEarnings[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
    }

    // ---------- View ----------
    function getEventTickets(uint256 eventId) external view returns (uint256[] memory) {
        return eventTickets[eventId];
    }

    function getMaxResalePrice(uint256 ticketId) external view returns (uint256) {
        return (tickets[ticketId].originalPrice * ANTI_SCALP_MULTIPLIER_BPS) / 10000;
    }

    function setPlatformFee(uint256 _feeBPS) external onlyOwner {
        require(_feeBPS <= 1000, "Fee too high");
        platformFeeBPS = _feeBPS;
    }
}
