// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title TemplateRegistry
 * @notice Contract template registry with factory-pattern deployment, versioning, and ratings.
 *         Users register reusable contract templates; anyone can deploy instances via the factory.
 * @dev Templates store bytecode hashes and ABI hashes; actual bytecode is submitted at deploy time.
 */
contract TemplateRegistry {
    // ──────────────────── Ownership ────────────────────
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
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

    // ──────────────────── Data Structures ────────────────────
    enum Category { Token, NFT, DeFi, GameFi, DAO, Utility, Other }

    struct Template {
        uint256 templateId;
        string name;
        string description;
        bytes32 bytecodeHash;    // keccak256 of creation bytecode
        bytes32 abiHash;         // keccak256 of ABI JSON
        Category category;
        address author;
        uint256 currentVersion;
        uint256 deployCount;
        uint256 totalRating;     // sum of all ratings
        uint256 ratingCount;     // number of ratings
        uint256 deployFee;       // fee in wei to deploy from template
        bool active;
        uint256 createdAt;
    }

    struct TemplateVersion {
        uint256 version;
        bytes32 bytecodeHash;
        bytes32 abiHash;
        string changelog;
        uint256 timestamp;
    }

    struct Deployment {
        uint256 deploymentId;
        uint256 templateId;
        address deployer;
        address deployedContract;
        uint256 templateVersion;
        uint256 timestamp;
    }

    // ──────────────────── State ────────────────────
    uint256 public nextTemplateId = 1;
    uint256 public nextDeploymentId = 1;
    uint256 public platformFeeBPS = 300; // 3%
    uint256 public registrationFee = 0.01 ether;

    mapping(uint256 => Template) public templates;
    mapping(uint256 => mapping(uint256 => TemplateVersion)) public templateVersions;
    mapping(uint256 => Deployment) public deployments;
    mapping(address => uint256[]) public authorTemplates;
    mapping(address => uint256[]) public userDeployments;
    mapping(uint256 => mapping(address => bool)) public hasRated;
    mapping(address => uint256) public pendingWithdrawals;

    // Category index
    mapping(Category => uint256[]) public categoryTemplates;

    // ──────────────────── Events ────────────────────
    event TemplateRegistered(uint256 indexed templateId, string name, address indexed author, Category category);
    event TemplateVersionAdded(uint256 indexed templateId, uint256 version, bytes32 bytecodeHash);
    event TemplateDeactivated(uint256 indexed templateId);
    event ContractDeployed(uint256 indexed deploymentId, uint256 indexed templateId, address indexed deployer, address deployedContract);
    event TemplateRated(uint256 indexed templateId, address indexed rater, uint8 rating);
    event DeployFeeUpdated(uint256 indexed templateId, uint256 newFee);
    event WithdrawalClaimed(address indexed addr, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    // ──────────────────── Template Registration ────────────────────

    /**
     * @notice Register a new contract template
     * @param _name Template name
     * @param _description Brief description
     * @param bytecodeHash keccak256 hash of the creation bytecode
     * @param abiHash keccak256 hash of the ABI JSON
     * @param category Template category
     * @param deployFee Fee users pay to deploy from this template
     */
    function registerTemplate(
        string calldata _name,
        string calldata _description,
        bytes32 bytecodeHash,
        bytes32 abiHash,
        Category category,
        uint256 deployFee
    ) external payable whenNotPaused returns (uint256) {
        require(msg.value >= registrationFee, "Insufficient registration fee");
        require(bytes(_name).length > 0 && bytes(_name).length <= 64, "Invalid name");
        require(bytecodeHash != bytes32(0), "Empty bytecode hash");
        require(abiHash != bytes32(0), "Empty ABI hash");

        uint256 templateId = nextTemplateId++;
        templates[templateId] = Template({
            templateId: templateId,
            name: _name,
            description: _description,
            bytecodeHash: bytecodeHash,
            abiHash: abiHash,
            category: category,
            author: msg.sender,
            currentVersion: 1,
            deployCount: 0,
            totalRating: 0,
            ratingCount: 0,
            deployFee: deployFee,
            active: true,
            createdAt: block.timestamp
        });

        templateVersions[templateId][1] = TemplateVersion({
            version: 1,
            bytecodeHash: bytecodeHash,
            abiHash: abiHash,
            changelog: "Initial version",
            timestamp: block.timestamp
        });

        authorTemplates[msg.sender].push(templateId);
        categoryTemplates[category].push(templateId);

        emit TemplateRegistered(templateId, _name, msg.sender, category);
        return templateId;
    }

    /**
     * @notice Add a new version to an existing template (author only)
     */
    function addVersion(
        uint256 templateId,
        bytes32 bytecodeHash,
        bytes32 abiHash,
        string calldata changelog
    ) external {
        Template storage t = templates[templateId];
        require(t.author == msg.sender, "Not author");
        require(t.active, "Template inactive");
        require(bytecodeHash != bytes32(0), "Empty bytecode hash");

        t.currentVersion++;
        t.bytecodeHash = bytecodeHash;
        t.abiHash = abiHash;

        templateVersions[templateId][t.currentVersion] = TemplateVersion({
            version: t.currentVersion,
            bytecodeHash: bytecodeHash,
            abiHash: abiHash,
            changelog: changelog,
            timestamp: block.timestamp
        });

        emit TemplateVersionAdded(templateId, t.currentVersion, bytecodeHash);
    }

    /**
     * @notice Deactivate a template (author only)
     */
    function deactivateTemplate(uint256 templateId) external {
        Template storage t = templates[templateId];
        require(t.author == msg.sender || msg.sender == owner, "Not authorized");
        t.active = false;
        emit TemplateDeactivated(templateId);
    }

    /**
     * @notice Update deploy fee (author only)
     */
    function setDeployFee(uint256 templateId, uint256 newFee) external {
        require(templates[templateId].author == msg.sender, "Not author");
        templates[templateId].deployFee = newFee;
        emit DeployFeeUpdated(templateId, newFee);
    }

    // ──────────────────── Factory Deployment ────────────────────

    /**
     * @notice Deploy a contract from a template using CREATE2
     * @param templateId The template to deploy
     * @param bytecode The actual creation bytecode (must match template hash)
     * @param salt Salt for CREATE2 deterministic addressing
     */
    function deployFromTemplate(
        uint256 templateId,
        bytes calldata bytecode,
        bytes32 salt
    ) external payable whenNotPaused nonReentrant returns (address) {
        Template storage t = templates[templateId];
        require(t.active, "Template inactive");
        require(keccak256(bytecode) == t.bytecodeHash, "Bytecode mismatch");
        require(msg.value >= t.deployFee, "Insufficient deploy fee");

        // Deploy using CREATE2
        address deployed;
        assembly {
            deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        require(deployed != address(0), "Deployment failed");

        uint256 deploymentId = nextDeploymentId++;
        deployments[deploymentId] = Deployment({
            deploymentId: deploymentId,
            templateId: templateId,
            deployer: msg.sender,
            deployedContract: deployed,
            templateVersion: t.currentVersion,
            timestamp: block.timestamp
        });

        t.deployCount++;
        userDeployments[msg.sender].push(deploymentId);

        // Pay author
        if (t.deployFee > 0) {
            uint256 fee = (t.deployFee * platformFeeBPS) / 10000;
            uint256 payout = t.deployFee - fee;
            pendingWithdrawals[t.author] += payout;
            pendingWithdrawals[owner] += fee;
        }

        // Refund excess
        uint256 excess = msg.value - t.deployFee;
        if (excess > 0) {
            (bool ok, ) = msg.sender.call{value: excess}("");
            require(ok, "Refund failed");
        }

        emit ContractDeployed(deploymentId, templateId, msg.sender, deployed);
        return deployed;
    }

    /**
     * @notice Predict the CREATE2 deployment address
     * @param templateId Template ID (for bytecode hash reference)
     * @param bytecode The creation bytecode
     * @param salt The CREATE2 salt
     */
    function predictAddress(
        uint256 templateId,
        bytes calldata bytecode,
        bytes32 salt
    ) external view returns (address) {
        require(keccak256(bytecode) == templates[templateId].bytecodeHash, "Bytecode mismatch");
        bytes32 hash = keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(bytecode)
        ));
        return address(uint160(uint256(hash)));
    }

    // ──────────────────── Ratings ────────────────────

    /**
     * @notice Rate a template (1-5 stars, must have deployed it)
     * @param templateId The template to rate
     * @param rating Rating from 1 to 5
     */
    function rateTemplate(uint256 templateId, uint8 rating) external {
        require(rating >= 1 && rating <= 5, "Rating 1-5");
        require(!hasRated[templateId][msg.sender], "Already rated");
        require(templates[templateId].active, "Template inactive");

        // Verify user has deployed this template
        bool deployed = false;
        uint256[] storage deps = userDeployments[msg.sender];
        for (uint256 i = 0; i < deps.length; i++) {
            if (deployments[deps[i]].templateId == templateId) {
                deployed = true;
                break;
            }
        }
        require(deployed, "Must deploy first");

        hasRated[templateId][msg.sender] = true;
        templates[templateId].totalRating += rating;
        templates[templateId].ratingCount++;

        emit TemplateRated(templateId, msg.sender, rating);
    }

    // ──────────────────── Withdrawals ────────────────────

    function claimWithdrawal() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to claim");
        pendingWithdrawals[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        emit WithdrawalClaimed(msg.sender, amount);
    }

    // ──────────────────── Views ────────────────────

    function getTemplate(uint256 templateId) external view returns (Template memory) {
        return templates[templateId];
    }

    function getVersion(uint256 templateId, uint256 version) external view returns (TemplateVersion memory) {
        return templateVersions[templateId][version];
    }

    function getDeployment(uint256 deploymentId) external view returns (Deployment memory) {
        return deployments[deploymentId];
    }

    function getAverageRating(uint256 templateId) external view returns (uint256 avg, uint256 count) {
        Template storage t = templates[templateId];
        count = t.ratingCount;
        avg = count > 0 ? (t.totalRating * 100) / count : 0; // scaled by 100
    }

    function getAuthorTemplates(address author) external view returns (uint256[] memory) {
        return authorTemplates[author];
    }

    function getUserDeployments(address user) external view returns (uint256[] memory) {
        return userDeployments[user];
    }

    function getCategoryTemplates(Category category) external view returns (uint256[] memory) {
        return categoryTemplates[category];
    }

    // ──────────────────── Admin ────────────────────

    function setRegistrationFee(uint256 newFee) external onlyOwner {
        registrationFee = newFee;
    }

    function setFee(uint256 newFeeBPS) external onlyOwner {
        require(newFeeBPS <= 1000, "Fee too high");
        platformFeeBPS = newFeeBPS;
    }

    function withdraw() external onlyOwner {
        (bool ok, ) = owner.call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }

    receive() external payable {}
}
