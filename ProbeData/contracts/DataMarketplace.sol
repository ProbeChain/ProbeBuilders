// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DataMarketplace
 * @author ProbeChain
 * @notice Decentralized data marketplace with provider staking and quality scoring
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London)
 */

// --- Inline Ownable ---
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    error OwnableUnauthorized(address account);
    error OwnableInvalidOwner(address owner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorized(msg.sender);
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(newOwner);
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// --- Inline ReentrancyGuard ---
abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();

    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardReentrantCall();
        _status = 2;
        _;
        _status = 1;
    }
}

// --- Inline Pausable ---
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();

    modifier whenNotPaused() {
        if (_paused) revert ContractPaused();
        _;
    }

    function paused() public view returns (bool) { return _paused; }

    function pause() external onlyOwner {
        if (_paused) revert ContractPaused();
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        if (!_paused) revert ContractNotPaused();
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract DataMarketplace is Ownable, ReentrancyGuard, Pausable {
    // --- Types ---
    enum License { OpenAccess, Commercial, Research, Restricted }

    struct Dataset {
        uint256 id;
        address provider;
        string name;
        string description;
        bytes32 sampleHash;
        uint256 price;
        License license;
        uint256 totalRating;
        uint256 ratingCount;
        uint256 purchaseCount;
        bool active;
    }

    struct Purchase {
        address buyer;
        uint256 datasetId;
        uint256 timestamp;
        bool rated;
    }

    // --- State ---
    uint256 public nextDatasetId;
    uint256 public constant MIN_STAKE = 0.1 ether;
    uint256 public constant PLATFORM_FEE_BPS = 250; // 2.5%

    mapping(uint256 => Dataset) public datasets;
    mapping(address => uint256) public providerStakes;
    mapping(address => uint256) public providerDatasetCount;
    mapping(uint256 => mapping(address => bytes32)) private _downloadKeys;
    mapping(uint256 => mapping(address => bool)) public hasPurchased;
    mapping(address => mapping(uint256 => Purchase)) public purchases;
    uint256 public totalPlatformFees;

    // --- Events ---
    event DatasetListed(uint256 indexed datasetId, address indexed provider, string name, uint256 price, License license);
    event DatasetPurchased(uint256 indexed datasetId, address indexed buyer, uint256 price);
    event DatasetRated(uint256 indexed datasetId, address indexed rater, uint8 rating);
    event DownloadKeySet(uint256 indexed datasetId, address indexed buyer);
    event ProviderStaked(address indexed provider, uint256 amount);
    event ProviderUnstaked(address indexed provider, uint256 amount);
    event DatasetDeactivated(uint256 indexed datasetId);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // --- Errors ---
    error InsufficientStake();
    error DatasetNotFound();
    error DatasetNotActive();
    error InsufficientPayment();
    error AlreadyPurchased();
    error NotPurchased();
    error AlreadyRated();
    error InvalidRating();
    error NotProvider();
    error NoKeyAvailable();
    error NothingToWithdraw();

    // --- Provider Staking ---

    /// @notice Stake tokens to become a data provider
    function stakeAsProvider() external payable whenNotPaused {
        if (msg.value < MIN_STAKE) revert InsufficientStake();
        providerStakes[msg.sender] += msg.value;
        emit ProviderStaked(msg.sender, msg.value);
    }

    /// @notice Unstake tokens (only if no active datasets)
    function unstake(uint256 amount) external nonReentrant {
        if (providerStakes[msg.sender] < amount) revert InsufficientStake();
        if (providerDatasetCount[msg.sender] > 0) revert NotProvider();
        providerStakes[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit ProviderUnstaked(msg.sender, amount);
    }

    // --- Dataset Management ---

    /// @notice List a new dataset on the marketplace
    /// @param name Human-readable dataset name
    /// @param description Description of the dataset contents
    /// @param sampleHash IPFS/content hash of sample data
    /// @param price Price in wei to purchase access
    /// @param license License type for the dataset
    /// @return datasetId The ID of the newly listed dataset
    function listDataset(
        string calldata name,
        string calldata description,
        bytes32 sampleHash,
        uint256 price,
        License license
    ) external whenNotPaused returns (uint256 datasetId) {
        if (providerStakes[msg.sender] < MIN_STAKE) revert InsufficientStake();

        datasetId = nextDatasetId++;
        datasets[datasetId] = Dataset({
            id: datasetId,
            provider: msg.sender,
            name: name,
            description: description,
            sampleHash: sampleHash,
            price: price,
            license: license,
            totalRating: 0,
            ratingCount: 0,
            purchaseCount: 0,
            active: true
        });

        providerDatasetCount[msg.sender]++;
        emit DatasetListed(datasetId, msg.sender, name, price, license);
    }

    /// @notice Purchase access to a dataset
    /// @param datasetId The dataset to purchase
    function purchaseDataset(uint256 datasetId) external payable nonReentrant whenNotPaused {
        Dataset storage ds = datasets[datasetId];
        if (ds.provider == address(0)) revert DatasetNotFound();
        if (!ds.active) revert DatasetNotActive();
        if (msg.value < ds.price) revert InsufficientPayment();
        if (hasPurchased[datasetId][msg.sender]) revert AlreadyPurchased();

        hasPurchased[datasetId][msg.sender] = true;
        ds.purchaseCount++;

        uint256 fee = (msg.value * PLATFORM_FEE_BPS) / 10000;
        totalPlatformFees += fee;
        uint256 providerPayment = msg.value - fee;

        payable(ds.provider).transfer(providerPayment);

        purchases[msg.sender][datasetId] = Purchase({
            buyer: msg.sender,
            datasetId: datasetId,
            timestamp: block.timestamp,
            rated: false
        });

        emit DatasetPurchased(datasetId, msg.sender, msg.value);
    }

    /// @notice Rate a purchased dataset (1-5 stars)
    /// @param datasetId The dataset to rate
    /// @param rating Rating from 1 to 5
    function rateDataset(uint256 datasetId, uint8 rating) external whenNotPaused {
        if (!hasPurchased[datasetId][msg.sender]) revert NotPurchased();
        if (purchases[msg.sender][datasetId].rated) revert AlreadyRated();
        if (rating < 1 || rating > 5) revert InvalidRating();

        Dataset storage ds = datasets[datasetId];
        ds.totalRating += rating;
        ds.ratingCount++;
        purchases[msg.sender][datasetId].rated = true;

        emit DatasetRated(datasetId, msg.sender, rating);
    }

    /// @notice Provider sets encrypted download key for a buyer
    /// @param datasetId The dataset ID
    /// @param buyer The buyer address
    /// @param encryptedKey The encrypted download key
    function setDownloadKey(uint256 datasetId, address buyer, bytes32 encryptedKey) external {
        Dataset storage ds = datasets[datasetId];
        if (ds.provider != msg.sender) revert NotProvider();
        if (!hasPurchased[datasetId][buyer]) revert NotPurchased();

        _downloadKeys[datasetId][buyer] = encryptedKey;
        emit DownloadKeySet(datasetId, buyer);
    }

    /// @notice Retrieve encrypted download key for a purchased dataset
    /// @param datasetId The dataset to get the key for
    /// @return The encrypted download key
    function downloadKey(uint256 datasetId) external view returns (bytes32) {
        if (!hasPurchased[datasetId][msg.sender]) revert NotPurchased();
        bytes32 key = _downloadKeys[datasetId][msg.sender];
        if (key == bytes32(0)) revert NoKeyAvailable();
        return key;
    }

    /// @notice Get the average rating for a dataset (scaled by 100)
    /// @param datasetId The dataset ID
    /// @return Average rating * 100
    function getAverageRating(uint256 datasetId) external view returns (uint256) {
        Dataset storage ds = datasets[datasetId];
        if (ds.ratingCount == 0) return 0;
        return (ds.totalRating * 100) / ds.ratingCount;
    }

    /// @notice Deactivate a dataset listing
    /// @param datasetId The dataset to deactivate
    function deactivateDataset(uint256 datasetId) external {
        Dataset storage ds = datasets[datasetId];
        if (ds.provider != msg.sender) revert NotProvider();
        ds.active = false;
        providerDatasetCount[msg.sender]--;
        emit DatasetDeactivated(datasetId);
    }

    /// @notice Withdraw accumulated platform fees
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = totalPlatformFees;
        if (amount == 0) revert NothingToWithdraw();
        totalPlatformFees = 0;
        payable(owner()).transfer(amount);
        emit FeesWithdrawn(owner(), amount);
    }
}
