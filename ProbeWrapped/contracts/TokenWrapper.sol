// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TokenWrapper
 * @author ProbeChain
 * @notice WETH-pattern wrapper for native PROBE token (wPROBE)
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

contract TokenWrapper is Ownable, ReentrancyGuard, Pausable {
    /// @notice Token name
    string public constant name = "Wrapped PROBE";

    /// @notice Token symbol
    string public constant symbol = "wPROBE";

    /// @notice Token decimals
    uint8 public constant decimals = 18;

    /// @notice Total supply of wPROBE
    uint256 public totalSupply;

    /// @dev Balance mapping
    mapping(address => uint256) private _balances;

    /// @dev Allowance mapping
    mapping(address => mapping(address => uint256)) private _allowances;

    /// @dev Total wrapped amount tracking
    uint256 public totalWrapped;

    /// @dev Total unwrapped amount tracking
    uint256 public totalUnwrapped;

    // ───────── Events ─────────

    /// @notice ERC-20 Transfer event
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice ERC-20 Approval event
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Emitted when PROBE is wrapped to wPROBE
    event Wrapped(address indexed account, uint256 amount);

    /// @notice Emitted when wPROBE is unwrapped to PROBE
    event Unwrapped(address indexed account, uint256 amount);

    // ───────── Constructor ─────────

    constructor() {
        totalSupply = 0;
    }

    // ───────── Admin ─────────

    /// @notice Pause/unpause
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Wrap / Unwrap ─────────

    /// @notice Wrap native PROBE to wPROBE
    /// @dev Send PROBE with the transaction to receive wPROBE
    function wrap() external payable whenNotPaused nonReentrant {
        require(msg.value > 0, "TokenWrapper: zero amount");

        _balances[msg.sender] += msg.value;
        totalSupply += msg.value;
        totalWrapped += msg.value;

        emit Transfer(address(0), msg.sender, msg.value);
        emit Wrapped(msg.sender, msg.value);
    }

    /// @notice Unwrap wPROBE back to native PROBE
    /// @param amount Amount of wPROBE to unwrap
    function unwrap(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "TokenWrapper: zero amount");
        require(_balances[msg.sender] >= amount, "TokenWrapper: insufficient balance");

        _balances[msg.sender] -= amount;
        totalSupply -= amount;
        totalUnwrapped += amount;

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "TokenWrapper: transfer failed");

        emit Transfer(msg.sender, address(0), amount);
        emit Unwrapped(msg.sender, amount);
    }

    /// @notice Receive function to auto-wrap incoming PROBE
    receive() external payable {
        require(msg.value > 0, "TokenWrapper: zero amount");

        _balances[msg.sender] += msg.value;
        totalSupply += msg.value;
        totalWrapped += msg.value;

        emit Transfer(address(0), msg.sender, msg.value);
        emit Wrapped(msg.sender, msg.value);
    }

    // ───────── ERC-20 Functions ─────────

    /// @notice Get balance
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice Transfer wPROBE
    function transfer(address to, uint256 amount) external whenNotPaused returns (bool) {
        require(to != address(0), "TokenWrapper: zero address");
        require(_balances[msg.sender] >= amount, "TokenWrapper: insufficient balance");

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
        require(spender != address(0), "TokenWrapper: zero address");
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Transfer from
    function transferFrom(address from, address to, uint256 amount) external whenNotPaused returns (bool) {
        require(from != address(0), "TokenWrapper: zero from");
        require(to != address(0), "TokenWrapper: zero to");
        require(_balances[from] >= amount, "TokenWrapper: insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "TokenWrapper: insufficient allowance");

        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;

        emit Transfer(from, to, amount);
        return true;
    }

    // ───────── View Functions ─────────

    /// @notice Get the contract's PROBE balance (should equal totalSupply)
    function reserveBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Check if the wrapper is fully backed
    function isFullyBacked() external view returns (bool) {
        return address(this).balance >= totalSupply;
    }
}
