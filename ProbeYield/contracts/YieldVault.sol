// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title YieldVault
 * @author ProbeBuilders
 * @notice ERC-4626 compatible yield aggregator vault for ProbeChain Rydberg Testnet.
 * @dev Accepts ERC20 deposits, tracks shares, delegates to a pluggable Strategy.
 */

// ============ Interfaces ============

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

/// @notice Strategy interface that the vault delegates funds to
interface IStrategy {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function balanceOf() external view returns (uint256);
    function harvest() external returns (uint256);
    function want() external view returns (address);
}

// ============ Ownable ============

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

// ============ ReentrancyGuard ============

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

// ============ Pausable ============

abstract contract Pausable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    function paused() public view returns (bool) { return _paused; }

    function _pause() internal {
        _paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

// ============ YieldVault (ERC-4626) ============

contract YieldVault is Ownable, ReentrancyGuard, Pausable {
    // -- ERC20 vault share token --
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // -- Vault state --
    IERC20 public immutable asset;
    IStrategy public strategy;
    uint256 public depositCap;
    uint256 public performanceFeeBps; // basis points (e.g., 1000 = 10%)
    address public feeRecipient;

    // -- Events --
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    event StrategyUpdated(address indexed oldStrategy, address indexed newStrategy);
    event Harvested(uint256 profit, uint256 fee);
    event DepositCapUpdated(uint256 newCap);

    constructor(
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _depositCap,
        uint256 _performanceFeeBps,
        address _feeRecipient
    ) {
        asset = IERC20(_asset);
        name = _name;
        symbol = _symbol;
        decimals = IERC20(_asset).decimals();
        depositCap = _depositCap;
        performanceFeeBps = _performanceFeeBps;
        feeRecipient = _feeRecipient;
    }

    // ---- ERC-4626 Core ----

    /// @notice Total assets managed by the vault (idle + strategy)
    function totalAssets() public view returns (uint256) {
        uint256 idle = asset.balanceOf(address(this));
        uint256 deployed = address(strategy) != address(0) ? strategy.balanceOf() : 0;
        return idle + deployed;
    }

    /// @notice Convert assets to shares
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? assets : (assets * supply) / totalAssets();
    }

    /// @notice Convert shares to assets
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? shares : (shares * totalAssets()) / supply;
    }

    /// @notice Max deposit for a given receiver
    function maxDeposit(address) external view returns (uint256) {
        if (paused()) return 0;
        uint256 total = totalAssets();
        return total >= depositCap ? 0 : depositCap - total;
    }

    /// @notice Preview shares for a deposit
    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    /// @notice Preview assets for a withdrawal
    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    /// @notice Deposit assets and mint shares
    function deposit(uint256 assets, address receiver) external nonReentrant whenNotPaused returns (uint256 shares) {
        require(assets > 0, "Vault: zero deposit");
        require(totalAssets() + assets <= depositCap, "Vault: cap exceeded");

        shares = convertToShares(assets);
        require(shares > 0, "Vault: zero shares");

        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Redeem shares for underlying assets
    function redeem(uint256 shares, address receiver, address shareOwner) external nonReentrant returns (uint256 assets) {
        require(shares > 0, "Vault: zero shares");
        if (msg.sender != shareOwner) {
            uint256 currentAllowance = allowance[shareOwner][msg.sender];
            require(currentAllowance >= shares, "Vault: insufficient allowance");
            allowance[shareOwner][msg.sender] = currentAllowance - shares;
        }

        assets = convertToAssets(shares);
        require(assets > 0, "Vault: zero assets");

        // Pull from strategy if needed
        uint256 idle = asset.balanceOf(address(this));
        if (idle < assets && address(strategy) != address(0)) {
            strategy.withdraw(assets - idle);
        }

        _burn(shareOwner, shares);
        asset.transfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, shareOwner, assets, shares);
    }

    // ---- Strategy Management ----

    /// @notice Set or update strategy
    function setStrategy(address _strategy) external onlyOwner {
        address old = address(strategy);
        // Withdraw all from old strategy
        if (old != address(0)) {
            uint256 bal = strategy.balanceOf();
            if (bal > 0) strategy.withdraw(bal);
        }
        strategy = IStrategy(_strategy);
        emit StrategyUpdated(old, _strategy);
    }

    /// @notice Push idle funds to strategy
    function earn() external onlyOwner {
        require(address(strategy) != address(0), "Vault: no strategy");
        uint256 idle = asset.balanceOf(address(this));
        if (idle > 0) {
            asset.approve(address(strategy), idle);
            strategy.deposit(idle);
        }
    }

    /// @notice Harvest strategy profits
    function harvest() external onlyOwner {
        require(address(strategy) != address(0), "Vault: no strategy");
        uint256 profit = strategy.harvest();
        uint256 fee = 0;
        if (profit > 0 && performanceFeeBps > 0) {
            fee = (profit * performanceFeeBps) / 10000;
            asset.transfer(feeRecipient, fee);
        }
        emit Harvested(profit, fee);
    }

    // ---- Admin ----

    function setDepositCap(uint256 _cap) external onlyOwner {
        depositCap = _cap;
        emit DepositCapUpdated(_cap);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ---- ERC20 Internals ----

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        require(currentAllowance >= amount, "Vault: insufficient allowance");
        allowance[from][msg.sender] = currentAllowance - amount;
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(balanceOf[from] >= amount, "Vault: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        require(balanceOf[from] >= amount, "Vault: insufficient balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}
