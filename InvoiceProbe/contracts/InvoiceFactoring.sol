// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title InvoiceFactoring
 * @author ProbeChain Rydberg Testnet
 * @notice Decentralized invoice factoring: create invoices, sell them to factors at discount, settle on due date
 * @dev Invoices as on-chain instruments with factoring, settlement, and payment claims
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

contract InvoiceFactoring is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum InvoiceStatus { Created, Factored, Settled, Overdue, Defaulted }

    // ---------- Structs ----------
    struct Invoice {
        uint256 id;
        address creditor;
        address debtor;
        uint256 amount;
        uint256 dueDate;
        bytes32 documentHash;
        InvoiceStatus status;
        uint256 createdAt;
        address factor;
        uint256 discountBPS;
        uint256 factoredAmount;
        uint256 settledAt;
        uint256 settledAmount;
    }

    // ---------- State ----------
    uint256 public nextInvoiceId;
    uint256 public maxDiscountBPS;
    uint256 public platformFeeBPS;
    uint256 public defaultPeriod;

    mapping(uint256 => Invoice) public invoices;
    mapping(address => uint256[]) public creditorInvoices;
    mapping(address => uint256[]) public debtorInvoices;
    mapping(address => uint256[]) public factorInvoices;
    mapping(address => uint256) public factorEarnings;
    mapping(address => uint256) public creditorBalance;

    // ---------- Events ----------
    /// @notice Emitted when an invoice is created
    event InvoiceCreated(uint256 indexed invoiceId, address indexed creditor, address indexed debtor, uint256 amount, uint256 dueDate);
    /// @notice Emitted when an invoice is factored (sold at discount)
    event InvoiceFactored(uint256 indexed invoiceId, address indexed factor, uint256 discountBPS, uint256 factoredAmount);
    /// @notice Emitted when an invoice is settled by the debtor
    event InvoiceSettled(uint256 indexed invoiceId, address indexed debtor, uint256 amount);
    /// @notice Emitted when a factor or creditor claims payment
    event PaymentClaimed(address indexed claimant, uint256 amount);
    /// @notice Emitted when an invoice defaults
    event InvoiceDefaulted(uint256 indexed invoiceId);

    // ---------- Constructor ----------
    constructor(uint256 _maxDiscountBPS, uint256 _platformFeeBPS, uint256 _defaultPeriod)
        Ownable() ReentrancyGuard() Pausable()
    {
        require(_maxDiscountBPS <= 5000, "Max discount too high");
        require(_platformFeeBPS <= 500, "Fee too high");
        maxDiscountBPS = _maxDiscountBPS;
        platformFeeBPS = _platformFeeBPS;
        defaultPeriod = _defaultPeriod;
        nextInvoiceId = 1;
    }

    /**
     * @notice Create an invoice
     * @param debtor The party who owes payment
     * @param amount Invoice amount in wei
     * @param dueDate Payment due date timestamp
     * @param documentHash IPFS hash of invoice document
     * @return invoiceId The created invoice ID
     */
    function createInvoice(address debtor, uint256 amount, uint256 dueDate, bytes32 documentHash)
        external
        whenNotPaused
        returns (uint256 invoiceId)
    {
        require(debtor != address(0) && debtor != msg.sender, "Invalid debtor");
        require(amount > 0, "Zero amount");
        require(dueDate > block.timestamp, "Due date in the past");
        require(documentHash != bytes32(0), "Empty document hash");

        invoiceId = nextInvoiceId++;
        Invoice storage inv = invoices[invoiceId];
        inv.id = invoiceId;
        inv.creditor = msg.sender;
        inv.debtor = debtor;
        inv.amount = amount;
        inv.dueDate = dueDate;
        inv.documentHash = documentHash;
        inv.status = InvoiceStatus.Created;
        inv.createdAt = block.timestamp;

        creditorInvoices[msg.sender].push(invoiceId);
        debtorInvoices[debtor].push(invoiceId);

        emit InvoiceCreated(invoiceId, msg.sender, debtor, amount, dueDate);
    }

    /**
     * @notice Factor an invoice (buy it at discount)
     * @param invoiceId The invoice to factor
     * @param discountBPS Discount in basis points the factor wants
     */
    function factorInvoice(uint256 invoiceId, uint256 discountBPS)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        Invoice storage inv = invoices[invoiceId];
        require(inv.status == InvoiceStatus.Created, "Not available for factoring");
        require(discountBPS <= maxDiscountBPS, "Discount exceeds maximum");
        require(msg.sender != inv.creditor && msg.sender != inv.debtor, "Creditor/debtor cannot factor");

        uint256 factoredAmount = inv.amount - ((inv.amount * discountBPS) / 10000);
        require(msg.value >= factoredAmount, "Insufficient payment");

        inv.status = InvoiceStatus.Factored;
        inv.factor = msg.sender;
        inv.discountBPS = discountBPS;
        inv.factoredAmount = factoredAmount;

        // Pay the creditor the factored amount (minus platform fee)
        uint256 fee = (factoredAmount * platformFeeBPS) / 10000;
        creditorBalance[inv.creditor] += factoredAmount - fee;

        factorInvoices[msg.sender].push(invoiceId);
        emit InvoiceFactored(invoiceId, msg.sender, discountBPS, factoredAmount);
    }

    /**
     * @notice Debtor settles an invoice
     * @param invoiceId The invoice to settle
     */
    function settleInvoice(uint256 invoiceId)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        Invoice storage inv = invoices[invoiceId];
        require(msg.sender == inv.debtor, "Only debtor can settle");
        require(inv.status == InvoiceStatus.Created || inv.status == InvoiceStatus.Factored, "Cannot settle");
        require(msg.value >= inv.amount, "Insufficient payment");

        inv.status = InvoiceStatus.Settled;
        inv.settledAt = block.timestamp;
        inv.settledAmount = msg.value;

        if (inv.factor != address(0)) {
            // Pay the factor the full invoice amount (they profit the discount)
            factorEarnings[inv.factor] += inv.amount;
        } else {
            // Pay the creditor
            creditorBalance[inv.creditor] += inv.amount;
        }

        emit InvoiceSettled(invoiceId, msg.sender, msg.value);
    }

    /**
     * @notice Claim accumulated payment
     */
    function claimPayment() external nonReentrant {
        uint256 credBal = creditorBalance[msg.sender];
        uint256 factBal = factorEarnings[msg.sender];
        uint256 total = credBal + factBal;
        require(total > 0, "No payment to claim");

        creditorBalance[msg.sender] = 0;
        factorEarnings[msg.sender] = 0;

        (bool ok, ) = msg.sender.call{value: total}("");
        require(ok, "Transfer failed");
        emit PaymentClaimed(msg.sender, total);
    }

    /**
     * @notice Mark an overdue invoice as defaulted
     * @param invoiceId The overdue invoice
     */
    function markDefaulted(uint256 invoiceId) external {
        Invoice storage inv = invoices[invoiceId];
        require(
            inv.status == InvoiceStatus.Created || inv.status == InvoiceStatus.Factored,
            "Cannot default"
        );
        require(block.timestamp > inv.dueDate + defaultPeriod, "Default period not reached");

        inv.status = InvoiceStatus.Defaulted;
        emit InvoiceDefaulted(invoiceId);
    }

    // ---------- View ----------
    function getCreditorInvoices(address creditor) external view returns (uint256[] memory) {
        return creditorInvoices[creditor];
    }

    function getDebtorInvoices(address debtor) external view returns (uint256[] memory) {
        return debtorInvoices[debtor];
    }

    function getFactorInvoices(address factor) external view returns (uint256[] memory) {
        return factorInvoices[factor];
    }

    function isOverdue(uint256 invoiceId) external view returns (bool) {
        Invoice storage inv = invoices[invoiceId];
        return (inv.status != InvoiceStatus.Settled && inv.status != InvoiceStatus.Defaulted && block.timestamp > inv.dueDate);
    }

    function setMaxDiscount(uint256 _maxBPS) external onlyOwner {
        require(_maxBPS <= 5000, "Too high");
        maxDiscountBPS = _maxBPS;
    }

    function withdrawFees() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "No fees");
        (bool ok, ) = owner().call{value: bal}("");
        require(ok, "Withdraw failed");
    }
}
