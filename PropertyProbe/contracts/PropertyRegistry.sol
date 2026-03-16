// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title PropertyRegistry
 * @author ProbeChain Labs
 * @notice On-chain real estate registry with title chain history, lien
 *         management, and notary-verified title transfers.
 * @dev Designed for ProbeChain Rydberg Testnet (Chain ID 8004, EVM London).
 */

// ---------------------------------------------------------------------------
// Inline: Ownable
// ---------------------------------------------------------------------------
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// ---------------------------------------------------------------------------
// Inline: ReentrancyGuard
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Inline: Pausable
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Main Contract
// ---------------------------------------------------------------------------
contract PropertyRegistry is Ownable, ReentrancyGuard, Pausable {

    struct Property {
        bytes32 propertyId;
        string location;
        uint256 area;              // in square metres (or smallest unit)
        bytes32 ownershipHash;     // hash of legal ownership documents
        address currentOwner;
        uint256 registeredAt;
        bool exists;
    }

    struct Lien {
        uint256 id;
        bytes32 propertyId;
        address lienholder;
        uint256 amount;
        string description;
        bool active;
        uint256 createdAt;
    }

    struct TitleTransfer {
        address from;
        address to;
        bytes32 notarySignature;
        uint256 timestamp;
    }

    mapping(bytes32 => Property) public properties;
    mapping(address => bool) public authorizedNotaries;

    uint256 private _nextLienId;
    mapping(uint256 => Lien) public liens;
    mapping(bytes32 => uint256[]) public propertyLiens;
    mapping(bytes32 => TitleTransfer[]) public titleHistory;

    uint256 public totalProperties;

    // ---- Events ----------------------------------------------------------
    event PropertyRegistered(bytes32 indexed propertyId, address indexed owner, string location, uint256 area);
    event TitleTransferred(bytes32 indexed propertyId, address indexed from, address indexed to, bytes32 notarySignature);
    event LienAdded(uint256 indexed lienId, bytes32 indexed propertyId, address indexed lienholder, uint256 amount);
    event LienRemoved(uint256 indexed lienId, bytes32 indexed propertyId);
    event NotaryAuthorized(address indexed notary);
    event NotaryRevoked(address indexed notary);

    constructor() {
        _nextLienId = 1;
    }

    // ---- Notary Management -----------------------------------------------

    function authorizeNotary(address notary) external onlyOwner {
        require(notary != address(0), "Zero address");
        authorizedNotaries[notary] = true;
        emit NotaryAuthorized(notary);
    }

    function revokeNotary(address notary) external onlyOwner {
        authorizedNotaries[notary] = false;
        emit NotaryRevoked(notary);
    }

    // ---- Core Functions --------------------------------------------------

    /**
     * @notice Register a new property on-chain.
     * @param propertyId    Unique property identifier (e.g., hash of deed number).
     * @param location      Human-readable location string.
     * @param area          Property area in square metres.
     * @param ownershipHash Hash of ownership documentation.
     */
    function registerProperty(
        bytes32 propertyId,
        string calldata location,
        uint256 area,
        bytes32 ownershipHash
    ) external whenNotPaused {
        require(!properties[propertyId].exists, "Property already registered");
        require(bytes(location).length > 0, "Empty location");
        require(area > 0, "Zero area");
        require(ownershipHash != bytes32(0), "Empty ownership hash");

        properties[propertyId] = Property({
            propertyId: propertyId,
            location: location,
            area: area,
            ownershipHash: ownershipHash,
            currentOwner: msg.sender,
            registeredAt: block.timestamp,
            exists: true
        });

        titleHistory[propertyId].push(TitleTransfer({
            from: address(0),
            to: msg.sender,
            notarySignature: bytes32(0),
            timestamp: block.timestamp
        }));

        totalProperties++;
        emit PropertyRegistered(propertyId, msg.sender, location, area);
    }

    /**
     * @notice Transfer title of a property to a new owner. Requires notary signature.
     * @param propertyId      The property to transfer.
     * @param newOwner        New owner address.
     * @param notarySignature Notary verification hash.
     */
    function transferTitle(
        bytes32 propertyId,
        address newOwner,
        bytes32 notarySignature
    ) external whenNotPaused {
        Property storage p = properties[propertyId];
        require(p.exists, "Property not found");
        require(msg.sender == p.currentOwner, "Not the owner");
        require(newOwner != address(0), "Zero address");
        require(newOwner != p.currentOwner, "Same owner");
        require(authorizedNotaries[tx.origin] || authorizedNotaries[msg.sender], "Notary not authorized");

        // Check no active liens
        uint256[] memory lienIds = propertyLiens[propertyId];
        for (uint256 i = 0; i < lienIds.length; i++) {
            require(!liens[lienIds[i]].active, "Active lien exists");
        }

        address previousOwner = p.currentOwner;
        p.currentOwner = newOwner;

        titleHistory[propertyId].push(TitleTransfer({
            from: previousOwner,
            to: newOwner,
            notarySignature: notarySignature,
            timestamp: block.timestamp
        }));

        emit TitleTransferred(propertyId, previousOwner, newOwner, notarySignature);
    }

    /**
     * @notice Add a lien against a property.
     * @param propertyId  The property to lien.
     * @param amount      Lien amount.
     * @param description Lien description.
     * @return lienId     The new lien identifier.
     */
    function addLien(
        bytes32 propertyId,
        uint256 amount,
        string calldata description
    ) external whenNotPaused returns (uint256 lienId) {
        Property storage p = properties[propertyId];
        require(p.exists, "Property not found");
        require(msg.sender == p.currentOwner || msg.sender == owner(), "Not authorized");
        require(amount > 0, "Zero amount");

        lienId = _nextLienId++;
        liens[lienId] = Lien({
            id: lienId,
            propertyId: propertyId,
            lienholder: msg.sender,
            amount: amount,
            description: description,
            active: true,
            createdAt: block.timestamp
        });

        propertyLiens[propertyId].push(lienId);
        emit LienAdded(lienId, propertyId, msg.sender, amount);
    }

    /**
     * @notice Remove (satisfy) a lien.
     * @param lienId The lien to remove.
     */
    function removeLien(uint256 lienId) external whenNotPaused {
        Lien storage l = liens[lienId];
        require(l.id != 0, "Lien not found");
        require(l.active, "Lien already removed");
        require(
            msg.sender == l.lienholder || msg.sender == owner(),
            "Not authorized"
        );

        l.active = false;
        emit LienRemoved(lienId, l.propertyId);
    }

    // ---- Views -----------------------------------------------------------

    function getProperty(bytes32 propertyId) external view returns (Property memory) {
        require(properties[propertyId].exists, "Not found");
        return properties[propertyId];
    }

    function getTitleHistory(bytes32 propertyId) external view returns (TitleTransfer[] memory) {
        return titleHistory[propertyId];
    }

    function getPropertyLienIds(bytes32 propertyId) external view returns (uint256[] memory) {
        return propertyLiens[propertyId];
    }

    function getLien(uint256 lienId) external view returns (Lien memory) {
        require(liens[lienId].id != 0, "Not found");
        return liens[lienId];
    }
}
