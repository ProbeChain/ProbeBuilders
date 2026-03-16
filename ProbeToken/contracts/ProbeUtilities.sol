// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ProbeUtilities
 * @author ProbeChain Team
 * @notice PROBE token utility functions: batch transfers, multicall, balance queries
 * @dev Provides gas-efficient batch operations for the native PROBE token on Rydberg Testnet
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

/// @notice Minimal ERC20 interface for token interactions
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract ProbeUtilities is Ownable, ReentrancyGuard, Pausable {
    /// @notice Multicall result
    struct CallResult {
        bool success;
        bytes returnData;
    }

    /// @notice Transfer record for auditing
    struct TransferRecord {
        address from;
        uint256 totalAmount;
        uint256 recipientCount;
        uint256 timestamp;
    }

    mapping(address => TransferRecord[]) private _transferHistory;
    uint256 public maxBatchSize = 100;
    uint256 public totalBatchTransfers;

    /// @notice Emitted on batch transfer
    event BatchTransferExecuted(address indexed sender, uint256 recipientCount, uint256 totalAmount);
    /// @notice Emitted on batch ETH transfer
    event BatchETHTransfer(address indexed sender, uint256 recipientCount, uint256 totalAmount);
    /// @notice Emitted on multicall
    event MulticallExecuted(address indexed sender, uint256 callCount, uint256 successCount);
    /// @notice Emitted on approve and transfer
    event ApproveAndTransferExecuted(address indexed token, address indexed from, address indexed to, uint256 amount);

    error ArrayLengthMismatch();
    error BatchTooLarge(uint256 size, uint256 max);
    error EmptyBatch();
    error InsufficientValue(uint256 sent, uint256 required);
    error TransferFailed(uint256 index);
    error ZeroAddress();

    /**
     * @notice Batch transfer ERC20 tokens to multiple recipients
     * @param token The ERC20 token contract address
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts per recipient
     */
    function batchTransfer(
        address token,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external nonReentrant whenNotPaused {
        if (recipients.length == 0) revert EmptyBatch();
        if (recipients.length != amounts.length) revert ArrayLengthMismatch();
        if (recipients.length > maxBatchSize) revert BatchTooLarge(recipients.length, maxBatchSize);

        uint256 totalAmount;
        IERC20 erc20 = IERC20(token);

        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert ZeroAddress();
            bool success = erc20.transferFrom(msg.sender, recipients[i], amounts[i]);
            if (!success) revert TransferFailed(i);
            totalAmount += amounts[i];
        }

        _transferHistory[msg.sender].push(TransferRecord({
            from: msg.sender,
            totalAmount: totalAmount,
            recipientCount: recipients.length,
            timestamp: block.timestamp
        }));

        totalBatchTransfers++;
        emit BatchTransferExecuted(msg.sender, recipients.length, totalAmount);
    }

    /**
     * @notice Batch transfer native ETH/PROBE to multiple recipients
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts per recipient
     */
    function batchTransferETH(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external payable nonReentrant whenNotPaused {
        if (recipients.length == 0) revert EmptyBatch();
        if (recipients.length != amounts.length) revert ArrayLengthMismatch();
        if (recipients.length > maxBatchSize) revert BatchTooLarge(recipients.length, maxBatchSize);

        uint256 totalAmount;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        if (msg.value < totalAmount) revert InsufficientValue(msg.value, totalAmount);

        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert ZeroAddress();
            (bool success, ) = recipients[i].call{value: amounts[i]}("");
            if (!success) revert TransferFailed(i);
        }

        // Refund excess
        if (msg.value > totalAmount) {
            (bool refunded, ) = msg.sender.call{value: msg.value - totalAmount}("");
            require(refunded, "Refund failed");
        }

        totalBatchTransfers++;
        emit BatchETHTransfer(msg.sender, recipients.length, totalAmount);
    }

    /**
     * @notice Approve and transfer in one call (helper)
     * @param token The ERC20 token
     * @param from The source address (must have approved this contract)
     * @param to The destination address
     * @param amount The transfer amount
     */
    function approveAndTransfer(
        address token,
        address from,
        address to,
        uint256 amount
    ) external whenNotPaused {
        require(msg.sender == from || msg.sender == owner(), "Unauthorized");
        IERC20(token).transferFrom(from, to, amount);
        emit ApproveAndTransferExecuted(token, from, to, amount);
    }

    /**
     * @notice Get balances for multiple addresses (ERC20)
     * @param token The ERC20 token contract
     * @param addresses Array of addresses to query
     * @return balances Array of balances
     */
    function getBalances(
        address token,
        address[] calldata addresses
    ) external view returns (uint256[] memory balances) {
        balances = new uint256[](addresses.length);
        IERC20 erc20 = IERC20(token);
        for (uint256 i = 0; i < addresses.length; i++) {
            balances[i] = erc20.balanceOf(addresses[i]);
        }
    }

    /**
     * @notice Get native ETH/PROBE balances for multiple addresses
     * @param addresses Array of addresses to query
     * @return balances Array of balances
     */
    function getETHBalances(
        address[] calldata addresses
    ) external view returns (uint256[] memory balances) {
        balances = new uint256[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            balances[i] = addresses[i].balance;
        }
    }

    /**
     * @notice Execute multiple calls in a single transaction
     * @param targets Array of target addresses
     * @param calldatas Array of encoded calls
     * @return results Array of call results
     */
    function multicall(
        address[] calldata targets,
        bytes[] calldata calldatas
    ) external nonReentrant whenNotPaused returns (CallResult[] memory results) {
        if (targets.length != calldatas.length) revert ArrayLengthMismatch();
        if (targets.length == 0) revert EmptyBatch();

        results = new CallResult[](targets.length);
        uint256 successCount;

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory data) = targets[i].call(calldatas[i]);
            results[i] = CallResult({success: success, returnData: data});
            if (success) successCount++;
        }

        emit MulticallExecuted(msg.sender, targets.length, successCount);
    }

    /**
     * @notice Get transfer history for an address
     * @param user The user address
     * @return records Array of transfer records
     */
    function getTransferHistory(address user) external view returns (TransferRecord[] memory records) {
        return _transferHistory[user];
    }

    /// @notice Set max batch size
    function setMaxBatchSize(uint256 newMax) external onlyOwner {
        require(newMax > 0 && newMax <= 500, "Invalid size");
        maxBatchSize = newMax;
    }

    receive() external payable {}
}
