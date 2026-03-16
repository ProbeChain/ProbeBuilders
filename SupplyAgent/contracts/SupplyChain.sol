// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title SupplyChain
 * @author ProbeBuilders
 * @notice Supply chain tracking with immutable provenance for ProbeChain Rydberg Testnet.
 *         Track products from origin through checkpoints with custody transfers.
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

contract SupplyChain is Ownable, ReentrancyGuard, Pausable {

    /* ── Enums ── */

    /// @notice Product status at a checkpoint
    enum Status {
        Created,
        InTransit,
        AtWarehouse,
        QualityCheck,
        Delivered,
        Recalled
    }

    /* ── Structs ── */

    /// @notice A tracked product
    struct Product {
        uint256 id;
        string  sku;
        string  origin;
        string  metadata;      // IPFS hash or JSON
        address creator;
        address currentCustodian;
        Status  currentStatus;
        uint256 createdAt;
        uint256 updatedAt;
        bool    active;
    }

    /// @notice A checkpoint in the supply chain
    struct Checkpoint {
        string  location;
        Status  status;
        address verifier;
        string  notes;
        uint256 timestamp;
    }

    /// @notice A custody transfer record
    struct CustodyTransfer {
        address from;
        address to;
        uint256 timestamp;
    }

    /* ── State ── */

    uint256 public nextProductId;
    mapping(uint256 => Product) public products;
    mapping(uint256 => Checkpoint[]) private _checkpoints;
    mapping(uint256 => CustodyTransfer[]) private _transfers;
    mapping(string => uint256) public skuToProductId;
    mapping(address => bool) public authorizedVerifiers;
    mapping(address => uint256[]) private _custodianProducts;

    /* ── Events ── */

    /// @notice Emitted when a product is created
    event ProductCreated(uint256 indexed productId, string sku, string origin, address indexed creator);
    /// @notice Emitted when a checkpoint is added
    event CheckpointAdded(uint256 indexed productId, string location, Status status, address indexed verifier);
    /// @notice Emitted when custody is transferred
    event CustodyTransferred(uint256 indexed productId, address indexed from, address indexed to);
    /// @notice Emitted when a product is recalled
    event ProductRecalled(uint256 indexed productId, address indexed recalledBy);
    /// @notice Emitted when verifier status changes
    event VerifierUpdated(address indexed verifier, bool status);

    /* ── Errors ── */

    error NotCustodian();
    error NotVerifier();
    error ProductNotActive();
    error SKUAlreadyExists();
    error InvalidProduct();

    /* ── Modifiers ── */

    modifier onlyCustodian(uint256 productId) {
        if (products[productId].currentCustodian != msg.sender && msg.sender != owner()) revert NotCustodian();
        _;
    }

    modifier onlyVerifier() {
        if (!authorizedVerifiers[msg.sender] && msg.sender != owner()) revert NotVerifier();
        _;
    }

    modifier productActive(uint256 productId) {
        if (!products[productId].active) revert ProductNotActive();
        _;
    }

    /* ── Constructor ── */

    constructor() Ownable() {
        authorizedVerifiers[msg.sender] = true;
    }

    /* ── Admin ── */

    /// @notice Add or remove an authorized verifier
    function setVerifier(address verifier, bool status) external onlyOwner {
        authorizedVerifiers[verifier] = status;
        emit VerifierUpdated(verifier, status);
    }

    /* ── Core functions ── */

    /**
     * @notice Create a new product to track
     * @param sku Stock keeping unit (unique)
     * @param origin Origin location/country
     * @param metadata IPFS hash or JSON metadata
     * @return productId The created product ID
     */
    function createProduct(
        string calldata sku,
        string calldata origin,
        string calldata metadata
    ) external whenNotPaused returns (uint256 productId) {
        require(bytes(sku).length > 0, "empty sku");
        require(bytes(origin).length > 0, "empty origin");
        if (skuToProductId[sku] != 0) revert SKUAlreadyExists();

        productId = ++nextProductId; // start from 1 so 0 means "not found"
        products[productId] = Product({
            id: productId,
            sku: sku,
            origin: origin,
            metadata: metadata,
            creator: msg.sender,
            currentCustodian: msg.sender,
            currentStatus: Status.Created,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            active: true
        });

        skuToProductId[sku] = productId;
        _custodianProducts[msg.sender].push(productId);

        _checkpoints[productId].push(Checkpoint({
            location: origin,
            status: Status.Created,
            verifier: msg.sender,
            notes: "Product created",
            timestamp: block.timestamp
        }));

        emit ProductCreated(productId, sku, origin, msg.sender);
    }

    /**
     * @notice Add a checkpoint to the product journey
     * @param productId The product
     * @param location Current location
     * @param status New status
     * @param notes Additional notes
     */
    function addCheckpoint(
        uint256 productId,
        string calldata location,
        Status status,
        string calldata notes
    ) external onlyVerifier productActive(productId) whenNotPaused {
        require(bytes(location).length > 0, "empty location");

        Product storage prod = products[productId];
        prod.currentStatus = status;
        prod.updatedAt = block.timestamp;

        _checkpoints[productId].push(Checkpoint({
            location: location,
            status: status,
            verifier: msg.sender,
            notes: notes,
            timestamp: block.timestamp
        }));

        emit CheckpointAdded(productId, location, status, msg.sender);
    }

    /**
     * @notice Transfer custody of a product to a new custodian
     * @param productId The product
     * @param newCustodian The new custodian address
     */
    function transferCustody(
        uint256 productId,
        address newCustodian
    ) external onlyCustodian(productId) productActive(productId) whenNotPaused {
        require(newCustodian != address(0), "zero custodian");

        Product storage prod = products[productId];
        address prev = prod.currentCustodian;
        prod.currentCustodian = newCustodian;
        prod.updatedAt = block.timestamp;

        _transfers[productId].push(CustodyTransfer({
            from: prev,
            to: newCustodian,
            timestamp: block.timestamp
        }));

        _custodianProducts[newCustodian].push(productId);

        emit CustodyTransferred(productId, prev, newCustodian);
    }

    /**
     * @notice Recall a product (mark as recalled, still tracked)
     * @param productId The product to recall
     */
    function recallProduct(uint256 productId) external onlyOwner productActive(productId) {
        Product storage prod = products[productId];
        prod.currentStatus = Status.Recalled;
        prod.updatedAt = block.timestamp;
        prod.active = false;

        _checkpoints[productId].push(Checkpoint({
            location: "",
            status: Status.Recalled,
            verifier: msg.sender,
            notes: "Product recalled",
            timestamp: block.timestamp
        }));

        emit ProductRecalled(productId, msg.sender);
    }

    /* ── View helpers ── */

    /// @notice Get full checkpoint history for a product
    function getHistory(uint256 productId) external view returns (Checkpoint[] memory) {
        return _checkpoints[productId];
    }

    /// @notice Get custody transfer history
    function getCustodyHistory(uint256 productId) external view returns (CustodyTransfer[] memory) {
        return _transfers[productId];
    }

    /// @notice Get products currently held by a custodian
    function getCustodianProducts(address custodian) external view returns (uint256[] memory) {
        return _custodianProducts[custodian];
    }

    /// @notice Look up product by SKU
    function getProductBySKU(string calldata sku) external view returns (Product memory) {
        uint256 pid = skuToProductId[sku];
        if (pid == 0) revert InvalidProduct();
        return products[pid];
    }

    /// @notice Get checkpoint count for a product
    function getCheckpointCount(uint256 productId) external view returns (uint256) {
        return _checkpoints[productId].length;
    }
}
