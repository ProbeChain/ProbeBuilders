// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title InvoiceSystem
 * @author ProbeChain Labs
 * @notice Merchant payment gateway with invoice management, multi-token support,
 *         and auto-release after a confirmation period.
 * @dev Designed for ProbeChain Rydberg Testnet (Chain ID 8004, EVM London).
 */

// ---------------------------------------------------------------------------
// Inline: Ownable
// ---------------------------------------------------------------------------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ---------------------------------------------------------------------------
// Inline: ReentrancyGuard
// ---------------------------------------------------------------------------
abstract contract ReentrancyGuard {
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    constructor() { _status = _NOT_ENTERED; }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// ---------------------------------------------------------------------------
// Inline: Pausable
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Minimal ERC-20 interface
// ---------------------------------------------------------------------------
interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

// ---------------------------------------------------------------------------
// Main Contract
// ---------------------------------------------------------------------------
contract InvoiceSystem is Ownable, ReentrancyGuard, Pausable {
    /// @notice Confirmation period before auto-release (seconds).
    uint256 public confirmationPeriod;

    enum InvoiceStatus { Pending, Paid, Released, Refunded, Expired }

    struct Invoice {
        uint256 id;
        address merchant;
        address payer;
        uint256 amount;
        address token;          // address(0) = native PROBE
        uint256 dueDate;
        string memo;
        InvoiceStatus status;
        uint256 paidAt;
        uint256 createdAt;
    }

    uint256 private _nextInvoiceId;
    mapping(uint256 => Invoice) public invoices;
    mapping(address => uint256[]) public merchantInvoices;

    // ---- Events ----------------------------------------------------------
    event InvoiceCreated(uint256 indexed invoiceId, address indexed merchant, uint256 amount, address token, uint256 dueDate, string memo);
    event InvoicePaid(uint256 indexed invoiceId, address indexed payer, uint256 amount);
    event InvoiceReleased(uint256 indexed invoiceId, address indexed merchant, uint256 amount);
    event InvoiceRefunded(uint256 indexed invoiceId, address indexed payer, uint256 amount);
    event ConfirmationPeriodUpdated(uint256 newPeriod);

    constructor(uint256 _confirmationPeriod) {
        confirmationPeriod = _confirmationPeriod;
        _nextInvoiceId = 1;
    }

    // ---- Core Functions --------------------------------------------------

    /**
     * @notice Create a new invoice.
     * @param merchant  Recipient merchant address.
     * @param amount    Payment amount (in token decimals or wei for native).
     * @param token     ERC-20 token address, or address(0) for native PROBE.
     * @param dueDate   Unix timestamp for payment deadline.
     * @param memo      Human-readable memo / reference.
     * @return invoiceId The newly created invoice identifier.
     */
    function createInvoice(
        address merchant,
        uint256 amount,
        address token,
        uint256 dueDate,
        string calldata memo
    ) external whenNotPaused returns (uint256 invoiceId) {
        require(merchant != address(0), "Invalid merchant");
        require(amount > 0, "Zero amount");
        require(dueDate > block.timestamp, "Due date in past");

        invoiceId = _nextInvoiceId++;
        invoices[invoiceId] = Invoice({
            id: invoiceId,
            merchant: merchant,
            payer: address(0),
            amount: amount,
            token: token,
            dueDate: dueDate,
            memo: memo,
            status: InvoiceStatus.Pending,
            paidAt: 0,
            createdAt: block.timestamp
        });

        merchantInvoices[merchant].push(invoiceId);
        emit InvoiceCreated(invoiceId, merchant, amount, token, dueDate, memo);
    }

    /**
     * @notice Pay an invoice. For native PROBE send msg.value; for ERC-20 approve first.
     * @param invoiceId The invoice to pay.
     */
    function payInvoice(uint256 invoiceId) external payable nonReentrant whenNotPaused {
        Invoice storage inv = invoices[invoiceId];
        require(inv.id != 0, "Invoice not found");
        require(inv.status == InvoiceStatus.Pending, "Not payable");
        require(block.timestamp <= inv.dueDate, "Invoice expired");

        if (inv.token == address(0)) {
            require(msg.value == inv.amount, "Incorrect PROBE amount");
        } else {
            require(msg.value == 0, "No PROBE needed for token invoice");
            bool ok = IERC20(inv.token).transferFrom(msg.sender, address(this), inv.amount);
            require(ok, "Token transfer failed");
        }

        inv.payer = msg.sender;
        inv.status = InvoiceStatus.Paid;
        inv.paidAt = block.timestamp;

        emit InvoicePaid(invoiceId, msg.sender, inv.amount);
    }

    /**
     * @notice Release funds to merchant after confirmation period.
     * @param invoiceId The invoice to release.
     */
    function releaseInvoice(uint256 invoiceId) external nonReentrant whenNotPaused {
        Invoice storage inv = invoices[invoiceId];
        require(inv.status == InvoiceStatus.Paid, "Not paid");
        require(
            block.timestamp >= inv.paidAt + confirmationPeriod,
            "Confirmation period not elapsed"
        );

        inv.status = InvoiceStatus.Released;

        if (inv.token == address(0)) {
            (bool success, ) = payable(inv.merchant).call{value: inv.amount}("");
            require(success, "Transfer failed");
        } else {
            bool ok = IERC20(inv.token).transfer(inv.merchant, inv.amount);
            require(ok, "Token transfer failed");
        }

        emit InvoiceReleased(invoiceId, inv.merchant, inv.amount);
    }

    /**
     * @notice Refund a paid invoice (owner or merchant only, before release).
     * @param invoiceId The invoice to refund.
     */
    function refundInvoice(uint256 invoiceId) external nonReentrant whenNotPaused {
        Invoice storage inv = invoices[invoiceId];
        require(inv.status == InvoiceStatus.Paid, "Not paid");
        require(
            msg.sender == owner() || msg.sender == inv.merchant,
            "Not authorized"
        );

        inv.status = InvoiceStatus.Refunded;

        if (inv.token == address(0)) {
            (bool success, ) = payable(inv.payer).call{value: inv.amount}("");
            require(success, "Refund failed");
        } else {
            bool ok = IERC20(inv.token).transfer(inv.payer, inv.amount);
            require(ok, "Token refund failed");
        }

        emit InvoiceRefunded(invoiceId, inv.payer, inv.amount);
    }

    // ---- Admin -----------------------------------------------------------

    function setConfirmationPeriod(uint256 _period) external onlyOwner {
        confirmationPeriod = _period;
        emit ConfirmationPeriodUpdated(_period);
    }

    // ---- Views -----------------------------------------------------------

    function getInvoice(uint256 invoiceId) external view returns (Invoice memory) {
        require(invoices[invoiceId].id != 0, "Not found");
        return invoices[invoiceId];
    }

    function getMerchantInvoiceIds(address merchant) external view returns (uint256[] memory) {
        return merchantInvoices[merchant];
    }

    function totalInvoices() external view returns (uint256) {
        return _nextInvoiceId - 1;
    }

    receive() external payable {}
}
