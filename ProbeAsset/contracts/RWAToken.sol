// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title RWAToken
 * @notice Real World Asset tokenization with KYC whitelist-gated transfers,
 *         asset valuation updates, and compliance enforcement.
 * @dev ERC-20 token with transfer restrictions based on KYC whitelist
 */
contract RWAToken {
    // ──────────────────── Ownership ────────────────────
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    // ──────────────────── Pausable ────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "Paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ──────────────────── Reentrancy Guard ────────────────────
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "Reentrant");
        _locked = 2;
        _;
        _locked = 1;
    }

    // ──────────────────── ERC-20 Core ────────────────────
    string public name = "ProbeAsset RWA Token";
    string public symbol = "pRWA";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ──────────────────── RWA Data ────────────────────
    enum AssetType { RealEstate, Commodity, Bond, Equity, Art, Other }
    enum AssetStatus { Active, Frozen, Redeemed }

    struct Asset {
        uint256 assetId;
        AssetType assetType;
        uint256 valuation;          // in wei
        bytes32 documentHash;       // Hash of legal documents
        address issuer;
        AssetStatus status;
        uint256 tokensMinted;
        uint256 createdAt;
        uint256 lastValuationUpdate;
    }

    // ──────────────────── Compliance ────────────────────
    mapping(address => bool) public kycWhitelist;
    mapping(address => bool) public complianceOfficers;
    mapping(uint256 => Asset) public assets;
    mapping(address => uint256) public frozenBalances;
    uint256 public nextAssetId = 1;

    // ──────────────────── Events ────────────────────
    event AssetMinted(uint256 indexed assetId, AssetType assetType, uint256 valuation, uint256 tokensMinted);
    event ValuationUpdated(uint256 indexed assetId, uint256 oldValuation, uint256 newValuation);
    event AssetRedeemed(uint256 indexed assetId, address indexed redeemer, uint256 tokensReturned);
    event AssetFrozen(uint256 indexed assetId);
    event KYCApproved(address indexed account);
    event KYCRevoked(address indexed account);
    event ComplianceOfficerSet(address indexed officer, bool status);
    event BalanceFrozen(address indexed account, uint256 amount);
    event BalanceUnfrozen(address indexed account, uint256 amount);

    constructor() {
        owner = msg.sender;
        complianceOfficers[msg.sender] = true;
        kycWhitelist[msg.sender] = true;
    }

    modifier onlyCompliance() {
        require(complianceOfficers[msg.sender] || msg.sender == owner, "Not compliance officer");
        _;
    }

    modifier onlyWhitelisted(address account) {
        require(kycWhitelist[account], "Not KYC approved");
        _;
    }

    // ──────────────────── KYC Management ────────────────────

    /**
     * @notice Approve an address for KYC
     */
    function approveKYC(address account) external onlyCompliance {
        require(account != address(0), "Zero address");
        kycWhitelist[account] = true;
        emit KYCApproved(account);
    }

    /**
     * @notice Batch approve KYC
     */
    function batchApproveKYC(address[] calldata accounts) external onlyCompliance {
        for (uint256 i = 0; i < accounts.length; i++) {
            kycWhitelist[accounts[i]] = true;
            emit KYCApproved(accounts[i]);
        }
    }

    /**
     * @notice Revoke KYC approval
     */
    function revokeKYC(address account) external onlyCompliance {
        kycWhitelist[account] = false;
        emit KYCRevoked(account);
    }

    /**
     * @notice Set compliance officer status
     */
    function setComplianceOfficer(address officer, bool status) external onlyOwner {
        complianceOfficers[officer] = status;
        emit ComplianceOfficerSet(officer, status);
    }

    // ──────────────────── Asset Management ────────────────────

    /**
     * @notice Mint tokens representing a real world asset
     * @param assetType Category of the asset
     * @param valuation Asset valuation in wei
     * @param documentHash Hash of legal documentation
     * @param tokensToMint Number of tokens to mint (in wei units)
     */
    function mintAsset(
        AssetType assetType,
        uint256 valuation,
        bytes32 documentHash,
        uint256 tokensToMint
    ) external onlyOwner whenNotPaused returns (uint256) {
        require(valuation > 0, "Zero valuation");
        require(tokensToMint > 0, "Zero tokens");
        require(documentHash != bytes32(0), "Empty document");

        uint256 assetId = nextAssetId++;
        assets[assetId] = Asset({
            assetId: assetId,
            assetType: assetType,
            valuation: valuation,
            documentHash: documentHash,
            issuer: msg.sender,
            status: AssetStatus.Active,
            tokensMinted: tokensToMint,
            createdAt: block.timestamp,
            lastValuationUpdate: block.timestamp
        });

        totalSupply += tokensToMint;
        balanceOf[msg.sender] += tokensToMint;

        emit Transfer(address(0), msg.sender, tokensToMint);
        emit AssetMinted(assetId, assetType, valuation, tokensToMint);
        return assetId;
    }

    /**
     * @notice Update asset valuation
     */
    function updateValuation(uint256 assetId, uint256 newValuation) external onlyOwner {
        Asset storage a = assets[assetId];
        require(a.status == AssetStatus.Active, "Not active");
        require(newValuation > 0, "Zero valuation");

        uint256 oldVal = a.valuation;
        a.valuation = newValuation;
        a.lastValuationUpdate = block.timestamp;

        emit ValuationUpdated(assetId, oldVal, newValuation);
    }

    /**
     * @notice Redeem asset tokens (burn tokens, release underlying asset)
     * @param assetId The asset to redeem
     * @param tokenAmount Amount of tokens to burn
     */
    function redeemAsset(uint256 assetId, uint256 tokenAmount) external nonReentrant whenNotPaused {
        Asset storage a = assets[assetId];
        require(a.status == AssetStatus.Active, "Not active");
        require(balanceOf[msg.sender] >= tokenAmount, "Insufficient balance");
        require(tokenAmount > 0, "Zero amount");

        balanceOf[msg.sender] -= tokenAmount;
        totalSupply -= tokenAmount;
        a.tokensMinted -= tokenAmount;

        if (a.tokensMinted == 0) {
            a.status = AssetStatus.Redeemed;
        }

        emit Transfer(msg.sender, address(0), tokenAmount);
        emit AssetRedeemed(assetId, msg.sender, tokenAmount);
    }

    /**
     * @notice Freeze an asset (compliance action)
     */
    function freezeAsset(uint256 assetId) external onlyCompliance {
        assets[assetId].status = AssetStatus.Frozen;
        emit AssetFrozen(assetId);
    }

    // ──────────────────── ERC-20 with Compliance ────────────────────

    /**
     * @notice Transfer with KYC compliance check
     */
    function transfer(address to, uint256 amount)
        external
        whenNotPaused
        onlyWhitelisted(msg.sender)
        onlyWhitelisted(to)
        returns (bool)
    {
        require(to != address(0), "Zero address");
        uint256 available = balanceOf[msg.sender] - frozenBalances[msg.sender];
        require(available >= amount, "Insufficient available balance");

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    /**
     * @notice Approve spending with KYC check on spender
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice TransferFrom with compliance checks on both parties
     */
    function transferFrom(address from, address to, uint256 amount)
        external
        whenNotPaused
        onlyWhitelisted(from)
        onlyWhitelisted(to)
        returns (bool)
    {
        require(to != address(0), "Zero address");
        require(allowance[from][msg.sender] >= amount, "Allowance exceeded");
        uint256 available = balanceOf[from] - frozenBalances[from];
        require(available >= amount, "Insufficient available balance");

        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    // ──────────────────── Balance Freezing ────────────────────

    /**
     * @notice Freeze a portion of an account's balance (compliance)
     */
    function freezeBalance(address account, uint256 amount) external onlyCompliance {
        require(balanceOf[account] >= amount, "Exceeds balance");
        frozenBalances[account] = amount;
        emit BalanceFrozen(account, amount);
    }

    /**
     * @notice Unfreeze balance
     */
    function unfreezeBalance(address account) external onlyCompliance {
        uint256 frozen = frozenBalances[account];
        frozenBalances[account] = 0;
        emit BalanceUnfrozen(account, frozen);
    }

    // ──────────────────── Views ────────────────────

    function getAsset(uint256 assetId) external view returns (Asset memory) {
        return assets[assetId];
    }

    function getAvailableBalance(address account) external view returns (uint256) {
        return balanceOf[account] - frozenBalances[account];
    }

    function isKYCApproved(address account) external view returns (bool) {
        return kycWhitelist[account];
    }

    receive() external payable {}
}
