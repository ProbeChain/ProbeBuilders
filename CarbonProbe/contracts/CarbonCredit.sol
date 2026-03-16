// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title CarbonCredit
 * @author ProbeBuilders
 * @notice Carbon credit trading token for ProbeChain Rydberg Testnet.
 *         ERC-20-like with mint, retire, and full provenance tracking per credit.
 * @dev Inline Ownable, ReentrancyGuard, Pausable. EVM London compatible.
 */

/* ───────── Abstract helpers (inlined) ───────── */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed prev, address indexed next_);
    error OwnableUnauthorized();
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorized(); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardLocked();
    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardLocked();
        _status = 2;
        _;
        _status = 1;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();
    modifier whenNotPaused() { if (_paused) revert ContractPaused(); _; }
    modifier whenPaused() { if (!_paused) revert ContractNotPaused(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

/* ───────── Main Contract ───────── */

contract CarbonCredit is Ownable, ReentrancyGuard, Pausable {

    /* ── Token metadata ── */

    string public constant name     = "ProbeChain Carbon Credit";
    string public constant symbol   = "pCARBON";
    uint8  public constant decimals = 18;

    /* ── Structs ── */

    /// @notice Carbon credit project metadata
    struct Project {
        uint256 id;
        string  name;
        string  methodology;
        string  location;
        address verifier;
        uint256 registeredAt;
        bool    active;
    }

    /// @notice A retirement record
    struct Retirement {
        address retiree;
        uint256 amount;
        string  reason;
        uint256 projectId;
        uint256 timestamp;
    }

    /* ── ERC-20 State ── */

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /* ── Carbon-specific State ── */

    uint256 public nextProjectId;
    mapping(uint256 => Project) public projects;
    mapping(address => bool) public authorizedMinters;

    /// @notice Total credits retired (burned)
    uint256 public totalRetired;
    /// @notice All retirement records
    Retirement[] private _retirements;
    /// @notice Per-user retirement records
    mapping(address => uint256[]) private _userRetirements;
    /// @notice Credits minted per project
    mapping(uint256 => uint256) public projectMinted;
    /// @notice Credits retired per project
    mapping(uint256 => uint256) public projectRetired;

    /* ── Events ── */

    /// @notice Standard ERC-20 Transfer
    event Transfer(address indexed from, address indexed to, uint256 value);
    /// @notice Standard ERC-20 Approval
    event Approval(address indexed owner_, address indexed spender, uint256 value);
    /// @notice Emitted when a project is registered
    event ProjectRegistered(uint256 indexed projectId, string name, address indexed verifier);
    /// @notice Emitted when credits are minted
    event CreditsMinted(uint256 indexed projectId, address indexed to, uint256 amount, address indexed verifier);
    /// @notice Emitted when credits are retired (burned)
    event CreditsRetired(address indexed retiree, uint256 amount, string reason, uint256 indexed projectId);
    /// @notice Emitted when minter authorization changes
    event MinterUpdated(address indexed minter, bool status);
    /// @notice Emitted when a project is deactivated
    event ProjectDeactivated(uint256 indexed projectId);

    /* ── Errors ── */

    error NotMinter();
    error ProjectNotActive();
    error InsufficientBalance();
    error InsufficientAllowance();
    error InvalidProject();

    /* ── Modifiers ── */

    modifier onlyMinter() {
        if (!authorizedMinters[msg.sender] && msg.sender != owner()) revert NotMinter();
        _;
    }

    /* ── Constructor ── */

    constructor() Ownable() {
        authorizedMinters[msg.sender] = true;
    }

    /* ── Admin ── */

    /// @notice Set minter authorization
    function setMinter(address minter, bool status) external onlyOwner {
        authorizedMinters[minter] = status;
        emit MinterUpdated(minter, status);
    }

    /* ── Project management ── */

    /**
     * @notice Register a new carbon credit project
     * @param projectName Project name
     * @param methodology Offset methodology (e.g. "VCS", "Gold Standard")
     * @param location Project location
     * @param verifier Address of the third-party verifier
     * @return projectId The created project ID
     */
    function registerProject(
        string calldata projectName,
        string calldata methodology,
        string calldata location,
        address verifier
    ) external onlyOwner returns (uint256 projectId) {
        require(bytes(projectName).length > 0, "empty name");
        require(verifier != address(0), "zero verifier");

        projectId = nextProjectId++;
        projects[projectId] = Project({
            id: projectId,
            name: projectName,
            methodology: methodology,
            location: location,
            verifier: verifier,
            registeredAt: block.timestamp,
            active: true
        });

        emit ProjectRegistered(projectId, projectName, verifier);
    }

    /// @notice Deactivate a project (no further minting)
    function deactivateProject(uint256 projectId) external onlyOwner {
        projects[projectId].active = false;
        emit ProjectDeactivated(projectId);
    }

    /* ── Minting ── */

    /**
     * @notice Mint carbon credits linked to a verified project
     * @param projectId The originating project
     * @param to Recipient address
     * @param amount Amount to mint (18 decimals)
     */
    function mintCredits(uint256 projectId, address to, uint256 amount) external onlyMinter whenNotPaused {
        require(to != address(0), "zero to");
        require(amount > 0, "zero amount");
        if (!projects[projectId].active) revert ProjectNotActive();

        totalSupply += amount;
        balanceOf[to] += amount;
        projectMinted[projectId] += amount;

        emit CreditsMinted(projectId, to, amount, msg.sender);
        emit Transfer(address(0), to, amount);
    }

    /* ── Retirement (burn) ── */

    /**
     * @notice Retire (burn) carbon credits with a stated reason
     * @param amount Amount to retire
     * @param reason Retirement reason (e.g. "Offset 2026 Q1 emissions")
     * @param projectId The project whose credits are being retired
     */
    function retireCredits(uint256 amount, string calldata reason, uint256 projectId) external nonReentrant whenNotPaused {
        require(amount > 0, "zero amount");
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        totalRetired += amount;
        projectRetired[projectId] += amount;

        uint256 idx = _retirements.length;
        _retirements.push(Retirement({
            retiree: msg.sender,
            amount: amount,
            reason: reason,
            projectId: projectId,
            timestamp: block.timestamp
        }));
        _userRetirements[msg.sender].push(idx);

        emit CreditsRetired(msg.sender, amount, reason, projectId);
        emit Transfer(msg.sender, address(0), amount);
    }

    /* ── ERC-20 transfers ── */

    /// @notice Transfer credits to another address
    function transfer(address to, uint256 amount) external whenNotPaused returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    /// @notice Transfer credits on behalf of another address
    function transferFrom(address from, address to, uint256 amount) external whenNotPaused returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < amount) revert InsufficientAllowance();
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        return _transfer(from, to, amount);
    }

    /// @notice Approve spending allowance
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /* ── View helpers ── */

    /// @notice Get retirement history for a user
    function getRetirementHistory(address user) external view returns (Retirement[] memory history) {
        uint256[] storage indices = _userRetirements[user];
        history = new Retirement[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            history[i] = _retirements[indices[i]];
        }
    }

    /// @notice Get all retirements
    function getAllRetirements() external view returns (Retirement[] memory) {
        return _retirements;
    }

    /// @notice Get retirement count
    function getRetirementCount() external view returns (uint256) {
        return _retirements.length;
    }

    /* ── Internal ── */

    function _transfer(address from, address to, uint256 amount) private returns (bool) {
        require(to != address(0), "zero to");
        if (balanceOf[from] < amount) revert InsufficientBalance();
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
