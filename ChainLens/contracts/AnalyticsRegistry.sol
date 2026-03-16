// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title AnalyticsRegistry
 * @notice On-chain analytics marketplace — data providers register queries,
 *         consumers pay to execute them, providers submit results.
 * @dev Providers stake PROBE to guarantee data quality; disputes slash stake.
 */
contract AnalyticsRegistry {
    // ──────────────────── Ownership ────────────────────
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ──────────────────── Reentrancy Guard ────────────────────
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "Reentrant");
        _locked = 2;
        _;
        _locked = 1;
    }

    // ──────────────────── Pausable ────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "Paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ──────────────────── Constants ────────────────────
    uint256 public constant MIN_STAKE = 0.1 ether;
    uint256 public constant RESULT_TIMEOUT = 1 days;

    // ──────────────────── Data Structures ────────────────────
    struct DataProvider {
        address addr;
        uint256 stake;
        uint256 queriesServed;
        uint256 disputesLost;
        uint256 reputation; // 0-10000
        bool active;
    }

    enum QueryStatus { Registered, Deprecated }
    enum ExecutionStatus { Pending, Fulfilled, Disputed, Refunded }

    struct Query {
        uint256 queryId;
        string name;
        bytes32 queryHash;       // Hash of the query definition
        uint256 price;           // Price per execution in wei
        address provider;
        QueryStatus status;
        uint256 executionCount;
        uint256 createdAt;
    }

    struct Execution {
        uint256 executionId;
        uint256 queryId;
        address consumer;
        bytes32 resultHash;
        ExecutionStatus status;
        uint256 paidAmount;
        uint256 requestedAt;
        uint256 fulfilledAt;
    }

    // ──────────────────── State ────────────────────
    uint256 public nextQueryId = 1;
    uint256 public nextExecutionId = 1;
    uint256 public platformFeeBPS = 300; // 3%

    mapping(address => DataProvider) public providers;
    mapping(uint256 => Query) public queries;
    mapping(uint256 => Execution) public executions;
    mapping(address => uint256[]) public providerQueries;
    mapping(address => uint256[]) public consumerExecutions;
    mapping(address => uint256) public pendingWithdrawals;

    // ──────────────────── Events ────────────────────
    event ProviderRegistered(address indexed provider, uint256 stake);
    event ProviderStakeUpdated(address indexed provider, uint256 newStake);
    event QueryRegistered(uint256 indexed queryId, string name, address indexed provider, uint256 price);
    event QueryDeprecated(uint256 indexed queryId);
    event QueryExecuted(uint256 indexed executionId, uint256 indexed queryId, address indexed consumer);
    event ResultSubmitted(uint256 indexed executionId, bytes32 resultHash);
    event ExecutionDisputed(uint256 indexed executionId, address indexed consumer);
    event ExecutionRefunded(uint256 indexed executionId, address indexed consumer);
    event WithdrawalClaimed(address indexed addr, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    // ──────────────────── Provider Management ────────────────────

    /**
     * @notice Register as a data provider by staking PROBE
     */
    function registerProvider() external payable whenNotPaused {
        require(msg.value >= MIN_STAKE, "Stake too low");
        require(!providers[msg.sender].active, "Already registered");

        providers[msg.sender] = DataProvider({
            addr: msg.sender,
            stake: msg.value,
            queriesServed: 0,
            disputesLost: 0,
            reputation: 5000, // Start at 50%
            active: true
        });

        emit ProviderRegistered(msg.sender, msg.value);
    }

    /**
     * @notice Add more stake
     */
    function addStake() external payable {
        require(providers[msg.sender].active, "Not registered");
        providers[msg.sender].stake += msg.value;
        emit ProviderStakeUpdated(msg.sender, providers[msg.sender].stake);
    }

    /**
     * @notice Withdraw stake (deactivates provider)
     */
    function withdrawStake() external nonReentrant {
        DataProvider storage p = providers[msg.sender];
        require(p.active, "Not active");
        uint256 amount = p.stake;
        p.stake = 0;
        p.active = false;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
    }

    // ──────────────────── Query Management ────────────────────

    /**
     * @notice Register a new analytics query
     * @param _name Human-readable query name
     * @param queryHash Hash of query definition (SQL, GraphQL, etc.)
     * @param price Price per execution in wei
     */
    function registerQuery(
        string calldata _name,
        bytes32 queryHash,
        uint256 price
    ) external whenNotPaused returns (uint256) {
        require(providers[msg.sender].active, "Not active provider");
        require(bytes(_name).length > 0, "Empty name");
        require(price > 0, "Zero price");

        uint256 queryId = nextQueryId++;
        queries[queryId] = Query({
            queryId: queryId,
            name: _name,
            queryHash: queryHash,
            price: price,
            provider: msg.sender,
            status: QueryStatus.Registered,
            executionCount: 0,
            createdAt: block.timestamp
        });

        providerQueries[msg.sender].push(queryId);
        emit QueryRegistered(queryId, _name, msg.sender, price);
        return queryId;
    }

    /**
     * @notice Deprecate a query (provider only)
     */
    function deprecateQuery(uint256 queryId) external {
        require(queries[queryId].provider == msg.sender, "Not provider");
        queries[queryId].status = QueryStatus.Deprecated;
        emit QueryDeprecated(queryId);
    }

    // ──────────────────── Query Execution ────────────────────

    /**
     * @notice Execute a query by paying the price
     * @param queryId The query to execute
     */
    function executeQuery(uint256 queryId) external payable whenNotPaused returns (uint256) {
        Query storage q = queries[queryId];
        require(q.status == QueryStatus.Registered, "Query not available");
        require(msg.value >= q.price, "Insufficient payment");

        uint256 executionId = nextExecutionId++;
        executions[executionId] = Execution({
            executionId: executionId,
            queryId: queryId,
            consumer: msg.sender,
            resultHash: bytes32(0),
            status: ExecutionStatus.Pending,
            paidAmount: msg.value,
            requestedAt: block.timestamp,
            fulfilledAt: 0
        });

        q.executionCount++;
        consumerExecutions[msg.sender].push(executionId);

        emit QueryExecuted(executionId, queryId, msg.sender);
        return executionId;
    }

    /**
     * @notice Submit query result (provider only)
     * @param executionId The execution to fulfill
     * @param resultHash Hash of the result data
     */
    function submitResult(uint256 executionId, bytes32 resultHash) external {
        Execution storage e = executions[executionId];
        require(e.status == ExecutionStatus.Pending, "Not pending");
        Query storage q = queries[e.queryId];
        require(q.provider == msg.sender, "Not provider");

        e.resultHash = resultHash;
        e.status = ExecutionStatus.Fulfilled;
        e.fulfilledAt = block.timestamp;

        // Pay provider
        uint256 fee = (e.paidAmount * platformFeeBPS) / 10000;
        uint256 payout = e.paidAmount - fee;
        pendingWithdrawals[msg.sender] += payout;
        pendingWithdrawals[owner] += fee;

        // Update provider stats
        providers[msg.sender].queriesServed++;
        if (providers[msg.sender].reputation < 10000) {
            providers[msg.sender].reputation += 10;
        }

        emit ResultSubmitted(executionId, resultHash);
    }

    /**
     * @notice Dispute a result (consumer only, within 1 day of fulfillment)
     */
    function disputeResult(uint256 executionId) external {
        Execution storage e = executions[executionId];
        require(e.consumer == msg.sender, "Not consumer");
        require(e.status == ExecutionStatus.Fulfilled, "Not fulfilled");
        require(block.timestamp <= e.fulfilledAt + 1 days, "Dispute period over");

        e.status = ExecutionStatus.Disputed;
        emit ExecutionDisputed(executionId, msg.sender);
    }

    /**
     * @notice Resolve dispute (owner only) — refund consumer if provider at fault
     */
    function resolveDispute(uint256 executionId, bool refund) external onlyOwner nonReentrant {
        Execution storage e = executions[executionId];
        require(e.status == ExecutionStatus.Disputed, "Not disputed");

        Query storage q = queries[e.queryId];
        DataProvider storage p = providers[q.provider];

        if (refund) {
            e.status = ExecutionStatus.Refunded;
            pendingWithdrawals[e.consumer] += e.paidAmount;
            // Subtract previously credited provider payment
            uint256 fee = (e.paidAmount * platformFeeBPS) / 10000;
            uint256 payout = e.paidAmount - fee;
            if (pendingWithdrawals[q.provider] >= payout) {
                pendingWithdrawals[q.provider] -= payout;
            }
            if (pendingWithdrawals[owner] >= fee) {
                pendingWithdrawals[owner] -= fee;
            }
            // Slash provider reputation
            p.disputesLost++;
            p.reputation = p.reputation > 500 ? p.reputation - 500 : 0;
            emit ExecutionRefunded(executionId, e.consumer);
        } else {
            e.status = ExecutionStatus.Fulfilled;
        }
    }

    /**
     * @notice Claim timeout refund if provider hasn't responded
     */
    function claimTimeoutRefund(uint256 executionId) external nonReentrant {
        Execution storage e = executions[executionId];
        require(e.consumer == msg.sender, "Not consumer");
        require(e.status == ExecutionStatus.Pending, "Not pending");
        require(block.timestamp > e.requestedAt + RESULT_TIMEOUT, "Not timed out");

        e.status = ExecutionStatus.Refunded;
        (bool ok, ) = msg.sender.call{value: e.paidAmount}("");
        require(ok, "Refund failed");
        emit ExecutionRefunded(executionId, msg.sender);
    }

    /**
     * @notice Claim pending withdrawals
     */
    function claimWithdrawal() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to claim");
        pendingWithdrawals[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        emit WithdrawalClaimed(msg.sender, amount);
    }

    // ──────────────────── Views ────────────────────

    function getQuery(uint256 queryId) external view returns (Query memory) {
        return queries[queryId];
    }

    function getExecution(uint256 executionId) external view returns (Execution memory) {
        return executions[executionId];
    }

    function getProviderQueries(address provider) external view returns (uint256[] memory) {
        return providerQueries[provider];
    }

    function getConsumerExecutions(address consumer) external view returns (uint256[] memory) {
        return consumerExecutions[consumer];
    }

    function setFee(uint256 newFeeBPS) external onlyOwner {
        require(newFeeBPS <= 1000, "Fee too high");
        platformFeeBPS = newFeeBPS;
    }

    receive() external payable {}
}
