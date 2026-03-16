// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title FanTokenFactory
 * @author ProbeBuilders
 * @notice Creator fan token platform with bonding curve pricing
 * @dev Price = supply^2 / CURVE_CONSTANT. Supports token creation, buying, selling, and reward distribution.
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

abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardReentrantCall();
        _status = 2;
        _;
        _status = 1;
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

/// @title FanTokenFactory — Creator fan token platform with bonding curve
contract FanTokenFactory is Ownable, ReentrancyGuard, Pausable {

    /// @notice Fan token metadata
    struct FanToken {
        address creator;
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 currentSupply;
        uint256 reserveBalance;    // ETH held in bonding curve
        uint256 rewardPool;        // Accumulated rewards for holders
        uint64 createdAt;
        bool active;
    }

    /// @notice Bonding curve constant — Price = supply^2 / CURVE_CONSTANT
    uint256 public constant CURVE_CONSTANT = 1_000_000;
    /// @notice Platform fee in basis points
    uint256 public platformFeeBPS = 250; // 2.5%
    /// @notice Creator fee in basis points
    uint256 public creatorFeeBPS = 250;  // 2.5%
    uint256 public platformFees;
    uint256 public nextTokenId = 1;

    mapping(uint256 => FanToken) public fanTokens;
    /// @notice tokenId => holder => balance
    mapping(uint256 => mapping(address => uint256)) public balanceOf;
    /// @notice tokenId => holder => claimed rewards
    mapping(uint256 => mapping(address => uint256)) public claimedRewards;
    /// @notice Creator address => their token IDs
    mapping(address => uint256[]) public creatorTokens;

    event FanTokenCreated(uint256 indexed tokenId, address indexed creator, string name, string symbol, uint256 maxSupply);
    event TokensPurchased(uint256 indexed tokenId, address indexed buyer, uint256 amount, uint256 cost);
    event TokensSold(uint256 indexed tokenId, address indexed seller, uint256 amount, uint256 proceeds);
    event RewardsDistributed(uint256 indexed tokenId, uint256 amount);
    event RewardsClaimed(uint256 indexed tokenId, address indexed holder, uint256 amount);
    event PlatformFeesWithdrawn(uint256 amount);

    error TokenNotFound();
    error TokenNotActive();
    error ExceedsMaxSupply();
    error InsufficientPayment();
    error InsufficientBalance();
    error TransferFailed();
    error NotCreator();
    error ZeroAmount();

    constructor() Ownable(msg.sender) {}

    /// @notice Create a new fan token for a creator
    /// @param creator The creator address
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param maxSupply_ Maximum supply of fan tokens
    /// @return tokenId The created fan token ID
    function createFanToken(
        address creator,
        string calldata name_,
        string calldata symbol_,
        uint256 maxSupply_
    ) external whenNotPaused returns (uint256 tokenId) {
        require(creator != address(0), "Invalid creator");
        require(bytes(name_).length > 0 && bytes(name_).length <= 32, "Invalid name");
        require(maxSupply_ > 0 && maxSupply_ <= 1_000_000_000 ether, "Invalid max supply");

        tokenId = nextTokenId++;
        fanTokens[tokenId] = FanToken({
            creator: creator,
            name: name_,
            symbol: symbol_,
            maxSupply: maxSupply_,
            currentSupply: 0,
            reserveBalance: 0,
            rewardPool: 0,
            createdAt: uint64(block.timestamp),
            active: true
        });

        creatorTokens[creator].push(tokenId);
        emit FanTokenCreated(tokenId, creator, name_, symbol_, maxSupply_);
    }

    /// @notice Calculate buy price for a given amount of tokens
    /// @param tokenId Fan token ID
    /// @param amount Number of tokens to buy (in wei)
    /// @return cost Total cost in wei
    function getBuyPrice(uint256 tokenId, uint256 amount) public view returns (uint256 cost) {
        FanToken storage ft = fanTokens[tokenId];
        uint256 supply = ft.currentSupply;
        // Integral of supply^2 / CURVE_CONSTANT from supply to supply+amount
        // = [(supply+amount)^3 - supply^3] / (3 * CURVE_CONSTANT)
        uint256 newSupply = supply + amount;
        cost = (newSupply * newSupply * newSupply - supply * supply * supply) / (3 * CURVE_CONSTANT);
        if (cost == 0) cost = 1; // minimum cost
    }

    /// @notice Calculate sell price for a given amount of tokens
    /// @param tokenId Fan token ID
    /// @param amount Number of tokens to sell (in wei)
    /// @return proceeds Total proceeds in wei
    function getSellPrice(uint256 tokenId, uint256 amount) public view returns (uint256 proceeds) {
        FanToken storage ft = fanTokens[tokenId];
        uint256 supply = ft.currentSupply;
        require(amount <= supply, "Amount exceeds supply");
        uint256 newSupply = supply - amount;
        proceeds = (supply * supply * supply - newSupply * newSupply * newSupply) / (3 * CURVE_CONSTANT);
        // Cap by reserve
        if (proceeds > ft.reserveBalance) proceeds = ft.reserveBalance;
    }

    /// @notice Buy fan tokens along the bonding curve
    /// @param tokenId Fan token ID
    /// @param amount Number of tokens to buy (in wei units)
    function buyTokens(uint256 tokenId, uint256 amount)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        FanToken storage ft = fanTokens[tokenId];
        if (!ft.active) revert TokenNotActive();
        if (ft.currentSupply + amount > ft.maxSupply) revert ExceedsMaxSupply();

        uint256 cost = getBuyPrice(tokenId, amount);
        uint256 platformFee = (cost * platformFeeBPS) / 10000;
        uint256 creatorFee = (cost * creatorFeeBPS) / 10000;
        uint256 totalCost = cost + platformFee + creatorFee;

        if (msg.value < totalCost) revert InsufficientPayment();

        ft.currentSupply += amount;
        ft.reserveBalance += cost;
        platformFees += platformFee;
        balanceOf[tokenId][msg.sender] += amount;

        // Send creator fee
        if (creatorFee > 0) {
            (bool ok, ) = payable(ft.creator).call{value: creatorFee}("");
            if (!ok) revert TransferFailed();
        }

        // Refund excess
        uint256 excess = msg.value - totalCost;
        if (excess > 0) {
            (bool ok2, ) = payable(msg.sender).call{value: excess}("");
            if (!ok2) revert TransferFailed();
        }

        emit TokensPurchased(tokenId, msg.sender, amount, totalCost);
    }

    /// @notice Sell fan tokens back to the bonding curve
    /// @param tokenId Fan token ID
    /// @param amount Number of tokens to sell
    function sellTokens(uint256 tokenId, uint256 amount)
        external
        whenNotPaused
        nonReentrant
    {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf[tokenId][msg.sender] < amount) revert InsufficientBalance();

        FanToken storage ft = fanTokens[tokenId];
        uint256 proceeds = getSellPrice(tokenId, amount);
        uint256 platformFee = (proceeds * platformFeeBPS) / 10000;
        uint256 netProceeds = proceeds - platformFee;

        ft.currentSupply -= amount;
        ft.reserveBalance -= proceeds;
        platformFees += platformFee;
        balanceOf[tokenId][msg.sender] -= amount;

        (bool ok, ) = payable(msg.sender).call{value: netProceeds}("");
        if (!ok) revert TransferFailed();

        emit TokensSold(tokenId, msg.sender, amount, netProceeds);
    }

    /// @notice Distribute rewards to all holders (creator deposits ETH)
    /// @param tokenId Fan token ID
    function distributeRewards(uint256 tokenId) external payable whenNotPaused {
        FanToken storage ft = fanTokens[tokenId];
        if (ft.creator != msg.sender) revert NotCreator();
        require(msg.value > 0, "Must send reward");

        ft.rewardPool += msg.value;
        emit RewardsDistributed(tokenId, msg.value);
    }

    /// @notice Claim proportional share of reward pool
    /// @param tokenId Fan token ID
    function claimRewards(uint256 tokenId) external nonReentrant {
        FanToken storage ft = fanTokens[tokenId];
        uint256 holderBalance = balanceOf[tokenId][msg.sender];
        require(holderBalance > 0, "No tokens held");
        require(ft.currentSupply > 0, "No supply");

        uint256 totalEntitled = (ft.rewardPool * holderBalance) / ft.currentSupply;
        uint256 claimed = claimedRewards[tokenId][msg.sender];
        uint256 claimable = totalEntitled > claimed ? totalEntitled - claimed : 0;
        require(claimable > 0, "Nothing to claim");

        claimedRewards[tokenId][msg.sender] = totalEntitled;

        (bool ok, ) = payable(msg.sender).call{value: claimable}("");
        if (!ok) revert TransferFailed();

        emit RewardsClaimed(tokenId, msg.sender, claimable);
    }

    /// @notice Withdraw accumulated platform fees
    function withdrawPlatformFees() external onlyOwner nonReentrant {
        uint256 amount = platformFees;
        require(amount > 0, "No fees");
        platformFees = 0;
        (bool ok, ) = payable(owner()).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit PlatformFeesWithdrawn(amount);
    }

    /// @notice Get current spot price per token
    function getCurrentPrice(uint256 tokenId) external view returns (uint256) {
        FanToken storage ft = fanTokens[tokenId];
        return (ft.currentSupply * ft.currentSupply) / CURVE_CONSTANT;
    }

    /// @notice Get all token IDs for a creator
    function getCreatorTokens(address creator) external view returns (uint256[] memory) {
        return creatorTokens[creator];
    }
}
