// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PrivateQuery
 * @author ProbeChain
 * @notice Privacy analytics query-response marketplace with data source registration
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

contract PrivateQuery is Ownable, ReentrancyGuard, Pausable {
    // --- Types ---
    enum QueryStatus { Open, Answered, Verified, Disputed, Refunded }

    struct DataSource {
        uint256 id;
        address provider;
        string name;
        bytes32 schemaHash;
        uint256 queryCount;
        uint256 totalEarned;
        bool active;
    }

    struct Query {
        uint256 id;
        uint256 dataSourceId;
        address requester;
        bytes32 queryHash;
        uint256 budget;
        address responder;
        bytes32 resultHash;
        bytes32 proofHash;
        QueryStatus status;
        uint256 submittedAt;
        uint256 answeredAt;
    }

    // --- State ---
    uint256 public nextSourceId;
    uint256 public nextQueryId;
    uint256 public constant PROVIDER_STAKE = 0.05 ether;
    uint256 public constant PLATFORM_FEE_BPS = 300; // 3%
    uint256 public constant QUERY_TIMEOUT = 3 days;

    mapping(uint256 => DataSource) public dataSources;
    mapping(uint256 => Query) public queries;
    mapping(address => uint256) public providerStakes;
    mapping(uint256 => uint256[]) private _sourceQueries;
    uint256 public platformFees;

    // --- Events ---
    event DataSourceRegistered(uint256 indexed sourceId, address indexed provider, string name);
    event DataSourceDeactivated(uint256 indexed sourceId);
    event QuerySubmitted(uint256 indexed queryId, uint256 indexed dataSourceId, address indexed requester, uint256 budget);
    event AnswerSubmitted(uint256 indexed queryId, address indexed responder, bytes32 resultHash);
    event AnswerVerified(uint256 indexed queryId, address indexed requester);
    event AnswerDisputed(uint256 indexed queryId, address indexed requester);
    event QueryRefunded(uint256 indexed queryId);
    event ProviderStaked(address indexed provider, uint256 amount);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // --- Errors ---
    error SourceNotFound();
    error SourceNotActive();
    error QueryNotFound();
    error InvalidQueryStatus();
    error InsufficientBudget();
    error InsufficientStake();
    error NotProvider();
    error NotRequester();
    error NotResponder();
    error QueryExpired();
    error QueryNotExpired();
    error NothingToWithdraw();

    // --- Provider Management ---

    /// @notice Stake to register as a data source provider
    function stakeAsProvider() external payable whenNotPaused {
        if (msg.value < PROVIDER_STAKE) revert InsufficientStake();
        providerStakes[msg.sender] += msg.value;
        emit ProviderStaked(msg.sender, msg.value);
    }

    /// @notice Register a new data source
    /// @param name Human-readable data source name
    /// @param schemaHash Hash of the data source schema
    /// @return sourceId The ID of the registered data source
    function registerDataSource(
        string calldata name,
        bytes32 schemaHash
    ) external whenNotPaused returns (uint256 sourceId) {
        if (providerStakes[msg.sender] < PROVIDER_STAKE) revert InsufficientStake();

        sourceId = nextSourceId++;
        dataSources[sourceId] = DataSource({
            id: sourceId,
            provider: msg.sender,
            name: name,
            schemaHash: schemaHash,
            queryCount: 0,
            totalEarned: 0,
            active: true
        });

        emit DataSourceRegistered(sourceId, msg.sender, name);
    }

    /// @notice Deactivate a data source
    function deactivateDataSource(uint256 sourceId) external {
        DataSource storage ds = dataSources[sourceId];
        if (ds.provider != msg.sender) revert NotProvider();
        ds.active = false;
        emit DataSourceDeactivated(sourceId);
    }

    // --- Query Lifecycle ---

    /// @notice Submit a privacy-preserving query
    /// @param dataSourceId The data source to query
    /// @param queryHash Hash of the encrypted query
    /// @param budget Payment budget for the query
    /// @return queryId The ID of the submitted query
    function submitQuery(
        uint256 dataSourceId,
        bytes32 queryHash,
        uint256 budget
    ) external payable whenNotPaused returns (uint256 queryId) {
        DataSource storage ds = dataSources[dataSourceId];
        if (ds.provider == address(0)) revert SourceNotFound();
        if (!ds.active) revert SourceNotActive();
        if (msg.value < budget || budget == 0) revert InsufficientBudget();

        queryId = nextQueryId++;
        queries[queryId] = Query({
            id: queryId,
            dataSourceId: dataSourceId,
            requester: msg.sender,
            queryHash: queryHash,
            budget: budget,
            responder: address(0),
            resultHash: bytes32(0),
            proofHash: bytes32(0),
            status: QueryStatus.Open,
            submittedAt: block.timestamp,
            answeredAt: 0
        });

        ds.queryCount++;
        _sourceQueries[dataSourceId].push(queryId);
        emit QuerySubmitted(queryId, dataSourceId, msg.sender, budget);
    }

    /// @notice Submit an answer to a query
    /// @param queryId The query to answer
    /// @param resultHash Hash of the encrypted result
    /// @param proofHash Hash of the privacy proof
    function submitAnswer(
        uint256 queryId,
        bytes32 resultHash,
        bytes32 proofHash
    ) external whenNotPaused {
        Query storage q = queries[queryId];
        if (q.requester == address(0)) revert QueryNotFound();
        if (q.status != QueryStatus.Open) revert InvalidQueryStatus();

        DataSource storage ds = dataSources[q.dataSourceId];
        if (ds.provider != msg.sender) revert NotProvider();

        q.responder = msg.sender;
        q.resultHash = resultHash;
        q.proofHash = proofHash;
        q.status = QueryStatus.Answered;
        q.answeredAt = block.timestamp;

        emit AnswerSubmitted(queryId, msg.sender, resultHash);
    }

    /// @notice Verify and accept an answer, releasing payment
    /// @param queryId The query to verify
    function verifyAnswer(uint256 queryId) external nonReentrant whenNotPaused {
        Query storage q = queries[queryId];
        if (q.requester != msg.sender) revert NotRequester();
        if (q.status != QueryStatus.Answered) revert InvalidQueryStatus();

        q.status = QueryStatus.Verified;

        uint256 fee = (q.budget * PLATFORM_FEE_BPS) / 10000;
        platformFees += fee;
        uint256 payment = q.budget - fee;

        DataSource storage ds = dataSources[q.dataSourceId];
        ds.totalEarned += payment;
        payable(q.responder).transfer(payment);

        emit AnswerVerified(queryId, msg.sender);
    }

    /// @notice Dispute an answer
    function disputeAnswer(uint256 queryId) external whenNotPaused {
        Query storage q = queries[queryId];
        if (q.requester != msg.sender) revert NotRequester();
        if (q.status != QueryStatus.Answered) revert InvalidQueryStatus();
        q.status = QueryStatus.Disputed;
        emit AnswerDisputed(queryId, msg.sender);
    }

    /// @notice Refund an expired unanswered query
    function refundQuery(uint256 queryId) external nonReentrant {
        Query storage q = queries[queryId];
        if (q.requester != msg.sender) revert NotRequester();
        if (q.status != QueryStatus.Open) revert InvalidQueryStatus();
        if (block.timestamp < q.submittedAt + QUERY_TIMEOUT) revert QueryNotExpired();

        q.status = QueryStatus.Refunded;
        payable(msg.sender).transfer(q.budget);
        emit QueryRefunded(queryId);
    }

    /// @notice Get queries for a data source
    function getSourceQueries(uint256 sourceId) external view returns (uint256[] memory) {
        return _sourceQueries[sourceId];
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
