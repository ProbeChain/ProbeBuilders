// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title OTCDesk
 * @author ProbeBuilders
 * @notice Over-the-counter trading desk for ProbeChain Rydberg Testnet.
 *         Escrow-based, supports partial fills, privacy-preserving (events only, no public orderbook).
 * @dev Inline Ownable, ReentrancyGuard, Pausable. EVM London compatible.
 */

/* ───────── Minimal Interface ───────── */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/* ───────── Abstract helpers (inlined) ───────── */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed prev, address indexed next_);
    error OwnableUnauthorized();
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorized(); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardLocked();
    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardLocked();
        _status = 2;
        _;
        _status = 1;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();
    modifier whenNotPaused() { if (_paused) revert ContractPaused(); _; }
    modifier whenPaused() { if (!_paused) revert ContractNotPaused(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

/* ───────── Main Contract ───────── */

contract OTCDesk is Ownable, ReentrancyGuard, Pausable {

    /* ── Structs ── */

    /// @notice An OTC sell order
    struct Order {
        address seller;
        address token;        // token being sold
        uint256 totalAmount;  // total tokens offered
        uint256 filledAmount; // tokens already sold
        uint256 price;        // price per token in native currency (wei)
        uint256 minFill;      // minimum fill amount per trade
        bool    active;
        uint256 createdAt;
    }

    /// @notice A fill record
    struct Fill {
        uint256 orderId;
        address buyer;
        uint256 tokenAmount;
        uint256 nativeAmount;
        uint256 timestamp;
    }

    /* ── State ── */

    uint256 public nextOrderId;
    mapping(uint256 => Order) private _orders;
    mapping(uint256 => Fill[]) private _fills;
    mapping(address => uint256[]) private _sellerOrders;
    mapping(address => uint256[]) private _buyerFills;

    /// @notice Protocol fee in basis points (default 30 = 0.3%)
    uint256 public feeBps = 30;
    /// @notice Accumulated fees available for withdrawal
    uint256 public accumulatedFees;

    /* ── Events ── */

    /// @notice Emitted when a new order is created (privacy: only event, no public getter)
    event OrderCreated(uint256 indexed orderId, address indexed seller, address token, uint256 amount, uint256 price, uint256 minFill);
    /// @notice Emitted when an order is partially or fully filled
    event OrderFilled(uint256 indexed orderId, address indexed buyer, uint256 tokenAmount, uint256 nativeAmount);
    /// @notice Emitted when an order is cancelled
    event OrderCancelled(uint256 indexed orderId, uint256 remainingAmount);
    /// @notice Emitted when fees are collected
    event FeesCollected(address indexed to, uint256 amount);

    /* ── Errors ── */

    error OrderNotActive();
    error NotOrderSeller();
    error BelowMinFill();
    error ExceedsAvailable();
    error InsufficientPayment();
    error TransferFailed();

    /* ── Constructor ── */

    constructor() Ownable() {}

    /* ── Admin ── */

    /// @notice Set the fee in basis points (max 500 = 5%)
    function setFee(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 500, "fee too high");
        feeBps = newFeeBps;
    }

    /// @notice Withdraw accumulated protocol fees
    function collectFees(address to) external onlyOwner nonReentrant {
        uint256 amount = accumulatedFees;
        accumulatedFees = 0;
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit FeesCollected(to, amount);
    }

    /* ── Core functions ── */

    /**
     * @notice Create a sell order. Tokens are escrowed in the contract.
     * @param token ERC-20 token to sell
     * @param amount Amount of tokens to sell
     * @param price Price per token in native currency (wei)
     * @param minFill Minimum fill amount (0 for no minimum)
     * @return orderId The created order ID
     */
    function createOrder(
        address token,
        uint256 amount,
        uint256 price,
        uint256 minFill
    ) external nonReentrant whenNotPaused returns (uint256 orderId) {
        require(token != address(0), "zero token");
        require(amount > 0, "zero amount");
        require(price > 0, "zero price");
        require(minFill <= amount, "minFill > amount");

        // Escrow tokens
        bool ok = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!ok) revert TransferFailed();

        orderId = nextOrderId++;
        _orders[orderId] = Order({
            seller: msg.sender,
            token: token,
            totalAmount: amount,
            filledAmount: 0,
            price: price,
            minFill: minFill,
            active: true,
            createdAt: block.timestamp
        });

        _sellerOrders[msg.sender].push(orderId);

        emit OrderCreated(orderId, msg.sender, token, amount, price, minFill);
    }

    /**
     * @notice Fill an order (partial or full). Send native currency to buy tokens.
     * @param orderId The order to fill
     * @param amount Token amount to purchase
     */
    function fillOrder(uint256 orderId, uint256 amount) external payable nonReentrant whenNotPaused {
        Order storage order = _orders[orderId];
        if (!order.active) revert OrderNotActive();

        uint256 available = order.totalAmount - order.filledAmount;
        if (amount > available) revert ExceedsAvailable();
        if (amount < order.minFill && amount != available) revert BelowMinFill();

        uint256 cost = amount * order.price / 1e18;
        if (msg.value < cost) revert InsufficientPayment();

        // Calculate fee
        uint256 fee = cost * feeBps / 10000;
        uint256 sellerProceeds = cost - fee;
        accumulatedFees += fee;

        order.filledAmount += amount;
        if (order.filledAmount == order.totalAmount) {
            order.active = false;
        }

        // Transfer tokens to buyer
        bool ok = IERC20(order.token).transfer(msg.sender, amount);
        if (!ok) revert TransferFailed();

        // Send payment to seller
        (bool sent, ) = order.seller.call{value: sellerProceeds}("");
        if (!sent) revert TransferFailed();

        // Refund excess payment
        if (msg.value > cost) {
            (bool refunded, ) = msg.sender.call{value: msg.value - cost}("");
            if (!refunded) revert TransferFailed();
        }

        _fills[orderId].push(Fill({
            orderId: orderId,
            buyer: msg.sender,
            tokenAmount: amount,
            nativeAmount: cost,
            timestamp: block.timestamp
        }));

        _buyerFills[msg.sender].push(orderId);

        emit OrderFilled(orderId, msg.sender, amount, cost);
    }

    /**
     * @notice Cancel an active order and return remaining escrowed tokens
     * @param orderId The order to cancel
     */
    function cancelOrder(uint256 orderId) external nonReentrant whenNotPaused {
        Order storage order = _orders[orderId];
        if (order.seller != msg.sender && msg.sender != owner()) revert NotOrderSeller();
        if (!order.active) revert OrderNotActive();

        order.active = false;
        uint256 remaining = order.totalAmount - order.filledAmount;

        if (remaining > 0) {
            bool ok = IERC20(order.token).transfer(order.seller, remaining);
            if (!ok) revert TransferFailed();
        }

        emit OrderCancelled(orderId, remaining);
    }

    /* ── View helpers ── */

    /// @notice Get order details (only for participants, not public orderbook)
    function getOrder(uint256 orderId) external view returns (Order memory) {
        return _orders[orderId];
    }

    /// @notice Get fill history for an order
    function getOrderFills(uint256 orderId) external view returns (Fill[] memory) {
        return _fills[orderId];
    }

    /// @notice Get all order IDs created by a seller
    function getSellerOrders(address seller) external view returns (uint256[] memory) {
        return _sellerOrders[seller];
    }

    /// @notice Get remaining fill amount for an order
    function getAvailable(uint256 orderId) external view returns (uint256) {
        Order storage o = _orders[orderId];
        return o.active ? o.totalAmount - o.filledAmount : 0;
    }

    /// @notice Allow contract to receive native currency
    receive() external payable {}
}
