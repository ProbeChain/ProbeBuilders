// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title EventManager
 * @author ProbeChain
 * @notice On-chain event management — create events, sell tickets, check in attendees,
 *         cancel with automatic refunds.
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

// ── EventManager ───────────────────────────────────────────────────────────────
contract EventManager is Ownable, ReentrancyGuard, Pausable {

    enum EventStatus { Active, Cancelled, Completed }

    struct EventInfo {
        uint256 id;
        address organizer;
        string title;
        uint256 date;
        string location;
        uint256 maxAttendees;
        uint256 ticketPrice;
        uint256 registeredCount;
        uint256 checkedInCount;
        uint256 totalCollected;
        EventStatus status;
    }

    uint256 public nextEventId;
    uint256 public platformFeeBps = 250; // 2.5 %

    mapping(uint256 => EventInfo) public events;
    mapping(uint256 => mapping(address => bool)) public isRegistered;
    mapping(uint256 => mapping(address => bool)) public isCheckedIn;
    mapping(uint256 => address[]) private _attendees;

    // ── Events ─────────────────────────────────────────────────────────────────
    event EventCreated(uint256 indexed eventId, address indexed organizer, string title, uint256 date);
    event AttendeeRegistered(uint256 indexed eventId, address indexed attendee);
    event AttendeeCheckedIn(uint256 indexed eventId, address indexed attendee);
    event EventCancelled(uint256 indexed eventId, uint256 refundedTotal);
    event EventCompleted(uint256 indexed eventId, uint256 payout);
    event PlatformFeeUpdated(uint256 newBps);

    // ── Errors ─────────────────────────────────────────────────────────────────
    error InvalidEventParams();
    error EventNotFound();
    error EventNotActive();
    error EventFull();
    error AlreadyRegistered();
    error IncorrectPayment();
    error NotOrganizer();
    error NotRegistered();
    error AlreadyCheckedIn();
    error TransferFailed();
    error EventDateNotPassed();

    // ── Create Event ───────────────────────────────────────────────────────────
    /// @notice Create a new event.
    /// @param title        Event name.
    /// @param date         Unix timestamp of the event.
    /// @param location     Human-readable location string.
    /// @param maxAttendees Maximum number of registrations (0 = unlimited).
    /// @param ticketPrice  Price per ticket in wei (0 = free).
    function createEvent(
        string calldata title,
        uint256 date,
        string calldata location,
        uint256 maxAttendees,
        uint256 ticketPrice
    ) external whenNotPaused returns (uint256 eventId) {
        if (bytes(title).length == 0 || date == 0) revert InvalidEventParams();
        eventId = nextEventId++;
        events[eventId] = EventInfo({
            id: eventId,
            organizer: msg.sender,
            title: title,
            date: date,
            location: location,
            maxAttendees: maxAttendees,
            ticketPrice: ticketPrice,
            registeredCount: 0,
            checkedInCount: 0,
            totalCollected: 0,
            status: EventStatus.Active
        });
        emit EventCreated(eventId, msg.sender, title, date);
    }

    // ── Register ───────────────────────────────────────────────────────────────
    /// @notice Register for an event — pay the ticket price.
    function registerAttendee(uint256 eventId) external payable whenNotPaused {
        EventInfo storage ev = events[eventId];
        if (ev.date == 0) revert EventNotFound();
        if (ev.status != EventStatus.Active) revert EventNotActive();
        if (ev.maxAttendees > 0 && ev.registeredCount >= ev.maxAttendees) revert EventFull();
        if (isRegistered[eventId][msg.sender]) revert AlreadyRegistered();
        if (msg.value != ev.ticketPrice) revert IncorrectPayment();

        isRegistered[eventId][msg.sender] = true;
        _attendees[eventId].push(msg.sender);
        ev.registeredCount++;
        ev.totalCollected += msg.value;
        emit AttendeeRegistered(eventId, msg.sender);
    }

    // ── Check-in ───────────────────────────────────────────────────────────────
    /// @notice Organizer checks in an attendee at the event.
    function checkIn(uint256 eventId, address attendee) external whenNotPaused {
        EventInfo storage ev = events[eventId];
        if (ev.date == 0) revert EventNotFound();
        if (msg.sender != ev.organizer) revert NotOrganizer();
        if (!isRegistered[eventId][attendee]) revert NotRegistered();
        if (isCheckedIn[eventId][attendee]) revert AlreadyCheckedIn();
        isCheckedIn[eventId][attendee] = true;
        ev.checkedInCount++;
        emit AttendeeCheckedIn(eventId, attendee);
    }

    // ── Cancel ─────────────────────────────────────────────────────────────────
    /// @notice Cancel an event and refund all attendees.
    function cancelEvent(uint256 eventId) external nonReentrant whenNotPaused {
        EventInfo storage ev = events[eventId];
        if (ev.date == 0) revert EventNotFound();
        if (msg.sender != ev.organizer && msg.sender != owner()) revert NotOrganizer();
        if (ev.status != EventStatus.Active) revert EventNotActive();
        ev.status = EventStatus.Cancelled;

        uint256 totalRefunded;
        address[] storage attendees = _attendees[eventId];
        for (uint256 i = 0; i < attendees.length; i++) {
            if (ev.ticketPrice > 0) {
                (bool ok, ) = payable(attendees[i]).call{value: ev.ticketPrice}("");
                if (ok) totalRefunded += ev.ticketPrice;
            }
        }
        emit EventCancelled(eventId, totalRefunded);
    }

    // ── Complete & Payout ──────────────────────────────────────────────────────
    /// @notice Organizer completes the event and receives funds (minus platform fee).
    function completeEvent(uint256 eventId) external nonReentrant whenNotPaused {
        EventInfo storage ev = events[eventId];
        if (ev.date == 0) revert EventNotFound();
        if (msg.sender != ev.organizer) revert NotOrganizer();
        if (ev.status != EventStatus.Active) revert EventNotActive();
        if (block.timestamp < ev.date) revert EventDateNotPassed();
        ev.status = EventStatus.Completed;

        uint256 fee = (ev.totalCollected * platformFeeBps) / 10_000;
        uint256 payout = ev.totalCollected - fee;
        if (payout > 0) {
            (bool ok, ) = payable(ev.organizer).call{value: payout}("");
            if (!ok) revert TransferFailed();
        }
        emit EventCompleted(eventId, payout);
    }

    // ── Admin ──────────────────────────────────────────────────────────────────
    /// @notice Update platform fee (max 10 %).
    function setPlatformFee(uint256 newBps) external onlyOwner {
        if (newBps > 1000) revert InvalidEventParams();
        platformFeeBps = newBps;
        emit PlatformFeeUpdated(newBps);
    }

    /// @notice Withdraw accumulated platform fees.
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        if (bal == 0) revert TransferFailed();
        (bool ok, ) = payable(owner()).call{value: bal}("");
        if (!ok) revert TransferFailed();
    }

    // ── Views ──────────────────────────────────────────────────────────────────
    /// @notice Return the attendee list for an event.
    function getAttendees(uint256 eventId) external view returns (address[] memory) {
        return _attendees[eventId];
    }
}
