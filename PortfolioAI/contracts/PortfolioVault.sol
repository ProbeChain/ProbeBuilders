// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PortfolioVault
 * @author ProbeChain
 * @notice AI-managed portfolio vault with weighted token allocation and rebalancing
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() { _status = _NOT_ENTERED; }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

abstract contract Pausable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function _pause() internal whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function _unpause() internal whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

contract PortfolioVault is Ownable, ReentrancyGuard, Pausable {
    /// @notice Portfolio definition
    struct Portfolio {
        uint256 id;
        address creator;
        string name;
        address[] tokens;
        uint256[] weights;
        uint256 totalDeposits;
        uint256 totalShares;
        uint256 createdAt;
        bool active;
    }

    /// @notice Depositor share record
    struct Deposit {
        uint256 shares;
        uint256 depositedAt;
    }

    /// @dev Portfolio counter
    uint256 private _nextPortfolioId;

    /// @dev Weight basis points denominator (10000 = 100%)
    uint256 public constant WEIGHT_DENOMINATOR = 10000;

    /// @dev Portfolio ID => Portfolio
    mapping(uint256 => Portfolio) private _portfolios;

    /// @dev Portfolio ID => user => deposit
    mapping(uint256 => mapping(address => Deposit)) private _deposits;

    /// @dev Authorized AI agents for rebalancing
    mapping(address => bool) public agents;

    /// @dev All portfolio IDs
    uint256[] private _portfolioIds;

    /// @dev Creator => portfolio IDs
    mapping(address => uint256[]) private _creatorPortfolios;

    // ───────── Events ─────────

    /// @notice Emitted when a portfolio is created
    event PortfolioCreated(uint256 indexed portfolioId, address indexed creator, string name);

    /// @notice Emitted when a deposit is made
    event Deposited(uint256 indexed portfolioId, address indexed user, uint256 amount, uint256 shares);

    /// @notice Emitted when portfolio is rebalanced
    event Rebalanced(uint256 indexed portfolioId, uint256[] newWeights, address indexed agent);

    /// @notice Emitted when shares are withdrawn
    event Withdrawn(uint256 indexed portfolioId, address indexed user, uint256 shares, uint256 amount);

    /// @notice Emitted when an agent is updated
    event AgentUpdated(address indexed agent, bool status);

    /// @notice Emitted when a portfolio is deactivated
    event PortfolioDeactivated(uint256 indexed portfolioId);

    // ───────── Constructor ─────────

    constructor() {
        _nextPortfolioId = 1;
    }

    // ───────── Admin ─────────

    /// @notice Set agent status
    function setAgent(address agent, bool status) external onlyOwner {
        require(agent != address(0), "PortfolioVault: zero address");
        agents[agent] = status;
        emit AgentUpdated(agent, status);
    }

    /// @notice Pause/unpause
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Create a new portfolio with token allocation weights
    /// @param _name Portfolio name
    /// @param _tokens Array of token addresses in the portfolio
    /// @param _weights Array of weights in basis points (must sum to 10000)
    /// @return portfolioId The new portfolio ID
    function createPortfolio(
        string calldata _name,
        address[] calldata _tokens,
        uint256[] calldata _weights
    ) external whenNotPaused returns (uint256 portfolioId) {
        require(bytes(_name).length > 0, "PortfolioVault: empty name");
        require(_tokens.length > 0, "PortfolioVault: no tokens");
        require(_tokens.length == _weights.length, "PortfolioVault: length mismatch");
        require(_tokens.length <= 20, "PortfolioVault: too many tokens");

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < _weights.length; i++) {
            require(_weights[i] > 0, "PortfolioVault: zero weight");
            require(_tokens[i] != address(0), "PortfolioVault: zero token");
            totalWeight += _weights[i];
        }
        require(totalWeight == WEIGHT_DENOMINATOR, "PortfolioVault: weights must sum to 10000");

        portfolioId = _nextPortfolioId++;

        Portfolio storage p = _portfolios[portfolioId];
        p.id = portfolioId;
        p.creator = msg.sender;
        p.name = _name;
        p.totalDeposits = 0;
        p.totalShares = 0;
        p.createdAt = block.timestamp;
        p.active = true;

        for (uint256 i = 0; i < _tokens.length; i++) {
            p.tokens.push(_tokens[i]);
            p.weights.push(_weights[i]);
        }

        _portfolioIds.push(portfolioId);
        _creatorPortfolios[msg.sender].push(portfolioId);

        emit PortfolioCreated(portfolioId, msg.sender, _name);
    }

    /// @notice Deposit PROBE into a portfolio
    /// @param portfolioId The portfolio to deposit into
    function deposit(uint256 portfolioId) external payable whenNotPaused nonReentrant {
        Portfolio storage p = _portfolios[portfolioId];
        require(p.active, "PortfolioVault: not active");
        require(msg.value > 0, "PortfolioVault: zero amount");

        uint256 shares;
        if (p.totalShares == 0) {
            shares = msg.value;
        } else {
            shares = (msg.value * p.totalShares) / p.totalDeposits;
        }

        p.totalDeposits += msg.value;
        p.totalShares += shares;

        Deposit storage d = _deposits[portfolioId][msg.sender];
        d.shares += shares;
        if (d.depositedAt == 0) {
            d.depositedAt = block.timestamp;
        }

        emit Deposited(portfolioId, msg.sender, msg.value, shares);
    }

    /// @notice Rebalance portfolio weights (agent or creator only)
    /// @param portfolioId The portfolio to rebalance
    /// @param newWeights New weight allocations in basis points
    function rebalance(
        uint256 portfolioId,
        uint256[] calldata newWeights
    ) external whenNotPaused {
        Portfolio storage p = _portfolios[portfolioId];
        require(p.active, "PortfolioVault: not active");
        require(
            agents[msg.sender] || msg.sender == p.creator,
            "PortfolioVault: not authorized"
        );
        require(newWeights.length == p.tokens.length, "PortfolioVault: length mismatch");

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < newWeights.length; i++) {
            require(newWeights[i] > 0, "PortfolioVault: zero weight");
            totalWeight += newWeights[i];
        }
        require(totalWeight == WEIGHT_DENOMINATOR, "PortfolioVault: weights must sum to 10000");

        for (uint256 i = 0; i < newWeights.length; i++) {
            p.weights[i] = newWeights[i];
        }

        emit Rebalanced(portfolioId, newWeights, msg.sender);
    }

    /// @notice Withdraw shares from a portfolio
    /// @param portfolioId The portfolio to withdraw from
    /// @param shares Number of shares to redeem
    function withdraw(
        uint256 portfolioId,
        uint256 shares
    ) external whenNotPaused nonReentrant {
        Portfolio storage p = _portfolios[portfolioId];
        require(p.active, "PortfolioVault: not active");

        Deposit storage d = _deposits[portfolioId][msg.sender];
        require(d.shares >= shares, "PortfolioVault: insufficient shares");
        require(shares > 0, "PortfolioVault: zero shares");

        uint256 amount = (shares * p.totalDeposits) / p.totalShares;
        require(amount > 0, "PortfolioVault: zero amount");

        d.shares -= shares;
        p.totalShares -= shares;
        p.totalDeposits -= amount;

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "PortfolioVault: transfer failed");

        emit Withdrawn(portfolioId, msg.sender, shares, amount);
    }

    /// @notice Deactivate a portfolio (creator only)
    function deactivatePortfolio(uint256 portfolioId) external {
        Portfolio storage p = _portfolios[portfolioId];
        require(p.creator == msg.sender || msg.sender == owner(), "PortfolioVault: not authorized");
        require(p.active, "PortfolioVault: not active");
        p.active = false;
        emit PortfolioDeactivated(portfolioId);
    }

    // ───────── View Functions ─────────

    /// @notice Get portfolio details
    function getPortfolio(uint256 portfolioId) external view returns (Portfolio memory) {
        require(_portfolios[portfolioId].createdAt > 0, "PortfolioVault: not found");
        return _portfolios[portfolioId];
    }

    /// @notice Get user deposit in a portfolio
    function getDeposit(uint256 portfolioId, address user) external view returns (Deposit memory) {
        return _deposits[portfolioId][user];
    }

    /// @notice Get portfolios by creator
    function getCreatorPortfolios(address creator) external view returns (uint256[] memory) {
        return _creatorPortfolios[creator];
    }

    /// @notice Total portfolios
    function totalPortfolios() external view returns (uint256) {
        return _nextPortfolioId - 1;
    }

    /// @notice Calculate share value in PROBE
    function getShareValue(uint256 portfolioId, uint256 shares) external view returns (uint256) {
        Portfolio memory p = _portfolios[portfolioId];
        if (p.totalShares == 0) return 0;
        return (shares * p.totalDeposits) / p.totalShares;
    }
}
