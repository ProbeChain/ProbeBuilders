// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GoldToken
 * @author ProbeChain
 * @notice Gold-backed ERC-20 token with reserve proof tracking
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

contract GoldToken is Ownable, Pausable {
    /// @notice ERC-20 token name
    string public name;

    /// @notice ERC-20 token symbol
    string public symbol;

    /// @notice ERC-20 decimals
    uint8 public constant decimals = 18;

    /// @notice Total supply
    uint256 public totalSupply;

    /// @notice Gold reserve amount (in milligrams, tracked off-chain)
    uint256 public goldReserve;

    /// @notice Latest reserve proof hash
    bytes32 public reserveProofHash;

    /// @notice Reserve proof timestamp
    uint256 public reserveProofTimestamp;

    /// @dev Balance mapping
    mapping(address => uint256) private _balances;

    /// @dev Allowance mapping
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @dev Authorized minters
    mapping(address => bool) public minters;

    /// @notice Reserve proof history
    struct ReserveProof {
        bytes32 proofHash;
        uint256 goldReserve;
        uint256 totalSupplyAtProof;
        uint256 timestamp;
    }

    /// @dev Reserve proof history
    ReserveProof[] private _proofHistory;

    // ───────── Events ─────────

    /// @notice ERC-20 Transfer event
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice ERC-20 Approval event
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Emitted when gold is minted with reserve proof
    event GoldMinted(address indexed to, uint256 amount, bytes32 reserveProofHash);

    /// @notice Emitted when gold tokens are burned
    event GoldBurned(address indexed from, uint256 amount);

    /// @notice Emitted when reserve proof is updated
    event ReserveProofUpdated(bytes32 proofHash, uint256 goldReserve, uint256 timestamp);

    /// @notice Emitted when a minter is updated
    event MinterUpdated(address indexed minter, bool status);

    // ───────── Constructor ─────────

    constructor() {
        name = "ProbeGold Token";
        symbol = "pGOLD";
        totalSupply = 0;
        goldReserve = 0;
    }

    // ───────── Admin ─────────

    /// @notice Set minter status
    function setMinter(address minter, bool status) external onlyOwner {
        require(minter != address(0), "GoldToken: zero address");
        minters[minter] = status;
        emit MinterUpdated(minter, status);
    }

    /// @notice Pause/unpause
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── ERC-20 Functions ─────────

    /// @notice Get balance of an account
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Transfer tokens
    function transfer(address to, uint256 amount) external whenNotPaused returns (bool) {
        require(to != address(0), "GoldToken: zero address");
        require(_balances[msg.sender] >= amount, "GoldToken: insufficient balance");

        _balances[msg.sender] -= amount;
        _balances[to] += amount;

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /// @notice Get allowance
    function allowance(address tokenOwner, address spender) external view returns (uint256) {
        return _allowances[tokenOwner][spender];
    }

    /// @notice Approve spender
    function approve(address spender, uint256 amount) external whenNotPaused returns (bool) {
        require(spender != address(0), "GoldToken: zero address");
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfer tokens from another account
    function transferFrom(address from, address to, uint256 amount) external whenNotPaused returns (bool) {
        require(from != address(0), "GoldToken: zero from");
        require(to != address(0), "GoldToken: zero to");
        require(_balances[from] >= amount, "GoldToken: insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "GoldToken: insufficient allowance");

        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;

        emit Transfer(from, to, amount);
        return true;
    }

    // ───────── Gold-Specific Functions ─────────

    /// @notice Mint gold tokens with reserve proof (minter only)
    /// @param amount Amount of gold tokens to mint
    /// @param _reserveProofHash Hash of the gold reserve proof document
    function mintGold(uint256 amount, bytes32 _reserveProofHash) external whenNotPaused {
        require(minters[msg.sender] || msg.sender == owner(), "GoldToken: not minter");
        require(amount > 0, "GoldToken: zero amount");
        require(_reserveProofHash != bytes32(0), "GoldToken: empty proof");

        totalSupply += amount;
        _balances[msg.sender] += amount;
        reserveProofHash = _reserveProofHash;

        emit Transfer(address(0), msg.sender, amount);
        emit GoldMinted(msg.sender, amount, _reserveProofHash);
    }

    /// @notice Burn gold tokens
    /// @param amount Amount to burn
    function burnGold(uint256 amount) external whenNotPaused {
        require(amount > 0, "GoldToken: zero amount");
        require(_balances[msg.sender] >= amount, "GoldToken: insufficient balance");

        _balances[msg.sender] -= amount;
        totalSupply -= amount;

        emit Transfer(msg.sender, address(0), amount);
        emit GoldBurned(msg.sender, amount);
    }

    /// @notice Update gold reserve proof (owner or minter)
    /// @param _goldReserve New gold reserve amount in milligrams
    /// @param _proofHash Hash of the reserve proof document
    function updateReserveProof(uint256 _goldReserve, bytes32 _proofHash) external {
        require(msg.sender == owner() || minters[msg.sender], "GoldToken: not authorized");
        require(_proofHash != bytes32(0), "GoldToken: empty proof");

        goldReserve = _goldReserve;
        reserveProofHash = _proofHash;
        reserveProofTimestamp = block.timestamp;

        _proofHistory.push(ReserveProof({
            proofHash: _proofHash,
            goldReserve: _goldReserve,
            totalSupplyAtProof: totalSupply,
            timestamp: block.timestamp
        }));

        emit ReserveProofUpdated(_proofHash, _goldReserve, block.timestamp);
    }

    /// @notice Get reserve ratio (reserve per token in milligrams, scaled by 1e18)
    /// @return ratio Reserve ratio (0 if no supply)
    function getReserveRatio() external view returns (uint256 ratio) {
        if (totalSupply == 0) return 0;
        return (goldReserve * 1e18) / totalSupply;
    }

    /// @notice Get reserve proof history
    function getProofHistory() external view returns (ReserveProof[] memory) {
        return _proofHistory;
    }

    /// @notice Get proof history length
    function proofHistoryLength() external view returns (uint256) {
        return _proofHistory.length;
    }
}
