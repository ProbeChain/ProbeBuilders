// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CreatorStudio
 * @author ProbeChain
 * @notice Creator workspace with collaboration and revenue splitting on ProbeChain Rydberg Testnet
 * @dev Manages projects, collaborators, published works, purchases, and automatic revenue distribution
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

contract CreatorStudio is Ownable, ReentrancyGuard, Pausable {
    // ─── Types ───────────────────────────────────────────────────────────
    enum ProjectType { Art, Music, Writing, Code, Video, Mixed }

    struct Collaborator {
        address wallet;
        uint256 revenueShareBps; // basis points (100 = 1%)
        bool active;
    }

    struct Project {
        uint256 id;
        address creator;
        string name;
        ProjectType projectType;
        uint256 totalShareBps;
        uint256 collaboratorCount;
        bool active;
        uint256 createdAt;
    }

    struct Work {
        uint256 id;
        uint256 projectId;
        bytes32 contentHash;
        uint256 price;
        uint256 totalRevenue;
        uint256 purchaseCount;
        bool published;
        uint256 publishedAt;
    }

    // ─── State ───────────────────────────────────────────────────────────
    uint256 public projectCount;
    uint256 public workCount;
    uint256 public platformFeeBps = 250; // 2.5%

    mapping(uint256 => Project) public projects;
    mapping(uint256 => mapping(uint256 => Collaborator)) public collaborators;
    mapping(uint256 => Work) public works;
    mapping(uint256 => mapping(address => bool)) public hasPurchased;

    // ─── Events ──────────────────────────────────────────────────────────
    /// @notice Emitted when a new project is created
    event ProjectCreated(uint256 indexed projectId, address indexed creator, string name, ProjectType projectType);

    /// @notice Emitted when a collaborator is added to a project
    event CollaboratorAdded(uint256 indexed projectId, address indexed collaborator, uint256 revenueShareBps);

    /// @notice Emitted when a work is published
    event WorkPublished(uint256 indexed workId, uint256 indexed projectId, bytes32 contentHash, uint256 price);

    /// @notice Emitted when a work is purchased
    event WorkPurchased(uint256 indexed workId, address indexed buyer, uint256 price);

    /// @notice Emitted when revenue is distributed to collaborators
    event RevenueDistributed(uint256 indexed workId, address indexed recipient, uint256 amount);

    /// @notice Emitted when the platform fee is updated
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);

    // ─── Modifiers ───────────────────────────────────────────────────────
    modifier onlyProjectCreator(uint256 _projectId) {
        require(projects[_projectId].creator == msg.sender, "Not project creator");
        _;
    }

    // ─── Project Management ──────────────────────────────────────────────

    /**
     * @notice Create a new collaborative project
     * @param _name The project name
     * @param _projectType The type of creative project
     * @return projectId The ID of the newly created project
     */
    function createProject(string calldata _name, ProjectType _projectType)
        external
        whenNotPaused
        returns (uint256 projectId)
    {
        require(bytes(_name).length > 0 && bytes(_name).length <= 128, "Invalid name length");

        projectId = ++projectCount;
        projects[projectId] = Project({
            id: projectId,
            creator: msg.sender,
            name: _name,
            projectType: _projectType,
            totalShareBps: 10000, // creator starts with 100%
            collaboratorCount: 0,
            active: true,
            createdAt: block.timestamp
        });

        // Creator is collaborator index 0
        collaborators[projectId][0] = Collaborator({
            wallet: msg.sender,
            revenueShareBps: 10000,
            active: true
        });

        emit ProjectCreated(projectId, msg.sender, _name, _projectType);
    }

    /**
     * @notice Add a collaborator to a project with a revenue share
     * @param _projectId The project ID
     * @param _collaborator The collaborator address
     * @param _revenueShareBps Revenue share in basis points taken from creator's share
     */
    function addCollaborator(uint256 _projectId, address _collaborator, uint256 _revenueShareBps)
        external
        whenNotPaused
        onlyProjectCreator(_projectId)
    {
        require(_collaborator != address(0), "Invalid collaborator");
        require(_revenueShareBps > 0 && _revenueShareBps <= 5000, "Invalid share (1-5000 bps)");
        require(projects[_projectId].active, "Project not active");

        Project storage project = projects[_projectId];

        // Deduct from creator's share (index 0)
        Collaborator storage creator = collaborators[_projectId][0];
        require(creator.revenueShareBps >= _revenueShareBps, "Exceeds creator share");
        creator.revenueShareBps -= _revenueShareBps;

        uint256 collabIndex = ++project.collaboratorCount;
        collaborators[_projectId][collabIndex] = Collaborator({
            wallet: _collaborator,
            revenueShareBps: _revenueShareBps,
            active: true
        });

        emit CollaboratorAdded(_projectId, _collaborator, _revenueShareBps);
    }

    /**
     * @notice Publish a work from a project
     * @param _projectId The project ID
     * @param _contentHash The IPFS/content hash of the work
     * @param _price The sale price in wei
     * @return workId The ID of the published work
     */
    function publishWork(uint256 _projectId, bytes32 _contentHash, uint256 _price)
        external
        whenNotPaused
        onlyProjectCreator(_projectId)
        returns (uint256 workId)
    {
        require(projects[_projectId].active, "Project not active");
        require(_contentHash != bytes32(0), "Empty content hash");
        require(_price > 0, "Price must be > 0");

        workId = ++workCount;
        works[workId] = Work({
            id: workId,
            projectId: _projectId,
            contentHash: _contentHash,
            price: _price,
            totalRevenue: 0,
            purchaseCount: 0,
            published: true,
            publishedAt: block.timestamp
        });

        emit WorkPublished(workId, _projectId, _contentHash, _price);
    }

    /**
     * @notice Purchase a published work
     * @param _workId The work ID
     */
    function purchaseWork(uint256 _workId)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        Work storage work = works[_workId];
        require(work.published, "Work not published");
        require(msg.value == work.price, "Incorrect payment");
        require(!hasPurchased[_workId][msg.sender], "Already purchased");

        hasPurchased[_workId][msg.sender] = true;
        work.totalRevenue += msg.value;
        work.purchaseCount++;

        emit WorkPurchased(_workId, msg.sender, msg.value);
    }

    /**
     * @notice Distribute accumulated revenue for a work among collaborators
     * @param _workId The work ID
     */
    function distributeRevenue(uint256 _workId)
        external
        whenNotPaused
        nonReentrant
    {
        Work storage work = works[_workId];
        require(work.published, "Work not published");
        uint256 revenue = work.totalRevenue;
        require(revenue > 0, "No revenue to distribute");

        work.totalRevenue = 0;

        uint256 platformCut = (revenue * platformFeeBps) / 10000;
        uint256 distributable = revenue - platformCut;

        Project storage project = projects[work.projectId];

        // Distribute to all collaborators including creator (index 0)
        for (uint256 i = 0; i <= project.collaboratorCount; i++) {
            Collaborator storage collab = collaborators[work.projectId][i];
            if (collab.active && collab.revenueShareBps > 0) {
                uint256 share = (distributable * collab.revenueShareBps) / 10000;
                if (share > 0) {
                    (bool sent, ) = collab.wallet.call{value: share}("");
                    require(sent, "Transfer failed");
                    emit RevenueDistributed(_workId, collab.wallet, share);
                }
            }
        }

        // Platform fee to owner
        if (platformCut > 0) {
            (bool sent, ) = owner().call{value: platformCut}("");
            require(sent, "Platform fee transfer failed");
        }
    }

    /**
     * @notice Update the platform fee
     * @param _newFeeBps New fee in basis points
     */
    function setPlatformFee(uint256 _newFeeBps) external onlyOwner {
        require(_newFeeBps <= 1000, "Fee too high (max 10%)");
        emit PlatformFeeUpdated(platformFeeBps, _newFeeBps);
        platformFeeBps = _newFeeBps;
    }

    /**
     * @notice Get project details
     * @param _projectId The project ID
     */
    function getProject(uint256 _projectId) external view returns (Project memory) {
        return projects[_projectId];
    }

    /**
     * @notice Get work details
     * @param _workId The work ID
     */
    function getWork(uint256 _workId) external view returns (Work memory) {
        return works[_workId];
    }
}
