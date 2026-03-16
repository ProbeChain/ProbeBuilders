// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PaymentGateway
 * @author ProbeBuilders
 * @notice Payment gateway with merchant registration and multi-token support for ProbeChain.
 * @dev Supports createPayment, confirmPayment, refundPayment, and merchant management.
 */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: not owner");
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

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

    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function _pause() internal { _paused = true; emit Paused(msg.sender); }
    function _unpause() internal { _paused = false; emit Unpaused(msg.sender); }
}

contract PaymentGateway is Ownable, ReentrancyGuard, Pausable {
    // ---- Types ----
    enum PaymentStatus { Pending, Confirmed, Refunded, Expired, Disputed }

    struct Merchant {
        address wallet;
        string name;
        bool isActive;
        uint256 totalReceived;
        uint256 totalRefunded;
        uint256 registeredAt;
    }

    struct Payment {
        uint256 id;
        bytes32 merchantId;
        address payer;
        address token;       // address(0) for native
        uint256 amount;
        uint256 createdAt;
        uint256 expiresAt;
        PaymentStatus status;
        string reference;    // order ID or external reference
    }

    // ---- State ----
    mapping(bytes32 => Merchant) public merchants;
    bytes32[] public merchantIds;

    mapping(uint256 => Payment) public payments;
    uint256 public nextPaymentId;

    /// @notice Supported payment tokens
    mapping(address => bool) public supportedTokens;

    /// @notice Platform fee in basis points (e.g., 100 = 1%)
    uint256 public platformFeeBps = 100;
    uint256 public constant MAX_FEE_BPS = 500;
    address public feeCollector;

    /// @notice Default payment expiry (24 hours)
    uint256 public defaultExpiry = 24 hours;

    // ---- Events ----
    event MerchantRegistered(bytes32 indexed merchantId, address indexed wallet, string name);
    event MerchantUpdated(bytes32 indexed merchantId, bool isActive);
    event PaymentCreated(uint256 indexed paymentId, bytes32 indexed merchantId, address indexed payer, uint256 amount);
    event PaymentConfirmed(uint256 indexed paymentId, uint256 merchantAmount, uint256 fee);
    event PaymentRefunded(uint256 indexed paymentId, uint256 amount);
    event PaymentExpired(uint256 indexed paymentId);
    event PaymentDisputed(uint256 indexed paymentId);
    event TokenSupported(address indexed token, bool status);
    event FeeUpdated(uint256 newFeeBps);

    constructor(address _feeCollector) {
        feeCollector = _feeCollector;
        // Native currency always supported
        supportedTokens[address(0)] = true;
    }

    // ---- Admin ----

    function setSupportedToken(address token, bool status) external onlyOwner {
        supportedTokens[token] = status;
        emit TokenSupported(token, status);
    }

    function setPlatformFee(uint256 _feeBps) external onlyOwner {
        require(_feeBps <= MAX_FEE_BPS, "PayGateway: fee too high");
        platformFeeBps = _feeBps;
        emit FeeUpdated(_feeBps);
    }

    function setFeeCollector(address _collector) external onlyOwner {
        require(_collector != address(0), "PayGateway: zero address");
        feeCollector = _collector;
    }

    function setDefaultExpiry(uint256 _expiry) external onlyOwner {
        require(_expiry >= 1 hours && _expiry <= 7 days, "PayGateway: invalid expiry");
        defaultExpiry = _expiry;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ---- Merchant Management ----

    /// @notice Register a new merchant
    function registerMerchant(string calldata name_, address wallet) external onlyOwner returns (bytes32 merchantId) {
        require(wallet != address(0), "PayGateway: zero wallet");
        merchantId = keccak256(abi.encodePacked(name_, wallet, block.timestamp));
        require(merchants[merchantId].wallet == address(0), "PayGateway: merchant exists");

        merchants[merchantId] = Merchant({
            wallet: wallet,
            name: name_,
            isActive: true,
            totalReceived: 0,
            totalRefunded: 0,
            registeredAt: block.timestamp
        });
        merchantIds.push(merchantId);

        emit MerchantRegistered(merchantId, wallet, name_);
    }

    /// @notice Update merchant active status
    function setMerchantActive(bytes32 merchantId, bool isActive) external onlyOwner {
        require(merchants[merchantId].wallet != address(0), "PayGateway: merchant not found");
        merchants[merchantId].isActive = isActive;
        emit MerchantUpdated(merchantId, isActive);
    }

    // ---- Payment Lifecycle ----

    /// @notice Create a payment (ERC20)
    function createPayment(
        bytes32 merchantId,
        address token,
        uint256 amount,
        string calldata reference
    ) external nonReentrant whenNotPaused returns (uint256 paymentId) {
        Merchant storage m = merchants[merchantId];
        require(m.isActive, "PayGateway: merchant inactive");
        require(supportedTokens[token], "PayGateway: token not supported");
        require(amount > 0, "PayGateway: zero amount");

        // For ERC20, escrow the tokens
        if (token != address(0)) {
            IERC20(token).transferFrom(msg.sender, address(this), amount);
        }

        paymentId = nextPaymentId++;
        payments[paymentId] = Payment({
            id: paymentId,
            merchantId: merchantId,
            payer: msg.sender,
            token: token,
            amount: amount,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + defaultExpiry,
            status: PaymentStatus.Pending,
            reference: reference
        });

        emit PaymentCreated(paymentId, merchantId, msg.sender, amount);
    }

    /// @notice Create a payment with native currency
    function createNativePayment(
        bytes32 merchantId,
        string calldata reference
    ) external payable nonReentrant whenNotPaused returns (uint256 paymentId) {
        Merchant storage m = merchants[merchantId];
        require(m.isActive, "PayGateway: merchant inactive");
        require(msg.value > 0, "PayGateway: zero amount");

        paymentId = nextPaymentId++;
        payments[paymentId] = Payment({
            id: paymentId,
            merchantId: merchantId,
            payer: msg.sender,
            token: address(0),
            amount: msg.value,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + defaultExpiry,
            status: PaymentStatus.Pending,
            reference: reference
        });

        emit PaymentCreated(paymentId, merchantId, msg.sender, msg.value);
    }

    /// @notice Confirm a payment (releases funds to merchant minus fee)
    function confirmPayment(uint256 paymentId) external nonReentrant {
        Payment storage p = payments[paymentId];
        Merchant storage m = merchants[p.merchantId];
        require(p.status == PaymentStatus.Pending, "PayGateway: not pending");
        // Only merchant or owner can confirm
        require(msg.sender == m.wallet || msg.sender == owner(), "PayGateway: not authorized");

        p.status = PaymentStatus.Confirmed;

        uint256 fee = (p.amount * platformFeeBps) / 10000;
        uint256 merchantAmount = p.amount - fee;

        if (p.token == address(0)) {
            // Native
            if (fee > 0) {
                (bool s1, ) = feeCollector.call{value: fee}("");
                require(s1, "PayGateway: fee transfer failed");
            }
            (bool s2, ) = m.wallet.call{value: merchantAmount}("");
            require(s2, "PayGateway: merchant transfer failed");
        } else {
            if (fee > 0) {
                IERC20(p.token).transfer(feeCollector, fee);
            }
            IERC20(p.token).transfer(m.wallet, merchantAmount);
        }

        m.totalReceived += merchantAmount;
        emit PaymentConfirmed(paymentId, merchantAmount, fee);
    }

    /// @notice Refund a payment
    function refundPayment(uint256 paymentId) external nonReentrant {
        Payment storage p = payments[paymentId];
        Merchant storage m = merchants[p.merchantId];
        require(p.status == PaymentStatus.Pending || p.status == PaymentStatus.Confirmed, "PayGateway: cannot refund");
        require(msg.sender == m.wallet || msg.sender == owner(), "PayGateway: not authorized");

        p.status = PaymentStatus.Refunded;

        if (p.token == address(0)) {
            (bool sent, ) = p.payer.call{value: p.amount}("");
            require(sent, "PayGateway: refund failed");
        } else {
            IERC20(p.token).transfer(p.payer, p.amount);
        }

        m.totalRefunded += p.amount;
        emit PaymentRefunded(paymentId, p.amount);
    }

    /// @notice Mark expired payments (anyone can call)
    function expirePayment(uint256 paymentId) external nonReentrant {
        Payment storage p = payments[paymentId];
        require(p.status == PaymentStatus.Pending, "PayGateway: not pending");
        require(block.timestamp > p.expiresAt, "PayGateway: not expired");

        p.status = PaymentStatus.Expired;

        // Return escrowed funds to payer
        if (p.token == address(0)) {
            (bool sent, ) = p.payer.call{value: p.amount}("");
            require(sent, "PayGateway: refund failed");
        } else {
            IERC20(p.token).transfer(p.payer, p.amount);
        }

        emit PaymentExpired(paymentId);
    }

    /// @notice Dispute a payment (payer only)
    function disputePayment(uint256 paymentId) external {
        Payment storage p = payments[paymentId];
        require(msg.sender == p.payer, "PayGateway: not payer");
        require(p.status == PaymentStatus.Pending, "PayGateway: not pending");
        p.status = PaymentStatus.Disputed;
        emit PaymentDisputed(paymentId);
    }

    // ---- View ----

    function merchantCount() external view returns (uint256) {
        return merchantIds.length;
    }

    receive() external payable {}
}
