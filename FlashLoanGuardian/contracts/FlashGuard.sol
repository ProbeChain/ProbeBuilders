// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title FlashGuard
 * @author ProbeBuilders
 * @notice Flash loan protection with reentrancy guards and sandwich attack detection for ProbeChain.
 * @dev Monitors transactions, detects price deviations, and provides circuit-breaker protection.
 */

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IPriceOracle {
    function getPrice(address token) external view returns (uint256);
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

contract FlashGuard is Ownable, ReentrancyGuard {
    // ---- Constants ----
    uint256 public constant MAX_PRICE_DEVIATION_BPS = 500; // 5% max deviation
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant COOLDOWN_BLOCKS = 1;

    // ---- State ----

    /// @notice Protected contracts that FlashGuard monitors
    mapping(address => bool) public protectedContracts;

    /// @notice Price oracle reference
    IPriceOracle public priceOracle;

    /// @notice Per-token price tracking for deviation detection
    struct PriceSnapshot {
        uint256 price;
        uint256 blockNumber;
        uint256 timestamp;
    }

    mapping(address => PriceSnapshot) public lastPriceSnapshot;
    mapping(address => uint256) public priceDeviationThreshold; // per-token BPS threshold

    /// @notice Per-block transaction tracking (anti-sandwich)
    mapping(uint256 => mapping(address => uint256)) public blockTxCount; // block => token => tx count
    uint256 public maxTxPerBlockPerToken = 3;

    /// @notice Circuit breaker
    bool public circuitBreakerTripped;
    uint256 public circuitBreakerCooldown = 1 hours;
    uint256 public circuitBreakerTrippedAt;

    /// @notice Flash loan detection: track balance changes within a transaction
    mapping(address => mapping(address => uint256)) public preTransactionBalance; // contract => token => balance

    /// @notice Guarded transaction tracking
    struct GuardedTx {
        uint256 id;
        address sender;
        address target;
        address token;
        uint256 amount;
        uint256 blockNumber;
        uint256 timestamp;
        bool flagged;
        string flagReason;
    }

    GuardedTx[] public guardedTransactions;

    // ---- Events ----
    event ContractProtected(address indexed target, bool status);
    event PriceDeviationDetected(address indexed token, uint256 expectedPrice, uint256 actualPrice, uint256 deviationBps);
    event SandwichAttackDetected(address indexed token, uint256 blockNumber, uint256 txCount);
    event FlashLoanDetected(address indexed contract_, address indexed token, uint256 balanceBefore, uint256 balanceAfter);
    event CircuitBreakerTripped(address indexed triggeredBy, string reason);
    event CircuitBreakerReset(address indexed resetBy);
    event TransactionGuarded(uint256 indexed txId, address indexed sender, address indexed token, uint256 amount, bool flagged);
    event OracleUpdated(address indexed newOracle);
    event ThresholdUpdated(address indexed token, uint256 thresholdBps);

    constructor(address _oracle) {
        priceOracle = IPriceOracle(_oracle);
    }

    // ---- Admin ----

    function setProtectedContract(address target, bool status) external onlyOwner {
        protectedContracts[target] = status;
        emit ContractProtected(target, status);
    }

    function setOracle(address _oracle) external onlyOwner {
        priceOracle = IPriceOracle(_oracle);
        emit OracleUpdated(_oracle);
    }

    function setTokenThreshold(address token, uint256 thresholdBps) external onlyOwner {
        require(thresholdBps > 0 && thresholdBps <= MAX_PRICE_DEVIATION_BPS, "FlashGuard: invalid threshold");
        priceDeviationThreshold[token] = thresholdBps;
        emit ThresholdUpdated(token, thresholdBps);
    }

    function setMaxTxPerBlock(uint256 _max) external onlyOwner {
        require(_max > 0 && _max <= 100, "FlashGuard: invalid max");
        maxTxPerBlockPerToken = _max;
    }

    // ---- Pre-Transaction Guard ----

    /// @notice Called before a guarded operation to snapshot state
    /// @param target The protected contract
    /// @param token The token involved
    /// @param amount The transaction amount
    function preGuard(
        address target,
        address token,
        uint256 amount
    ) external nonReentrant returns (uint256 txId) {
        require(!circuitBreakerTripped || block.timestamp > circuitBreakerTrippedAt + circuitBreakerCooldown, "FlashGuard: circuit breaker active");

        bool flagged = false;
        string memory flagReason = "";

        // 1. Check sandwich attack: too many txs in same block for same token
        blockTxCount[block.number][token]++;
        if (blockTxCount[block.number][token] > maxTxPerBlockPerToken) {
            flagged = true;
            flagReason = "Potential sandwich: excessive same-block txs";
            emit SandwichAttackDetected(token, block.number, blockTxCount[block.number][token]);
        }

        // 2. Check price deviation
        if (address(priceOracle) != address(0)) {
            uint256 threshold = priceDeviationThreshold[token];
            if (threshold == 0) threshold = MAX_PRICE_DEVIATION_BPS;

            try priceOracle.getPrice(token) returns (uint256 currentPrice) {
                PriceSnapshot storage snap = lastPriceSnapshot[token];
                if (snap.price > 0 && snap.blockNumber < block.number) {
                    uint256 deviation;
                    if (currentPrice > snap.price) {
                        deviation = ((currentPrice - snap.price) * BASIS_POINTS) / snap.price;
                    } else {
                        deviation = ((snap.price - currentPrice) * BASIS_POINTS) / snap.price;
                    }

                    if (deviation > threshold) {
                        flagged = true;
                        flagReason = "Price deviation exceeds threshold";
                        emit PriceDeviationDetected(token, snap.price, currentPrice, deviation);
                    }
                }
                snap.price = currentPrice;
                snap.blockNumber = block.number;
                snap.timestamp = block.timestamp;
            } catch {
                // Oracle failed, continue without price check
            }
        }

        // 3. Snapshot balance for flash loan detection
        if (protectedContracts[target]) {
            preTransactionBalance[target][token] = IERC20(token).balanceOf(target);
        }

        // Record guarded transaction
        txId = guardedTransactions.length;
        guardedTransactions.push(GuardedTx({
            id: txId,
            sender: msg.sender,
            target: target,
            token: token,
            amount: amount,
            blockNumber: block.number,
            timestamp: block.timestamp,
            flagged: flagged,
            flagReason: flagReason
        }));

        // Trip circuit breaker if flagged
        if (flagged) {
            _tripCircuitBreaker(flagReason);
        }

        emit TransactionGuarded(txId, msg.sender, token, amount, flagged);
    }

    // ---- Post-Transaction Guard ----

    /// @notice Called after a guarded operation to detect flash loans
    /// @param target The protected contract
    /// @param token The token involved
    function postGuard(address target, address token) external {
        if (!protectedContracts[target]) return;

        uint256 balanceBefore = preTransactionBalance[target][token];
        uint256 balanceAfter = IERC20(token).balanceOf(target);

        // If balance returned to same level within same tx, likely flash loan
        if (balanceBefore > 0 && balanceAfter >= balanceBefore) {
            // Check if there was a significant intermediate draw
            // (Heuristic: if balance is same but we recorded a large tx, it was flash-loaned)
            emit FlashLoanDetected(target, token, balanceBefore, balanceAfter);
        }

        // Cleanup
        preTransactionBalance[target][token] = 0;
    }

    // ---- Circuit Breaker ----

    function _tripCircuitBreaker(string memory reason) internal {
        if (!circuitBreakerTripped) {
            circuitBreakerTripped = true;
            circuitBreakerTrippedAt = block.timestamp;
            emit CircuitBreakerTripped(msg.sender, reason);
        }
    }

    /// @notice Manually trip the circuit breaker
    function tripCircuitBreaker(string calldata reason) external onlyOwner {
        _tripCircuitBreaker(reason);
    }

    /// @notice Reset the circuit breaker
    function resetCircuitBreaker() external onlyOwner {
        circuitBreakerTripped = false;
        emit CircuitBreakerReset(msg.sender);
    }

    function setCircuitBreakerCooldown(uint256 _cooldown) external onlyOwner {
        require(_cooldown >= 5 minutes && _cooldown <= 24 hours, "FlashGuard: invalid cooldown");
        circuitBreakerCooldown = _cooldown;
    }

    // ---- View Functions ----

    /// @notice Check if a transaction would be flagged (dry-run)
    function wouldFlag(address token) external view returns (bool flagged, string memory reason) {
        // Check same-block tx count
        if (blockTxCount[block.number][token] >= maxTxPerBlockPerToken) {
            return (true, "Potential sandwich: excessive same-block txs");
        }

        // Check price deviation
        if (address(priceOracle) != address(0)) {
            uint256 threshold = priceDeviationThreshold[token];
            if (threshold == 0) threshold = MAX_PRICE_DEVIATION_BPS;

            try priceOracle.getPrice(token) returns (uint256 currentPrice) {
                PriceSnapshot storage snap = lastPriceSnapshot[token];
                if (snap.price > 0) {
                    uint256 deviation;
                    if (currentPrice > snap.price) {
                        deviation = ((currentPrice - snap.price) * BASIS_POINTS) / snap.price;
                    } else {
                        deviation = ((snap.price - currentPrice) * BASIS_POINTS) / snap.price;
                    }
                    if (deviation > threshold) {
                        return (true, "Price deviation exceeds threshold");
                    }
                }
            } catch {
                // Oracle unavailable
            }
        }

        return (false, "");
    }

    function guardedTxCount() external view returns (uint256) {
        return guardedTransactions.length;
    }

    function isCircuitBreakerActive() external view returns (bool) {
        if (!circuitBreakerTripped) return false;
        return block.timestamp <= circuitBreakerTrippedAt + circuitBreakerCooldown;
    }

    /// @notice Rescue stuck tokens
    function rescueTokens(address token, uint256 amount, address to) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
}
