// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title EdgeStorage
 * @author ProbeChain
 * @notice Decentralized edge storage network on ProbeChain Rydberg Testnet
 * @dev Node registration, paid data storage, retrieval, extension, and deletion
 */
contract EdgeStorage {
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

    // ─── Structs ────────────────────────────────────────────────────────
    struct StorageNode {
        address nodeOperator;
        uint256 capacityGB;
        uint256 usedGB;
        string location;
        uint256 bandwidthMbps;
        uint256 pricePerGBDay;
        bool active;
        uint256 registeredAt;
    }

    struct StorageRecord {
        uint256 nodeId;
        address dataOwner;
        bytes32 dataHash;
        uint256 sizeGB;
        uint256 expiresAt;
        bool deleted;
        uint256 createdAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => StorageNode) public nodes;
    mapping(uint256 => StorageRecord) public records;
    mapping(address => uint256) public pendingWithdrawals;
    uint256 public nextNodeId;
    uint256 public nextRecordId;
    uint256 public platformFee = 200; // 2%
    uint256 public constant FEE_DENOMINATOR = 10000;

    // ─── Events ─────────────────────────────────────────────────────────
    event NodeRegistered(uint256 indexed nodeId, address indexed operator, uint256 capacityGB);
    event DataStored(uint256 indexed recordId, uint256 indexed nodeId, bytes32 dataHash, uint256 sizeGB);
    event DataRetrieved(uint256 indexed recordId, address indexed requester);
    event StorageExtended(uint256 indexed recordId, uint256 newExpiry);
    event DataDeleted(uint256 indexed recordId);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register as a storage node operator
     * @param capacityGB Total storage capacity in GB
     * @param location Node location description
     * @param bandwidthMbps Network bandwidth in Mbps
     * @param pricePerGBDay Price per GB per day in wei
     */
    function registerNode(
        uint256 capacityGB,
        string calldata location,
        uint256 bandwidthMbps,
        uint256 pricePerGBDay
    ) external whenNotPaused returns (uint256) {
        require(capacityGB > 0, "Zero capacity");
        require(bytes(location).length > 0, "Empty location");
        require(pricePerGBDay > 0, "Zero price");

        uint256 id = nextNodeId++;
        nodes[id] = StorageNode({
            nodeOperator: msg.sender,
            capacityGB: capacityGB,
            usedGB: 0,
            location: location,
            bandwidthMbps: bandwidthMbps,
            pricePerGBDay: pricePerGBDay,
            active: true,
            registeredAt: block.timestamp
        });

        emit NodeRegistered(id, msg.sender, capacityGB);
        return id;
    }

    /**
     * @notice Store data on a node
     * @param nodeId The storage node
     * @param dataHash Hash of the data
     * @param sizeGB Size of data in GB
     * @param durationDays Storage duration in days
     */
    function storeData(
        uint256 nodeId,
        bytes32 dataHash,
        uint256 sizeGB,
        uint256 durationDays
    ) external payable whenNotPaused nonReentrant returns (uint256) {
        StorageNode storage n = nodes[nodeId];
        require(n.active, "Node not active");
        require(sizeGB > 0 && durationDays > 0, "Zero values");
        require(n.usedGB + sizeGB <= n.capacityGB, "Insufficient capacity");

        uint256 cost = n.pricePerGBDay * sizeGB * durationDays;
        require(msg.value >= cost, "Insufficient payment");

        n.usedGB += sizeGB;
        uint256 fee = (cost * platformFee) / FEE_DENOMINATOR;
        pendingWithdrawals[_owner] += fee;
        pendingWithdrawals[n.nodeOperator] += cost - fee;

        uint256 recordId = nextRecordId++;
        records[recordId] = StorageRecord({
            nodeId: nodeId,
            dataOwner: msg.sender,
            dataHash: dataHash,
            sizeGB: sizeGB,
            expiresAt: block.timestamp + (durationDays * 1 days),
            deleted: false,
            createdAt: block.timestamp
        });

        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit DataStored(recordId, nodeId, dataHash, sizeGB);
        return recordId;
    }

    /**
     * @notice Log a data retrieval event
     * @param recordId The storage record
     */
    function retrieveData(uint256 recordId) external whenNotPaused {
        StorageRecord storage r = records[recordId];
        require(!r.deleted, "Data deleted");
        require(block.timestamp < r.expiresAt, "Storage expired");
        require(msg.sender == r.dataOwner, "Not data owner");

        emit DataRetrieved(recordId, msg.sender);
    }

    /**
     * @notice Extend storage duration
     * @param recordId The storage record to extend
     * @param additionalDays Additional days
     */
    function extendStorage(uint256 recordId, uint256 additionalDays) external payable whenNotPaused nonReentrant {
        StorageRecord storage r = records[recordId];
        require(!r.deleted, "Data deleted");
        require(msg.sender == r.dataOwner, "Not data owner");
        require(additionalDays > 0, "Zero days");

        StorageNode storage n = nodes[r.nodeId];
        uint256 cost = n.pricePerGBDay * r.sizeGB * additionalDays;
        require(msg.value >= cost, "Insufficient payment");

        uint256 fee = (cost * platformFee) / FEE_DENOMINATOR;
        pendingWithdrawals[_owner] += fee;
        pendingWithdrawals[n.nodeOperator] += cost - fee;

        r.expiresAt += additionalDays * 1 days;

        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        emit StorageExtended(recordId, r.expiresAt);
    }

    /**
     * @notice Delete stored data
     * @param recordId The storage record to delete
     */
    function deleteData(uint256 recordId) external whenNotPaused {
        StorageRecord storage r = records[recordId];
        require(msg.sender == r.dataOwner, "Not data owner");
        require(!r.deleted, "Already deleted");

        r.deleted = true;
        nodes[r.nodeId].usedGB -= r.sizeGB;
        emit DataDeleted(recordId);
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
     * @notice Deactivate a node
     */
    function deactivateNode(uint256 nodeId) external {
        require(msg.sender == nodes[nodeId].nodeOperator || msg.sender == _owner, "Not authorized");
        nodes[nodeId].active = false;
    }
}
