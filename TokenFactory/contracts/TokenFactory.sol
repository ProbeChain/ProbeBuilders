// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title TokenFactory
 * @author ProbeChain
 * @notice One-click ERC-20 token creation factory
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

/// @notice Minimal ERC-20 token deployed by the factory
contract FactoryToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    address public creator;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint8 _decimals,
        address _creator
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _totalSupply;
        creator = _creator;
        _balances[_creator] = _totalSupply;
        emit Transfer(address(0), _creator, _totalSupply);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), "ERC20: zero address");
        require(_balances[msg.sender] >= amount, "ERC20: insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address tokenOwner, address spender) external view returns (uint256) {
        return _allowances[tokenOwner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        require(spender != address(0), "ERC20: zero address");
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(from != address(0), "ERC20: zero from");
        require(to != address(0), "ERC20: zero to");
        require(_balances[from] >= amount, "ERC20: insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "ERC20: insufficient allowance");
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

contract TokenFactory is Ownable, Pausable {
    /// @notice Token info record
    struct TokenInfo {
        address tokenAddress;
        string name;
        string symbol;
        uint256 totalSupply;
        uint8 decimals;
        address creator;
        uint256 createdAt;
    }

    /// @dev Creation fee
    uint256 public creationFee;

    /// @dev All deployed tokens
    TokenInfo[] private _allTokens;

    /// @dev Creator => token addresses
    mapping(address => address[]) private _creatorTokens;

    /// @dev Token address => TokenInfo index + 1
    mapping(address => uint256) private _tokenIndex;

    // ───────── Events ─────────

    /// @notice Emitted when a new token is created
    event TokenCreated(address indexed tokenAddress, address indexed creator, string name, string symbol, uint256 totalSupply);

    /// @notice Emitted when creation fee changes
    event CreationFeeUpdated(uint256 newFee);

    /// @notice Emitted when fees are withdrawn
    event FeesWithdrawn(address indexed to, uint256 amount);

    // ───────── Constructor ─────────

    constructor() {
        creationFee = 0;
    }

    // ───────── Admin ─────────

    /// @notice Set creation fee
    function setCreationFee(uint256 fee) external onlyOwner {
        creationFee = fee;
        emit CreationFeeUpdated(fee);
    }

    /// @notice Withdraw collected fees
    function withdrawFees(address payable to) external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "TokenFactory: no fees");
        (bool sent, ) = to.call{value: balance}("");
        require(sent, "TokenFactory: transfer failed");
        emit FeesWithdrawn(to, balance);
    }

    /// @notice Pause/unpause
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Create a new ERC-20 token
    /// @param _name Token name
    /// @param _symbol Token symbol
    /// @param _totalSupply Total supply (in smallest units)
    /// @param _decimals Token decimals
    /// @return tokenAddress The deployed token address
    function createToken(
        string calldata _name,
        string calldata _symbol,
        uint256 _totalSupply,
        uint8 _decimals
    ) external payable whenNotPaused returns (address tokenAddress) {
        require(bytes(_name).length > 0, "TokenFactory: empty name");
        require(bytes(_symbol).length > 0, "TokenFactory: empty symbol");
        require(_totalSupply > 0, "TokenFactory: zero supply");
        require(_decimals <= 18, "TokenFactory: decimals too high");
        require(msg.value >= creationFee, "TokenFactory: insufficient fee");

        FactoryToken token = new FactoryToken(
            _name,
            _symbol,
            _totalSupply,
            _decimals,
            msg.sender
        );

        tokenAddress = address(token);

        _allTokens.push(TokenInfo({
            tokenAddress: tokenAddress,
            name: _name,
            symbol: _symbol,
            totalSupply: _totalSupply,
            decimals: _decimals,
            creator: msg.sender,
            createdAt: block.timestamp
        }));

        _tokenIndex[tokenAddress] = _allTokens.length;
        _creatorTokens[msg.sender].push(tokenAddress);

        // Refund excess
        if (msg.value > creationFee && creationFee > 0) {
            (bool sent, ) = msg.sender.call{value: msg.value - creationFee}("");
            require(sent, "TokenFactory: refund failed");
        }

        emit TokenCreated(tokenAddress, msg.sender, _name, _symbol, _totalSupply);
    }

    // ───────── View Functions ─────────

    /// @notice Get all tokens deployed by a creator
    function getDeployedTokens(address creator) external view returns (address[] memory) {
        return _creatorTokens[creator];
    }

    /// @notice Get token info by address
    function getTokenInfo(address tokenAddr) external view returns (TokenInfo memory) {
        uint256 idx = _tokenIndex[tokenAddr];
        require(idx > 0, "TokenFactory: not found");
        return _allTokens[idx - 1];
    }

    /// @notice Get total tokens created
    function totalTokens() external view returns (uint256) {
        return _allTokens.length;
    }

    /// @notice Get all token infos (paginated)
    function getAllTokens(uint256 offset, uint256 limit) external view returns (TokenInfo[] memory) {
        if (offset >= _allTokens.length) {
            return new TokenInfo[](0);
        }
        uint256 end = offset + limit;
        if (end > _allTokens.length) end = _allTokens.length;
        TokenInfo[] memory result = new TokenInfo[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = _allTokens[i];
        }
        return result;
    }
}
