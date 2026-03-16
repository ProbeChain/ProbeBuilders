// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GraphAnalytics
 * @author ProbeChain Rydberg Testnet
 * @notice On-chain relationship graph for entity analytics, clustering, and querying
 * @dev Register entities, record relationships, query connections and clusters
 */

// ---------- Inlined Ownable ----------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: caller is not the owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner); _owner = newOwner;
    }
}

// ---------- Inlined ReentrancyGuard ----------
abstract contract ReentrancyGuard {
    uint256 private _status;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    constructor() { _status = _NOT_ENTERED; }
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED; _; _status = _NOT_ENTERED;
    }
}

// ---------- Inlined Pausable ----------
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

contract GraphAnalytics is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum EntityType { Wallet, Contract, Protocol, DAO, Token, NFTCollection, Bridge, Oracle }
    enum RelationType { Transfer, Interaction, Ownership, Delegation, Approval, Governance, Liquidity }

    // ---------- Structs ----------
    struct Entity {
        uint256 id;
        address registrant;
        EntityType entityType;
        bytes32 dataHash;
        uint256 relationshipCount;
        uint256 registeredAt;
        bool active;
    }

    struct Relationship {
        uint256 id;
        uint256 entity1;
        uint256 entity2;
        RelationType relationType;
        bytes32 metadata;
        uint256 weight;
        address recorder;
        uint256 recordedAt;
    }

    // ---------- State ----------
    uint256 public nextEntityId;
    uint256 public nextRelationshipId;

    mapping(uint256 => Entity) public entities;
    mapping(uint256 => Relationship) public relationships;
    mapping(uint256 => uint256[]) public entityRelationships;
    mapping(address => uint256[]) public registrantEntities;
    mapping(bytes32 => bool) public relationshipExists;
    mapping(address => bool) public authorizedRecorders;

    // ---------- Events ----------
    /// @notice Emitted when a new entity is registered
    event EntityRegistered(uint256 indexed entityId, address indexed registrant, EntityType entityType, bytes32 dataHash);
    /// @notice Emitted when a relationship is recorded
    event RelationshipRecorded(uint256 indexed relationshipId, uint256 indexed entity1, uint256 indexed entity2, RelationType relationType);
    /// @notice Emitted when an entity is deactivated
    event EntityDeactivated(uint256 indexed entityId);
    /// @notice Emitted when a recorder is authorized
    event RecorderAuthorized(address indexed recorder);
    /// @notice Emitted when a cluster query is logged
    event ClusterQueried(uint256 indexed entityId, uint256 depth, uint256 clusterSize);

    // ---------- Constructor ----------
    constructor() Ownable() ReentrancyGuard() Pausable() {
        nextEntityId = 1;
        nextRelationshipId = 1;
    }

    /**
     * @notice Authorize an address to record relationships
     * @param recorder The address to authorize
     */
    function authorizeRecorder(address recorder) external onlyOwner {
        require(recorder != address(0), "Zero address");
        authorizedRecorders[recorder] = true;
        emit RecorderAuthorized(recorder);
    }

    /**
     * @notice Revoke recorder authorization
     * @param recorder The address to revoke
     */
    function revokeRecorder(address recorder) external onlyOwner {
        authorizedRecorders[recorder] = false;
    }

    /**
     * @notice Register a new entity in the graph
     * @param entityType The type of entity
     * @param dataHash IPFS hash of entity details
     * @return entityId The registered entity ID
     */
    function registerEntity(EntityType entityType, bytes32 dataHash)
        external
        whenNotPaused
        returns (uint256 entityId)
    {
        require(dataHash != bytes32(0), "Empty data hash");

        entityId = nextEntityId++;
        Entity storage e = entities[entityId];
        e.id = entityId;
        e.registrant = msg.sender;
        e.entityType = entityType;
        e.dataHash = dataHash;
        e.registeredAt = block.timestamp;
        e.active = true;

        registrantEntities[msg.sender].push(entityId);
        emit EntityRegistered(entityId, msg.sender, entityType, dataHash);
    }

    /**
     * @notice Record a relationship between two entities
     * @param entity1 First entity ID
     * @param entity2 Second entity ID
     * @param relationType Type of relationship
     * @param metadata Additional data hash
     * @return relationshipId The relationship ID
     */
    function recordRelationship(
        uint256 entity1,
        uint256 entity2,
        RelationType relationType,
        bytes32 metadata
    )
        external
        whenNotPaused
        returns (uint256 relationshipId)
    {
        require(authorizedRecorders[msg.sender] || msg.sender == owner(), "Not authorized");
        require(entities[entity1].active, "Entity1 not active");
        require(entities[entity2].active, "Entity2 not active");
        require(entity1 != entity2, "Self-relationship");

        bytes32 relHash = keccak256(abi.encodePacked(entity1, entity2, relationType));
        require(!relationshipExists[relHash], "Relationship already exists");
        relationshipExists[relHash] = true;

        relationshipId = nextRelationshipId++;
        Relationship storage r = relationships[relationshipId];
        r.id = relationshipId;
        r.entity1 = entity1;
        r.entity2 = entity2;
        r.relationType = relationType;
        r.metadata = metadata;
        r.weight = 1;
        r.recorder = msg.sender;
        r.recordedAt = block.timestamp;

        entityRelationships[entity1].push(relationshipId);
        entityRelationships[entity2].push(relationshipId);
        entities[entity1].relationshipCount++;
        entities[entity2].relationshipCount++;

        emit RelationshipRecorded(relationshipId, entity1, entity2, relationType);
    }

    /**
     * @notice Increase weight of an existing relationship
     * @param relationshipId The relationship to strengthen
     */
    function strengthenRelationship(uint256 relationshipId) external {
        require(authorizedRecorders[msg.sender] || msg.sender == owner(), "Not authorized");
        Relationship storage r = relationships[relationshipId];
        require(r.id != 0, "Relationship does not exist");
        r.weight++;
    }

    /**
     * @notice Query all relationships for an entity
     * @param entityId The entity to query
     * @return relIds Array of relationship IDs
     */
    function queryRelationships(uint256 entityId) external view returns (uint256[] memory relIds) {
        return entityRelationships[entityId];
    }

    /**
     * @notice Get a cluster of entities around a root entity (depth=1 neighbors)
     * @param entityId Root entity
     * @param depth Cluster depth (currently supports 1)
     * @return clusterEntityIds Array of connected entity IDs
     */
    function getCluster(uint256 entityId, uint256 depth)
        external
        view
        returns (uint256[] memory clusterEntityIds)
    {
        require(depth >= 1 && depth <= 2, "Depth must be 1 or 2");
        require(entities[entityId].active, "Entity not active");

        uint256[] storage rels = entityRelationships[entityId];

        if (depth == 1) {
            clusterEntityIds = new uint256[](rels.length);
            for (uint256 i = 0; i < rels.length; i++) {
                Relationship storage r = relationships[rels[i]];
                clusterEntityIds[i] = (r.entity1 == entityId) ? r.entity2 : r.entity1;
            }
        } else {
            // Depth 2: get neighbors of neighbors (flatten, may have duplicates)
            uint256 totalCount;
            for (uint256 i = 0; i < rels.length; i++) {
                Relationship storage r = relationships[rels[i]];
                uint256 neighborId = (r.entity1 == entityId) ? r.entity2 : r.entity1;
                totalCount += entityRelationships[neighborId].length + 1;
            }

            clusterEntityIds = new uint256[](totalCount);
            uint256 idx;
            for (uint256 i = 0; i < rels.length; i++) {
                Relationship storage r = relationships[rels[i]];
                uint256 neighborId = (r.entity1 == entityId) ? r.entity2 : r.entity1;
                clusterEntityIds[idx++] = neighborId;

                uint256[] storage nRels = entityRelationships[neighborId];
                for (uint256 j = 0; j < nRels.length; j++) {
                    Relationship storage nr = relationships[nRels[j]];
                    clusterEntityIds[idx++] = (nr.entity1 == neighborId) ? nr.entity2 : nr.entity1;
                }
            }
        }
    }

    /**
     * @notice Deactivate an entity
     * @param entityId The entity to deactivate
     */
    function deactivateEntity(uint256 entityId) external {
        Entity storage e = entities[entityId];
        require(e.registrant == msg.sender || msg.sender == owner(), "Not authorized");
        require(e.active, "Already inactive");
        e.active = false;
        emit EntityDeactivated(entityId);
    }

    // ---------- View ----------
    function getRegistrantEntities(address registrant) external view returns (uint256[] memory) {
        return registrantEntities[registrant];
    }

    function getEntityRelationshipCount(uint256 entityId) external view returns (uint256) {
        return entities[entityId].relationshipCount;
    }
}
