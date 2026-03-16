// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title LicenseManager
 * @author ProbeChain
 * @notice Software license management with issuance, verification, and renewal on ProbeChain Rydberg Testnet
 * @dev Supports Perpetual, Subscription, and Trial license types with on-chain verification
 */

/// @dev Minimal Ownable implementation
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/// @dev Minimal ReentrancyGuard implementation
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/// @dev Minimal Pausable implementation
abstract contract Pausable is Ownable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    function pause() public onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract LicenseManager is Ownable, ReentrancyGuard, Pausable {
    // ─── Types ───────────────────────────────────────────────────────────
    enum LicenseType { Perpetual, Subscription, Trial }
    enum LicenseStatus { Active, Expired, Revoked }

    struct Product {
        uint256 id;
        address vendor;
        string name;
        string description;
        uint256 totalLicenses;
        uint256 activeLicenses;
        bool active;
        uint256 createdAt;
    }

    struct License {
        uint256 id;
        uint256 productId;
        address licensee;
        LicenseType licenseType;
        LicenseStatus status;
        uint256 price;
        uint256 issuedAt;
        uint256 expiresAt;
        uint256 renewalCount;
    }

    // ─── State ───────────────────────────────────────────────────────────
    uint256 public productCount;
    uint256 public licenseCount;
    uint256 public platformFeeBps = 200; // 2%

    mapping(uint256 => Product) public products;
    mapping(uint256 => License) public licenses;
    mapping(uint256 => uint256[]) public productLicenses;
    mapping(address => uint256[]) public userLicenses;
    mapping(uint256 => mapping(address => uint256)) public userProductLicense;

    // ─── Events ──────────────────────────────────────────────────────────
    /// @notice Emitted when a new product is created
    event ProductCreated(uint256 indexed productId, address indexed vendor, string name);

    /// @notice Emitted when a license is issued
    event LicenseIssued(uint256 indexed licenseId, uint256 indexed productId, address indexed licensee, LicenseType licenseType, uint256 expiresAt);

    /// @notice Emitted when a license is verified
    event LicenseVerified(uint256 indexed licenseId, bool valid);

    /// @notice Emitted when a license is revoked
    event LicenseRevoked(uint256 indexed licenseId, address indexed revokedBy);

    /// @notice Emitted when a license is renewed
    event LicenseRenewed(uint256 indexed licenseId, uint256 newExpiresAt, uint256 renewalCount);

    /// @notice Emitted when a product is deactivated
    event ProductDeactivated(uint256 indexed productId);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyVendor(uint256 _productId) {
        require(products[_productId].vendor == msg.sender, "Not product vendor");
        _;
    }

    // ─── Product Management ──────────────────────────────────────────────

    /**
     * @notice Create a new software product
     * @param _name Product name
     * @param _description Product description
     * @return productId The ID of the created product
     */
    function createProduct(string calldata _name, string calldata _description)
        external
        whenNotPaused
        returns (uint256 productId)
    {
        require(bytes(_name).length > 0 && bytes(_name).length <= 128, "Invalid name");
        require(bytes(_description).length > 0, "Empty description");

        productId = ++productCount;
        products[productId] = Product({
            id: productId,
            vendor: msg.sender,
            name: _name,
            description: _description,
            totalLicenses: 0,
            activeLicenses: 0,
            active: true,
            createdAt: block.timestamp
        });

        emit ProductCreated(productId, msg.sender, _name);
    }

    /**
     * @notice Issue a license for a product
     * @param _productId The product ID
     * @param _licensee The licensee address
     * @param _licenseType Type of license (Perpetual, Subscription, Trial)
     * @param _duration Duration in seconds (0 for Perpetual)
     * @param _price License price in wei
     * @return licenseId The ID of the issued license
     */
    function issueLicense(
        uint256 _productId,
        address _licensee,
        LicenseType _licenseType,
        uint256 _duration,
        uint256 _price
    )
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 licenseId)
    {
        Product storage product = products[_productId];
        require(product.active, "Product not active");
        require(_licensee != address(0), "Invalid licensee");

        // Vendor can issue free licenses; buyers must pay
        if (msg.sender != product.vendor) {
            require(msg.value >= _price, "Insufficient payment");
        }

        uint256 expiresAt;
        if (_licenseType == LicenseType.Perpetual) {
            expiresAt = type(uint256).max; // never expires
        } else if (_licenseType == LicenseType.Trial) {
            require(_duration > 0 && _duration <= 30 days, "Trial max 30 days");
            expiresAt = block.timestamp + _duration;
        } else {
            require(_duration > 0, "Duration required for subscription");
            expiresAt = block.timestamp + _duration;
        }

        licenseId = ++licenseCount;
        licenses[licenseId] = License({
            id: licenseId,
            productId: _productId,
            licensee: _licensee,
            licenseType: _licenseType,
            status: LicenseStatus.Active,
            price: _price,
            issuedAt: block.timestamp,
            expiresAt: expiresAt,
            renewalCount: 0
        });

        product.totalLicenses++;
        product.activeLicenses++;
        productLicenses[_productId].push(licenseId);
        userLicenses[_licensee].push(licenseId);
        userProductLicense[_productId][_licensee] = licenseId;

        // Pay vendor (minus platform fee)
        if (msg.value > 0) {
            uint256 platformCut = (msg.value * platformFeeBps) / 10000;
            uint256 vendorPayment = msg.value - platformCut;
            (bool sent, ) = product.vendor.call{value: vendorPayment}("");
            require(sent, "Vendor payment failed");
        }

        emit LicenseIssued(licenseId, _productId, _licensee, _licenseType, expiresAt);
    }

    /**
     * @notice Verify if a license is currently valid
     * @param _licenseId The license ID
     * @return valid Whether the license is valid
     */
    function verifyLicense(uint256 _licenseId) external returns (bool valid) {
        License storage lic = licenses[_licenseId];
        require(lic.id != 0, "License not found");

        // Auto-expire if past expiration
        if (lic.status == LicenseStatus.Active && block.timestamp > lic.expiresAt) {
            lic.status = LicenseStatus.Expired;
            products[lic.productId].activeLicenses--;
        }

        valid = lic.status == LicenseStatus.Active;
        emit LicenseVerified(_licenseId, valid);
    }

    /**
     * @notice Check license validity (view only, does not auto-expire)
     * @param _licenseId The license ID
     * @return valid Whether the license appears valid
     */
    function isLicenseValid(uint256 _licenseId) external view returns (bool valid) {
        License storage lic = licenses[_licenseId];
        return lic.status == LicenseStatus.Active && block.timestamp <= lic.expiresAt;
    }

    /**
     * @notice Revoke a license (vendor only)
     * @param _licenseId The license ID
     */
    function revokeLicense(uint256 _licenseId) external whenNotPaused {
        License storage lic = licenses[_licenseId];
        require(products[lic.productId].vendor == msg.sender, "Not vendor");
        require(lic.status == LicenseStatus.Active, "License not active");

        lic.status = LicenseStatus.Revoked;
        products[lic.productId].activeLicenses--;

        emit LicenseRevoked(_licenseId, msg.sender);
    }

    /**
     * @notice Renew a subscription license
     * @param _licenseId The license ID
     * @param _duration Additional duration in seconds
     * @return newExpiresAt The new expiration timestamp
     */
    function renewLicense(uint256 _licenseId, uint256 _duration)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 newExpiresAt)
    {
        License storage lic = licenses[_licenseId];
        require(lic.licensee == msg.sender || products[lic.productId].vendor == msg.sender, "Not authorized");
        require(lic.licenseType == LicenseType.Subscription, "Only subscription renewable");
        require(lic.status != LicenseStatus.Revoked, "License revoked");
        require(_duration > 0, "Duration must be > 0");

        // If expired, restart from now; if active, extend from current expiry
        if (block.timestamp > lic.expiresAt) {
            lic.expiresAt = block.timestamp + _duration;
            if (lic.status == LicenseStatus.Expired) {
                lic.status = LicenseStatus.Active;
                products[lic.productId].activeLicenses++;
            }
        } else {
            lic.expiresAt += _duration;
        }

        lic.renewalCount++;
        newExpiresAt = lic.expiresAt;

        // Pay vendor for renewal
        if (msg.value > 0) {
            Product storage product = products[lic.productId];
            uint256 platformCut = (msg.value * platformFeeBps) / 10000;
            uint256 vendorPayment = msg.value - platformCut;
            (bool sent, ) = product.vendor.call{value: vendorPayment}("");
            require(sent, "Vendor payment failed");
        }

        emit LicenseRenewed(_licenseId, newExpiresAt, lic.renewalCount);
    }

    /**
     * @notice Deactivate a product (vendor only)
     * @param _productId The product ID
     */
    function deactivateProduct(uint256 _productId) external onlyVendor(_productId) {
        products[_productId].active = false;
        emit ProductDeactivated(_productId);
    }

    /**
     * @notice Get all license IDs for a product
     * @param _productId The product ID
     */
    function getProductLicenses(uint256 _productId) external view returns (uint256[] memory) {
        return productLicenses[_productId];
    }

    /**
     * @notice Get all license IDs for a user
     * @param _user The user address
     */
    function getUserLicenses(address _user) external view returns (uint256[] memory) {
        return userLicenses[_user];
    }

    /**
     * @notice Update platform fee
     * @param _newFeeBps New fee in basis points
     */
    function setPlatformFee(uint256 _newFeeBps) external onlyOwner {
        require(_newFeeBps <= 1000, "Fee too high");
        platformFeeBps = _newFeeBps;
    }

    /**
     * @notice Withdraw platform fees
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees");
        (bool sent, ) = owner().call{value: balance}("");
        require(sent, "Withdraw failed");
    }

    /**
     * @notice Get product details
     * @param _productId The product ID
     */
    function getProduct(uint256 _productId) external view returns (Product memory) {
        return products[_productId];
    }

    /**
     * @notice Get license details
     * @param _licenseId The license ID
     */
    function getLicense(uint256 _licenseId) external view returns (License memory) {
        return licenses[_licenseId];
    }
}
