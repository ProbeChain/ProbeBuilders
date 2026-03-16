// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title PaperTrading
 * @author ProbeBuilders
 * @notice Paper trading platform with virtual balances and leaderboard
 * @dev No real funds at risk — all balances are virtual for learning/competition
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

/// @title PaperTrading — Virtual trading platform with leaderboard
contract PaperTrading is Ownable, Pausable {

    enum Side { Buy, Sell }
    enum TradeStatus { Open, Settled, Cancelled }

    /// @notice Trading account
    struct Account {
        address trader;
        uint256 virtualBalance;       // Virtual USD balance (18 decimals)
        uint256 initialBalance;
        int256 totalPnL;              // Profit/Loss tracking
        uint32 tradeCount;
        uint32 winCount;
        uint64 createdAt;
        bool active;
    }

    /// @notice Trade record
    struct Trade {
        uint256 accountId;
        bytes32 asset;                // Asset symbol hash (e.g., keccak256("BTC"))
        Side side;
        uint256 amount;               // Quantity (18 decimals)
        uint256 entryPrice;           // Price at entry (18 decimals)
        uint256 settlementPrice;      // Price at settlement
        int256 pnl;
        TradeStatus status;
        uint64 openedAt;
        uint64 settledAt;
    }

    /// @notice Position tracking
    struct Position {
        uint256 amount;
        uint256 avgEntryPrice;
    }

    uint256 public nextAccountId = 1;
    uint256 public nextTradeId = 1;
    uint256 public constant MAX_INITIAL_BALANCE = 1_000_000 ether; // 1M virtual USD
    uint256 public constant MIN_INITIAL_BALANCE = 100 ether;       // 100 virtual USD

    mapping(uint256 => Account) public accounts;
    mapping(address => uint256) public traderAccount;
    mapping(uint256 => Trade) public trades;
    /// @notice accountId => asset => Position
    mapping(uint256 => mapping(bytes32 => Position)) public positions;
    /// @notice Allowed trading assets
    mapping(bytes32 => bool) public allowedAssets;
    /// @notice Asset names for display
    mapping(bytes32 => string) public assetNames;
    /// @notice Authorized price settlers
    mapping(address => bool) public settlers;

    event AccountCreated(uint256 indexed accountId, address indexed trader, uint256 initialBalance);
    event TradePlaced(uint256 indexed tradeId, uint256 indexed accountId, bytes32 asset, Side side, uint256 amount, uint256 price);
    event TradeSettled(uint256 indexed tradeId, uint256 settlementPrice, int256 pnl);
    event TradeCancelled(uint256 indexed tradeId);
    event AssetAdded(bytes32 indexed assetHash, string name);
    event LeaderboardUpdate(uint256 indexed accountId, address indexed trader, int256 totalPnL);

    error AccountAlreadyExists();
    error AccountNotFound();
    error AccountNotActive();
    error InvalidBalance();
    error AssetNotAllowed();
    error InsufficientVirtualBalance();
    error TradeNotOpen();
    error NotAccountOwner();
    error NotSettler();

    constructor() Ownable(msg.sender) {
        settlers[msg.sender] = true;

        // Add default assets
        bytes32 btc = keccak256("BTC");
        bytes32 eth = keccak256("ETH");
        bytes32 prb = keccak256("PRB");
        allowedAssets[btc] = true; assetNames[btc] = "BTC";
        allowedAssets[eth] = true; assetNames[eth] = "ETH";
        allowedAssets[prb] = true; assetNames[prb] = "PRB";
    }

    /// @notice Create a paper trading account
    /// @param initialBalance Starting virtual balance (18 decimals)
    /// @return accountId Created account ID
    function createAccount(uint256 initialBalance)
        external
        whenNotPaused
        returns (uint256 accountId)
    {
        if (traderAccount[msg.sender] != 0) revert AccountAlreadyExists();
        if (initialBalance < MIN_INITIAL_BALANCE || initialBalance > MAX_INITIAL_BALANCE) {
            revert InvalidBalance();
        }

        accountId = nextAccountId++;
        accounts[accountId] = Account({
            trader: msg.sender,
            virtualBalance: initialBalance,
            initialBalance: initialBalance,
            totalPnL: 0,
            tradeCount: 0,
            winCount: 0,
            createdAt: uint64(block.timestamp),
            active: true
        });

        traderAccount[msg.sender] = accountId;
        emit AccountCreated(accountId, msg.sender, initialBalance);
    }

    /// @notice Place a virtual trade
    /// @param accountId Account ID
    /// @param asset Asset symbol (e.g., "BTC")
    /// @param side Buy or Sell
    /// @param amount Trade quantity (18 decimals)
    /// @param price Entry price (18 decimals)
    /// @return tradeId Created trade ID
    function placeTrade(
        uint256 accountId,
        string calldata asset,
        Side side,
        uint256 amount,
        uint256 price
    ) external whenNotPaused returns (uint256 tradeId) {
        Account storage a = accounts[accountId];
        if (a.trader != msg.sender) revert NotAccountOwner();
        if (!a.active) revert AccountNotActive();

        bytes32 assetHash = keccak256(abi.encodePacked(asset));
        if (!allowedAssets[assetHash]) revert AssetNotAllowed();

        require(amount > 0 && price > 0, "Invalid amount/price");

        // Check virtual margin: need at least 10% of notional
        uint256 notional = (amount * price) / 1 ether;
        uint256 requiredMargin = notional / 10;
        if (a.virtualBalance < requiredMargin) revert InsufficientVirtualBalance();

        // Reserve margin
        a.virtualBalance -= requiredMargin;
        a.tradeCount++;

        tradeId = nextTradeId++;
        trades[tradeId] = Trade({
            accountId: accountId,
            asset: assetHash,
            side: side,
            amount: amount,
            entryPrice: price,
            settlementPrice: 0,
            pnl: 0,
            status: TradeStatus.Open,
            openedAt: uint64(block.timestamp),
            settledAt: 0
        });

        // Update position
        Position storage pos = positions[accountId][assetHash];
        if (side == Side.Buy) {
            uint256 totalCost = pos.amount * pos.avgEntryPrice + amount * price;
            pos.amount += amount;
            pos.avgEntryPrice = pos.amount > 0 ? totalCost / pos.amount : 0;
        }

        emit TradePlaced(tradeId, accountId, assetHash, side, amount, price);
    }

    /// @notice Settle a trade at a given price
    /// @param tradeId Trade to settle
    /// @param settlementPrice Settlement price (18 decimals)
    function settleTrade(uint256 tradeId, uint256 settlementPrice)
        external
        whenNotPaused
    {
        if (!settlers[msg.sender]) revert NotSettler();

        Trade storage t = trades[tradeId];
        if (t.status != TradeStatus.Open) revert TradeNotOpen();
        require(settlementPrice > 0, "Invalid price");

        t.settlementPrice = settlementPrice;
        t.settledAt = uint64(block.timestamp);
        t.status = TradeStatus.Settled;

        // Calculate PnL
        int256 pnl;
        if (t.side == Side.Buy) {
            pnl = int256((t.amount * settlementPrice) / 1 ether) - int256((t.amount * t.entryPrice) / 1 ether);
        } else {
            pnl = int256((t.amount * t.entryPrice) / 1 ether) - int256((t.amount * settlementPrice) / 1 ether);
        }
        t.pnl = pnl;

        // Update account
        Account storage a = accounts[t.accountId];
        a.totalPnL += pnl;

        // Return margin + PnL
        uint256 notional = (t.amount * t.entryPrice) / 1 ether;
        uint256 margin = notional / 10;
        if (pnl >= 0) {
            a.virtualBalance += margin + uint256(pnl);
            a.winCount++;
        } else {
            uint256 loss = uint256(-pnl);
            if (loss >= margin) {
                // Total loss
            } else {
                a.virtualBalance += margin - loss;
            }
        }

        emit TradeSettled(tradeId, settlementPrice, pnl);
        emit LeaderboardUpdate(t.accountId, a.trader, a.totalPnL);
    }

    /// @notice Cancel an open trade (return margin)
    function cancelTrade(uint256 tradeId) external whenNotPaused {
        Trade storage t = trades[tradeId];
        Account storage a = accounts[t.accountId];
        if (a.trader != msg.sender) revert NotAccountOwner();
        if (t.status != TradeStatus.Open) revert TradeNotOpen();

        t.status = TradeStatus.Cancelled;
        uint256 notional = (t.amount * t.entryPrice) / 1 ether;
        uint256 margin = notional / 10;
        a.virtualBalance += margin;

        emit TradeCancelled(tradeId);
    }

    /// @notice Get portfolio summary
    /// @param accountId Account to query
    /// @return balance Virtual balance
    /// @return pnl Total PnL
    /// @return totalTrades Total trades
    /// @return wins Total winning trades
    function getPortfolio(uint256 accountId)
        external
        view
        returns (uint256 balance, int256 pnl, uint32 totalTrades, uint32 wins)
    {
        Account storage a = accounts[accountId];
        return (a.virtualBalance, a.totalPnL, a.tradeCount, a.winCount);
    }

    /// @notice Get position for an asset
    function getPosition(uint256 accountId, string calldata asset)
        external
        view
        returns (uint256 amount, uint256 avgPrice)
    {
        bytes32 assetHash = keccak256(abi.encodePacked(asset));
        Position storage p = positions[accountId][assetHash];
        return (p.amount, p.avgEntryPrice);
    }

    /// @notice Add allowed asset
    function addAsset(string calldata name_) external onlyOwner {
        bytes32 assetHash = keccak256(abi.encodePacked(name_));
        allowedAssets[assetHash] = true;
        assetNames[assetHash] = name_;
        emit AssetAdded(assetHash, name_);
    }

    /// @notice Set settler authorization
    function setSettler(address settler, bool authorized) external onlyOwner {
        settlers[settler] = authorized;
    }

    /// @notice Reset account (start over)
    function resetAccount(uint256 accountId, uint256 newBalance) external {
        Account storage a = accounts[accountId];
        if (a.trader != msg.sender) revert NotAccountOwner();
        if (newBalance < MIN_INITIAL_BALANCE || newBalance > MAX_INITIAL_BALANCE) revert InvalidBalance();

        a.virtualBalance = newBalance;
        a.initialBalance = newBalance;
        a.totalPnL = 0;
        a.tradeCount = 0;
        a.winCount = 0;
    }
}
