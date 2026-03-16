// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title CloudPlatform
 * @author ProbeChain
 * @notice Decentralized cloud platform on ProbeChain Rydberg Testnet
 * @dev Deploy containers, scale resources, manage deployments, handle refunds
 */
contract CloudPlatform {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() { require(msg.sender == _owner, "Not owner"); _; }
    event OwnershipTransferred(address indexed prev, address indexed next_);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _locked = 1;
    modifier nonReentrant() { require(_locked == 1, "Reentrant"); _locked = 2; _; _locked = 1; }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "Paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums & Structs ────────────────────────────────────────────────
    enum DeployStatus { Running, Scaled, Terminated, Refunded }

    struct Resources {
        uint256 cpuMillicores;
        uint256 memoryMB;
        uint256 storageGB;
        uint256 bandwidthMbps;
    }

    struct Deployment {
        address deployer;
        bytes32 imageHash;
        Resources resources;
        uint256 deposit;
        uint256 pricePerHour;
        uint256 startedAt;
        uint256 expiresAt;
        DeployStatus status;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => Deployment) public deployments;
    mapping(address => uint256) public pendingWithdrawals;
    mapping(address => uint256[]) public userDeployments;
    uint256 public nextDeployId;
    uint256 public basePricePerHour = 1e14; // 0.0001 ETH base
    uint256 public platformFee = 300; // 3%
    uint256 public constant FEE_DENOMINATOR = 10000;

    // ─── Events ─────────────────────────────────────────────────────────
    event ContainerDeployed(uint256 indexed deployId, address indexed deployer, bytes32 imageHash, uint256 duration);
    event ContainerScaled(uint256 indexed deployId, uint256 newCpu, uint256 newMemory);
    event DeploymentTerminated(uint256 indexed deployId);
    event RefundClaimed(uint256 indexed deployId, address indexed deployer, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Internal ───────────────────────────────────────────────────────
    function _calculatePrice(Resources memory res, uint256 hours_) internal view returns (uint256) {
        uint256 cpuFactor = res.cpuMillicores / 1000; // per core
        if (cpuFactor == 0) cpuFactor = 1;
        uint256 memFactor = res.memoryMB / 1024; // per GB
        if (memFactor == 0) memFactor = 1;
        return basePricePerHour * (cpuFactor + memFactor) * hours_;
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Deploy a container
     * @param imageHash Hash of the container image
     * @param resources Resource allocation
     * @param durationHours Duration in hours
     */
    function deployContainer(
        bytes32 imageHash,
        Resources calldata resources,
        uint256 durationHours
    ) external payable whenNotPaused returns (uint256) {
        require(imageHash != bytes32(0), "Empty image hash");
        require(durationHours > 0, "Zero duration");
        require(resources.cpuMillicores > 0, "Zero CPU");
        require(resources.memoryMB > 0, "Zero memory");

        uint256 cost = _calculatePrice(resources, durationHours);
        require(msg.value >= cost, "Insufficient payment");

        uint256 id = nextDeployId++;
        deployments[id] = Deployment({
            deployer: msg.sender,
            imageHash: imageHash,
            resources: resources,
            deposit: cost,
            pricePerHour: _calculatePrice(resources, 1),
            startedAt: block.timestamp,
            expiresAt: block.timestamp + (durationHours * 1 hours),
            status: DeployStatus.Running
        });

        userDeployments[msg.sender].push(id);

        uint256 fee = (cost * platformFee) / FEE_DENOMINATOR;
        pendingWithdrawals[_owner] += fee;

        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit ContainerDeployed(id, msg.sender, imageHash, durationHours);
        return id;
    }

    /**
     * @notice Scale a running container's resources
     * @param deployId The deployment to scale
     * @param newResources New resource allocation
     */
    function scaleContainer(
        uint256 deployId,
        Resources calldata newResources
    ) external payable whenNotPaused nonReentrant {
        Deployment storage d = deployments[deployId];
        require(msg.sender == d.deployer, "Not deployer");
        require(d.status == DeployStatus.Running, "Not running");
        require(block.timestamp < d.expiresAt, "Expired");
        require(newResources.cpuMillicores > 0 && newResources.memoryMB > 0, "Zero resources");

        uint256 remainingHours = (d.expiresAt - block.timestamp) / 1 hours;
        if (remainingHours == 0) remainingHours = 1;

        uint256 newCost = _calculatePrice(newResources, remainingHours);
        uint256 oldRemainingCost = d.pricePerHour * remainingHours;

        if (newCost > oldRemainingCost) {
            uint256 additional = newCost - oldRemainingCost;
            require(msg.value >= additional, "Insufficient payment");
            d.deposit += additional;
            uint256 fee = (additional * platformFee) / FEE_DENOMINATOR;
            pendingWithdrawals[_owner] += fee;
            if (msg.value > additional) {
                payable(msg.sender).transfer(msg.value - additional);
            }
        }

        d.resources = newResources;
        d.pricePerHour = _calculatePrice(newResources, 1);
        d.status = DeployStatus.Scaled;

        emit ContainerScaled(deployId, newResources.cpuMillicores, newResources.memoryMB);
    }

    /**
     * @notice Get deployment status
     * @param deployId The deployment to query
     */
    function getDeploymentStatus(uint256 deployId) external view returns (
        DeployStatus status,
        uint256 remainingSeconds,
        Resources memory resources
    ) {
        Deployment storage d = deployments[deployId];
        status = d.status;
        resources = d.resources;
        if (block.timestamp < d.expiresAt && (d.status == DeployStatus.Running || d.status == DeployStatus.Scaled)) {
            remainingSeconds = d.expiresAt - block.timestamp;
        }
    }

    /**
     * @notice Terminate a deployment early
     * @param deployId The deployment to terminate
     */
    function terminateDeployment(uint256 deployId) external whenNotPaused {
        Deployment storage d = deployments[deployId];
        require(msg.sender == d.deployer || msg.sender == _owner, "Not authorized");
        require(d.status == DeployStatus.Running || d.status == DeployStatus.Scaled, "Not running");

        d.status = DeployStatus.Terminated;
        emit DeploymentTerminated(deployId);
    }

    /**
     * @notice Claim refund for early termination
     * @param deployId The terminated deployment
     */
    function claimRefund(uint256 deployId) external whenNotPaused nonReentrant {
        Deployment storage d = deployments[deployId];
        require(msg.sender == d.deployer, "Not deployer");
        require(d.status == DeployStatus.Terminated, "Not terminated");

        uint256 usedHours = (block.timestamp - d.startedAt) / 1 hours;
        usedHours++; // round up
        uint256 usedCost = d.pricePerHour * usedHours;
        if (usedCost > d.deposit) usedCost = d.deposit;

        uint256 refund = d.deposit - usedCost;
        d.status = DeployStatus.Refunded;

        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }

        emit RefundClaimed(deployId, msg.sender, refund);
    }

    /**
     * @notice Withdraw pending balance
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "Nothing to withdraw");
        pendingWithdrawals[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Get user deployment IDs
     */
    function getUserDeployments(address user) external view returns (uint256[] memory) {
        return userDeployments[user];
    }

    /**
     * @notice Update base price (owner only)
     */
    function setBasePrice(uint256 newPrice) external onlyOwner {
        basePricePerHour = newPrice;
    }
}
