// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title TipJar
 * @author ProbeBuilders
 * @notice Social tipping protocol with native and ERC-20 token support
 * @dev Tracks tip history per user with leaderboard events
 */

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

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

    modifier whenNotPaused() {
        if (_paused) revert EnforcedPause();
        _;
    }

    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
}

/// @title TipJar — Social tipping protocol
contract TipJar is Ownable, ReentrancyGuard, Pausable {

    /// @notice Tip record
    struct TipRecord {
        address tipper;
        address recipient;
        address token;       // address(0) for native
        uint256 amount;
        uint64 timestamp;
        string message;
    }

    uint256 public minTipNative = 0.001 ether;
    uint256 public platformFeeBPS = 100; // 1%
    uint256 public totalTipCount;

    /// @notice Accumulated native tips per user
    mapping(address => uint256) public pendingWithdrawals;
    /// @notice Accumulated token tips per user: recipient => token => amount
    mapping(address => mapping(address => uint256)) public pendingTokenWithdrawals;
    /// @notice Total tips received (native value) per user for leaderboard
    mapping(address => uint256) public totalTipsReceived;
    /// @notice Total tips sent per user
    mapping(address => uint256) public totalTipsSent;
    /// @notice Platform fees accumulated
    uint256 public platformFees;
    /// @notice Allowed ERC-20 tokens for tipping
    mapping(address => bool) public allowedTokens;

    event TipSent(
        address indexed tipper,
        address indexed recipient,
        address indexed token,
        uint256 amount,
        uint256 fee,
        string message,
        uint256 tipId
    );
    event TipsWithdrawn(address indexed user, uint256 amount);
    event TokenTipsWithdrawn(address indexed user, address indexed token, uint256 amount);
    event MinTipUpdated(uint256 newMinTip);
    event PlatformFeeUpdated(uint256 newFeeBPS);
    event TokenAllowed(address indexed token, bool allowed);
    event LeaderboardUpdate(address indexed user, uint256 newTotal);
    event PlatformFeesWithdrawn(address indexed owner, uint256 amount);

    error TipTooLow();
    error NoTipsToWithdraw();
    error TransferFailed();
    error TokenNotAllowed();
    error CannotTipSelf();
    error InvalidRecipient();

    constructor() Ownable(msg.sender) {}

    /// @notice Send a native currency tip
    /// @param recipient Address to tip
    /// @param message Optional tip message
    function tip(address recipient, string calldata message)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        if (recipient == address(0)) revert InvalidRecipient();
        if (recipient == msg.sender) revert CannotTipSelf();
        if (msg.value < minTipNative) revert TipTooLow();

        uint256 fee = (msg.value * platformFeeBPS) / 10000;
        uint256 netAmount = msg.value - fee;
        platformFees += fee;

        pendingWithdrawals[recipient] += netAmount;
        totalTipsReceived[recipient] += msg.value;
        totalTipsSent[msg.sender] += msg.value;
        totalTipCount++;

        emit TipSent(msg.sender, recipient, address(0), netAmount, fee, message, totalTipCount);
        emit LeaderboardUpdate(recipient, totalTipsReceived[recipient]);
    }

    /// @notice Send an ERC-20 token tip
    /// @param recipient Address to tip
    /// @param token ERC-20 token address
    /// @param amount Amount to tip
    function tipWithToken(
        address recipient,
        address token,
        uint256 amount,
        string calldata message
    ) external whenNotPaused nonReentrant {
        if (recipient == address(0)) revert InvalidRecipient();
        if (recipient == msg.sender) revert CannotTipSelf();
        if (!allowedTokens[token]) revert TokenNotAllowed();
        require(amount > 0, "Amount must be > 0");

        uint256 fee = (amount * platformFeeBPS) / 10000;
        uint256 netAmount = amount - fee;

        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        pendingTokenWithdrawals[recipient][token] += netAmount;
        pendingTokenWithdrawals[owner()][token] += fee;
        totalTipCount++;

        emit TipSent(msg.sender, recipient, token, netAmount, fee, message, totalTipCount);
    }

    /// @notice Withdraw accumulated native tips
    function withdrawTips() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NoTipsToWithdraw();

        pendingWithdrawals[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit TipsWithdrawn(msg.sender, amount);
    }

    /// @notice Withdraw accumulated token tips
    /// @param token Token address to withdraw
    function withdrawTokenTips(address token) external nonReentrant {
        uint256 amount = pendingTokenWithdrawals[msg.sender][token];
        if (amount == 0) revert NoTipsToWithdraw();

        pendingTokenWithdrawals[msg.sender][token] = 0;
        bool success = IERC20(token).transfer(msg.sender, amount);
        if (!success) revert TransferFailed();

        emit TokenTipsWithdrawn(msg.sender, token, amount);
    }

    /// @notice Withdraw platform fees (owner only)
    function withdrawPlatformFees() external onlyOwner nonReentrant {
        uint256 amount = platformFees;
        if (amount == 0) revert NoTipsToWithdraw();
        platformFees = 0;

        (bool success, ) = payable(owner()).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit PlatformFeesWithdrawn(owner(), amount);
    }

    /// @notice Set minimum native tip amount
    function setMinTip(uint256 newMinTip) external onlyOwner {
        minTipNative = newMinTip;
        emit MinTipUpdated(newMinTip);
    }

    /// @notice Set platform fee in basis points
    function setPlatformFee(uint256 newFeeBPS) external onlyOwner {
        require(newFeeBPS <= 1000, "Fee too high"); // max 10%
        platformFeeBPS = newFeeBPS;
        emit PlatformFeeUpdated(newFeeBPS);
    }

    /// @notice Allow or disallow an ERC-20 token for tipping
    function setAllowedToken(address token, bool allowed) external onlyOwner {
        allowedTokens[token] = allowed;
        emit TokenAllowed(token, allowed);
    }
}
