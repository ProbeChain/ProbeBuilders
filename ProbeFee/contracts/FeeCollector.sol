// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title FeeCollector
 * @author ProbeChain Team
 * @notice Protocol-wide fee collection and management system for ProbeChain
 * @dev Configurable fee types by basis points, collection, withdrawal, and statistics
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender); _; }
    function owner() public view virtual returns (address) { return _owner; }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner); _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardReentrantCall();
        _status = _ENTERED; _; _status = _NOT_ENTERED;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    error ExpectedPause();
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    modifier whenPaused() { if (!_paused) revert ExpectedPause(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract FeeCollector is Ownable, ReentrancyGuard, Pausable {
    /// @notice Fee type configuration
    struct FeeConfig {
        bytes32 feeType;
        uint256 basisPoints;   // 1 bp = 0.01%
        bool active;
        uint256 totalCollected;
        uint256 collectionCount;
    }

    /// @notice Fee statistics
    struct FeeStats {
        uint256 totalFeesCollected;
        uint256 totalFeesWithdrawn;
        uint256 totalTransactions;
        uint256 activeFeesCount;
    }

    /// @notice Token-specific fee balance
    struct TokenBalance {
        address token;
        uint256 balance;
    }

    mapping(bytes32 => FeeConfig) private _fees;
    mapping(address => uint256) private _tokenBalances; // token address => collected fees
    bytes32[] private _feeTypes;

    uint256 public maxBasisPoints = 5000; // 50% max fee
    FeeStats public stats;

    /// @notice Emitted when a fee type is configured
    event FeeSet(bytes32 indexed feeType, uint256 basisPoints);
    /// @notice Emitted when a fee is collected
    event FeeCollected(bytes32 indexed feeType, address indexed payer, address token, uint256 feeAmount, uint256 netAmount);
    /// @notice Emitted when fees are withdrawn
    event FeesWithdrawn(address indexed token, address indexed recipient, uint256 amount);
    /// @notice Emitted when a fee type is deactivated
    event FeeDeactivated(bytes32 indexed feeType);

    error FeeTypeNotFound(bytes32 feeType);
    error FeeTypeInactive(bytes32 feeType);
    error BasisPointsTooHigh(uint256 bps, uint256 max);
    error ZeroAmount();
    error NoFeesToWithdraw(address token);
    error EmptyFeeType();

    /**
     * @notice Set or update a fee type
     * @param feeType The fee type identifier (e.g., keccak256("SWAP_FEE"))
     * @param basisPoints The fee in basis points (100 = 1%)
     */
    function setFee(bytes32 feeType, uint256 basisPoints) external onlyOwner {
        if (feeType == bytes32(0)) revert EmptyFeeType();
        if (basisPoints > maxBasisPoints) revert BasisPointsTooHigh(basisPoints, maxBasisPoints);

        if (_fees[feeType].feeType == bytes32(0)) {
            _feeTypes.push(feeType);
            stats.activeFeesCount++;
        }

        _fees[feeType] = FeeConfig({
            feeType: feeType,
            basisPoints: basisPoints,
            active: true,
            totalCollected: _fees[feeType].totalCollected,
            collectionCount: _fees[feeType].collectionCount
        });

        emit FeeSet(feeType, basisPoints);
    }

    /**
     * @notice Collect a fee on a transaction amount (ERC20 token)
     * @param feeType The fee type to apply
     * @param token The ERC20 token address
     * @param amount The gross transaction amount
     * @return netAmount The amount after fee deduction
     */
    function collectFee(
        bytes32 feeType,
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused returns (uint256 netAmount) {
        FeeConfig storage fee = _fees[feeType];
        if (fee.feeType == bytes32(0)) revert FeeTypeNotFound(feeType);
        if (!fee.active) revert FeeTypeInactive(feeType);
        if (amount == 0) revert ZeroAmount();

        uint256 feeAmount = (amount * fee.basisPoints) / 10000;
        netAmount = amount - feeAmount;

        // Transfer fee to this contract
        if (feeAmount > 0) {
            bool success = IERC20(token).transferFrom(msg.sender, address(this), feeAmount);
            require(success, "Fee transfer failed");
            _tokenBalances[token] += feeAmount;
        }

        fee.totalCollected += feeAmount;
        fee.collectionCount++;
        stats.totalFeesCollected += feeAmount;
        stats.totalTransactions++;

        emit FeeCollected(feeType, msg.sender, token, feeAmount, netAmount);
    }

    /**
     * @notice Collect a fee on native ETH/PROBE
     * @param feeType The fee type to apply
     * @return netAmount The amount after fee deduction
     */
    function collectFeeETH(
        bytes32 feeType
    ) external payable nonReentrant whenNotPaused returns (uint256 netAmount) {
        FeeConfig storage fee = _fees[feeType];
        if (fee.feeType == bytes32(0)) revert FeeTypeNotFound(feeType);
        if (!fee.active) revert FeeTypeInactive(feeType);
        if (msg.value == 0) revert ZeroAmount();

        uint256 feeAmount = (msg.value * fee.basisPoints) / 10000;
        netAmount = msg.value - feeAmount;

        // Refund net amount to sender
        if (netAmount > 0) {
            (bool success, ) = msg.sender.call{value: netAmount}("");
            require(success, "Refund failed");
        }

        _tokenBalances[address(0)] += feeAmount;
        fee.totalCollected += feeAmount;
        fee.collectionCount++;
        stats.totalFeesCollected += feeAmount;
        stats.totalTransactions++;

        emit FeeCollected(feeType, msg.sender, address(0), feeAmount, netAmount);
    }

    /**
     * @notice Withdraw collected fees for a token
     * @param token The token to withdraw (address(0) for native ETH/PROBE)
     */
    function withdrawFees(address token) external nonReentrant onlyOwner {
        uint256 balance = _tokenBalances[token];
        if (balance == 0) revert NoFeesToWithdraw(token);

        _tokenBalances[token] = 0;
        stats.totalFeesWithdrawn += balance;

        if (token == address(0)) {
            (bool success, ) = owner().call{value: balance}("");
            require(success, "ETH withdraw failed");
        } else {
            bool success = IERC20(token).transfer(owner(), balance);
            require(success, "Token withdraw failed");
        }

        emit FeesWithdrawn(token, owner(), balance);
    }

    /**
     * @notice Get fee statistics
     * @return feeStats The global fee stats
     */
    function getFeeStats() external view returns (FeeStats memory feeStats) {
        return stats;
    }

    /**
     * @notice Get fee configuration for a type
     * @param feeType The fee type
     * @return config The fee configuration
     */
    function getFee(bytes32 feeType) external view returns (FeeConfig memory config) {
        if (_fees[feeType].feeType == bytes32(0)) revert FeeTypeNotFound(feeType);
        return _fees[feeType];
    }

    /**
     * @notice Get collected balance for a token
     * @param token The token address
     * @return balance The collected fee balance
     */
    function getCollectedBalance(address token) external view returns (uint256 balance) {
        return _tokenBalances[token];
    }

    /**
     * @notice Get all fee types
     * @return types Array of fee type identifiers
     */
    function getAllFeeTypes() external view returns (bytes32[] memory types) {
        return _feeTypes;
    }

    /**
     * @notice Deactivate a fee type
     * @param feeType The fee type to deactivate
     */
    function deactivateFee(bytes32 feeType) external onlyOwner {
        if (_fees[feeType].feeType == bytes32(0)) revert FeeTypeNotFound(feeType);
        _fees[feeType].active = false;
        stats.activeFeesCount--;
        emit FeeDeactivated(feeType);
    }

    /// @notice Update max basis points cap
    function setMaxBasisPoints(uint256 max) external onlyOwner {
        require(max <= 10000, "Cannot exceed 100%");
        maxBasisPoints = max;
    }

    receive() external payable {}
}
