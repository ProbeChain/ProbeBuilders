// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ModelExchange
 * @author ProbeChain
 * @notice AI model weights exchange with ratings and custom fine-tune requests on ProbeChain Rydberg Testnet
 * @dev Manages model listings, purchases, ratings, and custom fine-tuning commissions
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

contract ModelExchange is Ownable, ReentrancyGuard, Pausable {
    // ─── Types ───────────────────────────────────────────────────────────
    enum LicenseType { OpenSource, Commercial, Research, Exclusive }
    enum FinetuneStatus { Requested, Accepted, Delivered, Disputed, Completed }

    struct Model {
        uint256 id;
        address creator;
        string name;
        bytes32 weightsHash;
        string baseModel;
        uint256 price;
        LicenseType license;
        uint256 totalSales;
        uint256 totalRatings;
        uint256 ratingSum;
        bool listed;
        uint256 createdAt;
    }

    struct FinetuneRequest {
        uint256 id;
        address requester;
        address provider;
        string spec;
        uint256 budget;
        bytes32 deliveredWeightsHash;
        FinetuneStatus status;
        uint256 createdAt;
    }

    struct Rating {
        address rater;
        uint256 modelId;
        uint8 score; // 1-5
        string review;
        uint256 ratedAt;
    }

    // ─── State ───────────────────────────────────────────────────────────
    uint256 public modelCount;
    uint256 public requestCount;
    uint256 public platformFeeBps = 300; // 3%

    mapping(uint256 => Model) public models;
    mapping(uint256 => FinetuneRequest) public finetuneRequests;
    mapping(uint256 => mapping(address => bool)) public hasPurchased;
    mapping(uint256 => mapping(address => bool)) public hasRated;
    mapping(address => uint256[]) public creatorModels;

    // ─── Events ──────────────────────────────────────────────────────────
    /// @notice Emitted when a model is listed
    event ModelListed(uint256 indexed modelId, address indexed creator, string name, uint256 price, LicenseType license);

    /// @notice Emitted when a model is purchased
    event ModelPurchased(uint256 indexed modelId, address indexed buyer, uint256 price);

    /// @notice Emitted when a model is rated
    event ModelRated(uint256 indexed modelId, address indexed rater, uint8 score);

    /// @notice Emitted when a finetune request is created
    event FinetuneRequested(uint256 indexed requestId, address indexed requester, string spec, uint256 budget);

    /// @notice Emitted when a finetune is delivered
    event FinetuneDelivered(uint256 indexed requestId, address indexed provider, bytes32 weightsHash);

    /// @notice Emitted when a finetune is completed (payment released)
    event FinetuneCompleted(uint256 indexed requestId);

    // ─── Model Management ────────────────────────────────────────────────

    /**
     * @notice List a new AI model for sale
     * @param _name Model name
     * @param _weightsHash Hash of the model weights
     * @param _baseModel Base model identifier (e.g., "llama-3-8b")
     * @param _price Price in wei
     * @param _license License type
     * @return modelId The ID of the listed model
     */
    function listModel(
        string calldata _name,
        bytes32 _weightsHash,
        string calldata _baseModel,
        uint256 _price,
        LicenseType _license
    ) external whenNotPaused returns (uint256 modelId) {
        require(bytes(_name).length > 0 && bytes(_name).length <= 128, "Invalid name");
        require(_weightsHash != bytes32(0), "Empty weights hash");
        require(_price > 0, "Price must be > 0");

        modelId = ++modelCount;
        models[modelId] = Model({
            id: modelId,
            creator: msg.sender,
            name: _name,
            weightsHash: _weightsHash,
            baseModel: _baseModel,
            price: _price,
            license: _license,
            totalSales: 0,
            totalRatings: 0,
            ratingSum: 0,
            listed: true,
            createdAt: block.timestamp
        });

        creatorModels[msg.sender].push(modelId);

        emit ModelListed(modelId, msg.sender, _name, _price, _license);
    }

    /**
     * @notice Purchase a model
     * @param _modelId The model ID
     */
    function purchaseModel(uint256 _modelId)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        Model storage model = models[_modelId];
        require(model.listed, "Model not listed");
        require(msg.value >= model.price, "Insufficient payment");
        require(!hasPurchased[_modelId][msg.sender], "Already purchased");
        require(msg.sender != model.creator, "Cannot buy own model");

        hasPurchased[_modelId][msg.sender] = true;
        model.totalSales++;

        uint256 platformCut = (msg.value * platformFeeBps) / 10000;
        uint256 creatorPayment = msg.value - platformCut;

        (bool sent, ) = model.creator.call{value: creatorPayment}("");
        require(sent, "Payment failed");

        emit ModelPurchased(_modelId, msg.sender, msg.value);
    }

    /**
     * @notice Rate a purchased model
     * @param _modelId The model ID
     * @param _score Rating score (1-5)
     * @param _review Review text
     */
    function rateModel(uint256 _modelId, uint8 _score, string calldata _review) external whenNotPaused {
        require(hasPurchased[_modelId][msg.sender], "Must purchase first");
        require(!hasRated[_modelId][msg.sender], "Already rated");
        require(_score >= 1 && _score <= 5, "Score must be 1-5");

        hasRated[_modelId][msg.sender] = true;
        Model storage model = models[_modelId];
        model.totalRatings++;
        model.ratingSum += _score;

        emit ModelRated(_modelId, msg.sender, _score);
    }

    /**
     * @notice Request a custom fine-tune
     * @param _spec Specification for the fine-tuning job
     * @param _budget Budget in wei (held in escrow)
     * @return requestId The ID of the request
     */
    function requestCustomFinetune(string calldata _spec, uint256 _budget)
        external
        payable
        whenNotPaused
        returns (uint256 requestId)
    {
        require(bytes(_spec).length > 0, "Empty spec");
        require(msg.value >= _budget && _budget > 0, "Insufficient budget");

        requestId = ++requestCount;
        finetuneRequests[requestId] = FinetuneRequest({
            id: requestId,
            requester: msg.sender,
            provider: address(0),
            spec: _spec,
            budget: _budget,
            deliveredWeightsHash: bytes32(0),
            status: FinetuneStatus.Requested,
            createdAt: block.timestamp
        });

        emit FinetuneRequested(requestId, msg.sender, _spec, _budget);
    }

    /**
     * @notice Deliver a completed fine-tune
     * @param _requestId The request ID
     * @param _weightsHash Hash of the delivered weights
     */
    function deliverFinetune(uint256 _requestId, bytes32 _weightsHash) external whenNotPaused {
        FinetuneRequest storage req = finetuneRequests[_requestId];
        require(req.status == FinetuneStatus.Requested || req.status == FinetuneStatus.Accepted, "Invalid status");
        require(_weightsHash != bytes32(0), "Empty weights hash");

        req.provider = msg.sender;
        req.deliveredWeightsHash = _weightsHash;
        req.status = FinetuneStatus.Delivered;

        emit FinetuneDelivered(_requestId, msg.sender, _weightsHash);
    }

    /**
     * @notice Accept delivery and release payment
     * @param _requestId The request ID
     */
    function acceptDelivery(uint256 _requestId) external whenNotPaused nonReentrant {
        FinetuneRequest storage req = finetuneRequests[_requestId];
        require(req.requester == msg.sender, "Not requester");
        require(req.status == FinetuneStatus.Delivered, "Not delivered");

        req.status = FinetuneStatus.Completed;

        uint256 platformCut = (req.budget * platformFeeBps) / 10000;
        uint256 providerPayment = req.budget - platformCut;

        (bool sent, ) = req.provider.call{value: providerPayment}("");
        require(sent, "Payment failed");

        emit FinetuneCompleted(_requestId);
    }

    /**
     * @notice Get average rating for a model (x100 for precision)
     * @param _modelId The model ID
     * @return Average rating multiplied by 100
     */
    function getModelScore(uint256 _modelId) external view returns (uint256) {
        Model storage model = models[_modelId];
        if (model.totalRatings == 0) return 0;
        return (model.ratingSum * 100) / model.totalRatings;
    }

    /**
     * @notice Get all models by a creator
     * @param _creator The creator address
     */
    function getCreatorModels(address _creator) external view returns (uint256[] memory) {
        return creatorModels[_creator];
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
}
