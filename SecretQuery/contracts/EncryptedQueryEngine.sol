// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title EncryptedQueryEngine
 * @author ProbeChain
 * @notice Encrypted query engine with database registration and payment-based query submission
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London)
 */

// --- Inline Ownable ---
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorized(address account);
    error OwnableInvalidOwner(address owner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorized(msg.sender);
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(newOwner);
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// --- Inline ReentrancyGuard ---
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

// --- Inline Pausable ---
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();

    modifier whenNotPaused() {
        if (_paused) revert ContractPaused();
        _;
    }

    function paused() public view returns (bool) { return _paused; }

    function pause() external onlyOwner {
        if (_paused) revert ContractPaused();
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        if (!_paused) revert ContractNotPaused();
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract EncryptedQueryEngine is Ownable, ReentrancyGuard, Pausable {
    // --- Types ---
    enum QueryStatus { Pending, ResultSubmitted, Confirmed, Rejected, Refunded }

    struct Database {
        uint256 id;
        address owner;
        string name;
        bytes32 schemaHash;
        bytes32 publicKey;
        uint256 queryPrice;
        uint256 totalQueries;
        uint256 totalEarned;
        bool active;
    }

    struct EncryptedQuery {
        uint256 id;
        uint256 dbId;
        address requester;
        bytes32 encryptedQuery;
        uint256 payment;
        bytes32 encryptedResult;
        QueryStatus status;
        uint256 submittedAt;
        uint256 resultAt;
    }

    // --- State ---
    uint256 public nextDbId;
    uint256 public nextQueryId;
    uint256 public constant PLATFORM_FEE_BPS = 200; // 2%
    uint256 public constant RESULT_TIMEOUT = 2 days;
    uint256 public constant CONFIRM_TIMEOUT = 3 days;

    mapping(uint256 => Database) public databases;
    mapping(uint256 => EncryptedQuery) public encryptedQueries;
    mapping(uint256 => uint256[]) private _dbQueries;
    mapping(address => uint256[]) private _userQueries;
    uint256 public platformFees;

    // --- Events ---
    event DatabaseRegistered(uint256 indexed dbId, address indexed dbOwner, string name, bytes32 publicKey);
    event DatabaseUpdated(uint256 indexed dbId, uint256 newPrice);
    event DatabaseDeactivated(uint256 indexed dbId);
    event QuerySubmitted(uint256 indexed queryId, uint256 indexed dbId, address indexed requester, uint256 payment);
    event ResultSubmitted(uint256 indexed queryId, bytes32 encryptedResult);
    event ResultConfirmed(uint256 indexed queryId);
    event ResultRejected(uint256 indexed queryId);
    event QueryRefunded(uint256 indexed queryId);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // --- Errors ---
    error DatabaseNotFound();
    error DatabaseNotActive();
    error QueryNotFound();
    error InvalidQueryStatus();
    error InsufficientPayment();
    error NotDatabaseOwner();
    error NotQueryRequester();
    error TimeoutNotReached();
    error NothingToWithdraw();
    error InvalidPublicKey();

    // --- Database Management ---

    /// @notice Register a new encrypted database
    /// @param name Database name
    /// @param schemaHash Hash of the database schema
    /// @param publicKey Public encryption key for queries
    /// @return dbId The ID of the registered database
    function registerDatabase(
        string calldata name,
        bytes32 schemaHash,
        bytes32 publicKey
    ) external whenNotPaused returns (uint256 dbId) {
        if (publicKey == bytes32(0)) revert InvalidPublicKey();

        dbId = nextDbId++;
        databases[dbId] = Database({
            id: dbId,
            owner: msg.sender,
            name: name,
            schemaHash: schemaHash,
            publicKey: publicKey,
            queryPrice: 0,
            totalQueries: 0,
            totalEarned: 0,
            active: true
        });

        emit DatabaseRegistered(dbId, msg.sender, name, publicKey);
    }

    /// @notice Update database query price
    /// @param dbId The database ID
    /// @param newPrice New price per query in wei
    function updateQueryPrice(uint256 dbId, uint256 newPrice) external {
        Database storage db = databases[dbId];
        if (db.owner != msg.sender) revert NotDatabaseOwner();
        db.queryPrice = newPrice;
        emit DatabaseUpdated(dbId, newPrice);
    }

    /// @notice Deactivate a database
    function deactivateDatabase(uint256 dbId) external {
        Database storage db = databases[dbId];
        if (db.owner != msg.sender) revert NotDatabaseOwner();
        db.active = false;
        emit DatabaseDeactivated(dbId);
    }

    // --- Query Lifecycle ---

    /// @notice Submit an encrypted query
    /// @param dbId The database to query
    /// @param encryptedQuery The encrypted query data
    /// @param payment Payment amount for the query
    /// @return queryId The ID of the submitted query
    function submitEncryptedQuery(
        uint256 dbId,
        bytes32 encryptedQuery,
        uint256 payment
    ) external payable whenNotPaused returns (uint256 queryId) {
        Database storage db = databases[dbId];
        if (db.owner == address(0)) revert DatabaseNotFound();
        if (!db.active) revert DatabaseNotActive();
        if (msg.value < payment || payment < db.queryPrice) revert InsufficientPayment();

        queryId = nextQueryId++;
        encryptedQueries[queryId] = EncryptedQuery({
            id: queryId,
            dbId: dbId,
            requester: msg.sender,
            encryptedQuery: encryptedQuery,
            payment: payment,
            encryptedResult: bytes32(0),
            status: QueryStatus.Pending,
            submittedAt: block.timestamp,
            resultAt: 0
        });

        db.totalQueries++;
        _dbQueries[dbId].push(queryId);
        _userQueries[msg.sender].push(queryId);

        emit QuerySubmitted(queryId, dbId, msg.sender, payment);
    }

    /// @notice Submit encrypted result for a query
    /// @param queryId The query to respond to
    /// @param encryptedResult The encrypted query result
    function submitEncryptedResult(uint256 queryId, bytes32 encryptedResult) external whenNotPaused {
        EncryptedQuery storage q = encryptedQueries[queryId];
        if (q.requester == address(0)) revert QueryNotFound();
        if (q.status != QueryStatus.Pending) revert InvalidQueryStatus();

        Database storage db = databases[q.dbId];
        if (db.owner != msg.sender) revert NotDatabaseOwner();

        q.encryptedResult = encryptedResult;
        q.status = QueryStatus.ResultSubmitted;
        q.resultAt = block.timestamp;

        emit ResultSubmitted(queryId, encryptedResult);
    }

    /// @notice Confirm receipt of result and release payment
    /// @param queryId The query to confirm
    function confirmResult(uint256 queryId) external nonReentrant whenNotPaused {
        EncryptedQuery storage q = encryptedQueries[queryId];
        if (q.requester != msg.sender) revert NotQueryRequester();
        if (q.status != QueryStatus.ResultSubmitted) revert InvalidQueryStatus();

        q.status = QueryStatus.Confirmed;

        uint256 fee = (q.payment * PLATFORM_FEE_BPS) / 10000;
        platformFees += fee;
        uint256 dbPayment = q.payment - fee;

        Database storage db = databases[q.dbId];
        db.totalEarned += dbPayment;
        payable(db.owner).transfer(dbPayment);

        emit ResultConfirmed(queryId);
    }

    /// @notice Reject a result (requester)
    function rejectResult(uint256 queryId) external whenNotPaused {
        EncryptedQuery storage q = encryptedQueries[queryId];
        if (q.requester != msg.sender) revert NotQueryRequester();
        if (q.status != QueryStatus.ResultSubmitted) revert InvalidQueryStatus();
        q.status = QueryStatus.Rejected;
        emit ResultRejected(queryId);
    }

    /// @notice Refund a timed-out query (no result submitted)
    function refundQuery(uint256 queryId) external nonReentrant {
        EncryptedQuery storage q = encryptedQueries[queryId];
        if (q.requester != msg.sender) revert NotQueryRequester();
        if (q.status != QueryStatus.Pending) revert InvalidQueryStatus();
        if (block.timestamp < q.submittedAt + RESULT_TIMEOUT) revert TimeoutNotReached();

        q.status = QueryStatus.Refunded;
        payable(msg.sender).transfer(q.payment);
        emit QueryRefunded(queryId);
    }

    /// @notice Auto-confirm result after timeout (database owner)
    function autoConfirmResult(uint256 queryId) external nonReentrant {
        EncryptedQuery storage q = encryptedQueries[queryId];
        if (q.status != QueryStatus.ResultSubmitted) revert InvalidQueryStatus();
        if (block.timestamp < q.resultAt + CONFIRM_TIMEOUT) revert TimeoutNotReached();

        Database storage db = databases[q.dbId];
        if (db.owner != msg.sender) revert NotDatabaseOwner();

        q.status = QueryStatus.Confirmed;
        uint256 fee = (q.payment * PLATFORM_FEE_BPS) / 10000;
        platformFees += fee;
        uint256 dbPayment = q.payment - fee;
        db.totalEarned += dbPayment;
        payable(db.owner).transfer(dbPayment);

        emit ResultConfirmed(queryId);
    }

    /// @notice Get queries for a database
    function getDatabaseQueries(uint256 dbId) external view returns (uint256[] memory) {
        return _dbQueries[dbId];
    }

    /// @notice Get queries for a user
    function getUserQueries(address user) external view returns (uint256[] memory) {
        return _userQueries[user];
    }

    /// @notice Withdraw platform fees
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = platformFees;
        if (amount == 0) revert NothingToWithdraw();
        platformFees = 0;
        payable(owner()).transfer(amount);
        emit FeesWithdrawn(owner(), amount);
    }
}
