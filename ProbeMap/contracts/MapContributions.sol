// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MapContributions
 * @author ProbeChain Rydberg Testnet
 * @notice Decentralized mapping with location submissions, verification, and contributor rewards
 * @dev POI (Points of Interest) are submitted with geo coordinates, verified by trusted verifiers
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

contract MapContributions is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum POIType { Restaurant, Shop, Park, Hospital, School, Transit, Hotel, Museum, Gas, Other }
    enum LocationStatus { Submitted, Verified, Disputed, Removed }

    // ---------- Structs ----------
    struct Location {
        uint256 id;
        address contributor;
        int256 lat;
        int256 long_;
        POIType poiType;
        bytes32 dataHash;
        LocationStatus status;
        uint256 verifications;
        uint256 disputes;
        uint256 submittedAt;
        uint256 verifiedAt;
    }

    // ---------- State ----------
    uint256 public nextLocationId;
    uint256 public rewardPerVerifiedPOI;
    uint256 public rewardPool;
    uint256 public minVerifications;

    mapping(uint256 => Location) public locations;
    mapping(address => uint256[]) public contributorLocations;
    mapping(address => uint256) public contributorRewards;
    mapping(address => bool) public verifiers;
    mapping(uint256 => mapping(address => bool)) public hasVerified;

    // Grid index: encode lat/long grid cell → location IDs
    mapping(bytes32 => uint256[]) private gridIndex;

    // ---------- Events ----------
    /// @notice Emitted when a location is submitted
    event LocationSubmitted(uint256 indexed locationId, address indexed contributor, int256 lat, int256 long_, POIType poiType);
    /// @notice Emitted when a location is verified
    event LocationVerified(uint256 indexed locationId, address indexed verifier, uint256 totalVerifications);
    /// @notice Emitted when a location reaches verification threshold
    event LocationConfirmed(uint256 indexed locationId, uint256 verifications);
    /// @notice Emitted when a location is disputed
    event LocationDisputed(uint256 indexed locationId, address indexed disputer);
    /// @notice Emitted when a location is removed
    event LocationRemoved(uint256 indexed locationId);
    /// @notice Emitted when a contributor claims rewards
    event RewardClaimed(address indexed contributor, uint256 amount);
    /// @notice Emitted when the reward pool is funded
    event RewardPoolFunded(uint256 amount);

    // ---------- Constructor ----------
    constructor(uint256 _rewardPerPOI, uint256 _minVerifications)
        Ownable() ReentrancyGuard() Pausable()
    {
        rewardPerVerifiedPOI = _rewardPerPOI;
        minVerifications = _minVerifications;
        nextLocationId = 1;
    }

    /// @notice Fund reward pool
    function fundRewardPool() external payable {
        require(msg.value > 0, "Must send funds");
        rewardPool += msg.value;
        emit RewardPoolFunded(msg.value);
    }

    /// @notice Add a verifier
    function addVerifier(address v) external onlyOwner {
        require(v != address(0), "Zero address");
        verifiers[v] = true;
    }

    /// @notice Remove a verifier
    function removeVerifier(address v) external onlyOwner {
        verifiers[v] = false;
    }

    /**
     * @notice Submit a location/POI to the map
     * @param lat Latitude (scaled by 1e6, e.g., 35.681236 → 35681236)
     * @param long_ Longitude (scaled by 1e6)
     * @param poiType Type of point of interest
     * @param dataHash IPFS hash of detailed POI data
     * @return locationId The created location identifier
     */
    function submitLocation(int256 lat, int256 long_, POIType poiType, bytes32 dataHash)
        external
        whenNotPaused
        returns (uint256 locationId)
    {
        require(lat >= -90000000 && lat <= 90000000, "Invalid latitude");
        require(long_ >= -180000000 && long_ <= 180000000, "Invalid longitude");
        require(dataHash != bytes32(0), "Empty data hash");

        locationId = nextLocationId++;
        Location storage loc = locations[locationId];
        loc.id = locationId;
        loc.contributor = msg.sender;
        loc.lat = lat;
        loc.long_ = long_;
        loc.poiType = poiType;
        loc.dataHash = dataHash;
        loc.status = LocationStatus.Submitted;
        loc.submittedAt = block.timestamp;

        contributorLocations[msg.sender].push(locationId);

        // Index in grid (1-degree cells)
        bytes32 cell = _gridCell(lat, long_);
        gridIndex[cell].push(locationId);

        emit LocationSubmitted(locationId, msg.sender, lat, long_, poiType);
    }

    /**
     * @notice Verify a submitted location
     * @param locationId The location to verify
     */
    function verifyLocation(uint256 locationId) external whenNotPaused {
        require(verifiers[msg.sender], "Not a verifier");
        Location storage loc = locations[locationId];
        require(loc.id != 0, "Location does not exist");
        require(loc.status == LocationStatus.Submitted, "Not in submitted state");
        require(!hasVerified[locationId][msg.sender], "Already verified by you");
        require(loc.contributor != msg.sender, "Cannot verify own submission");

        hasVerified[locationId][msg.sender] = true;
        loc.verifications++;

        emit LocationVerified(locationId, msg.sender, loc.verifications);

        if (loc.verifications >= minVerifications) {
            loc.status = LocationStatus.Verified;
            loc.verifiedAt = block.timestamp;
            contributorRewards[loc.contributor] += rewardPerVerifiedPOI;
            emit LocationConfirmed(locationId, loc.verifications);
        }
    }

    /**
     * @notice Dispute a location
     * @param locationId The location to dispute
     */
    function disputeLocation(uint256 locationId) external whenNotPaused {
        Location storage loc = locations[locationId];
        require(loc.id != 0, "Location does not exist");
        require(loc.status != LocationStatus.Removed, "Already removed");
        loc.disputes++;
        if (loc.disputes >= minVerifications) {
            loc.status = LocationStatus.Disputed;
        }
        emit LocationDisputed(locationId, msg.sender);
    }

    /**
     * @notice Remove a disputed location (owner only)
     * @param locationId The location to remove
     */
    function removeLocation(uint256 locationId) external onlyOwner {
        Location storage loc = locations[locationId];
        require(loc.id != 0, "Does not exist");
        loc.status = LocationStatus.Removed;
        emit LocationRemoved(locationId);
    }

    /**
     * @notice Get locations in an area (grid-based approximation)
     * @param lat Center latitude (scaled 1e6)
     * @param long_ Center longitude (scaled 1e6)
     * @param radius Search radius in grid cells (1 = ~111km)
     * @return locationIds Array of location IDs in the area
     */
    function getLocationsInArea(int256 lat, int256 long_, uint256 radius)
        external view returns (uint256[] memory locationIds)
    {
        require(radius <= 5, "Radius too large");
        int256 r = int256(radius);

        // Count first
        uint256 count;
        for (int256 dLat = -r; dLat <= r; dLat++) {
            for (int256 dLong = -r; dLong <= r; dLong++) {
                bytes32 cell = _gridCell(lat + dLat * 1000000, long_ + dLong * 1000000);
                count += gridIndex[cell].length;
            }
        }

        locationIds = new uint256[](count);
        uint256 idx;
        for (int256 dLat = -r; dLat <= r; dLat++) {
            for (int256 dLong = -r; dLong <= r; dLong++) {
                bytes32 cell = _gridCell(lat + dLat * 1000000, long_ + dLong * 1000000);
                uint256[] storage cellLocs = gridIndex[cell];
                for (uint256 i = 0; i < cellLocs.length; i++) {
                    locationIds[idx++] = cellLocs[i];
                }
            }
        }
    }

    /**
     * @notice Claim accumulated rewards
     */
    function rewardContributor() external nonReentrant whenNotPaused {
        uint256 amount = contributorRewards[msg.sender];
        require(amount > 0, "No rewards");
        require(rewardPool >= amount, "Insufficient pool");

        contributorRewards[msg.sender] = 0;
        rewardPool -= amount;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        emit RewardClaimed(msg.sender, amount);
    }

    // ---------- Internal ----------
    function _gridCell(int256 lat, int256 long_) internal pure returns (bytes32) {
        int256 gridLat = lat / 1000000;
        int256 gridLong = long_ / 1000000;
        return keccak256(abi.encodePacked(gridLat, gridLong));
    }

    // ---------- View ----------
    function getContributorLocations(address contributor) external view returns (uint256[] memory) {
        return contributorLocations[contributor];
    }

    function setRewardPerPOI(uint256 _reward) external onlyOwner {
        rewardPerVerifiedPOI = _reward;
    }

    function setMinVerifications(uint256 _min) external onlyOwner {
        require(_min >= 1, "Min 1");
        minVerifications = _min;
    }
}
