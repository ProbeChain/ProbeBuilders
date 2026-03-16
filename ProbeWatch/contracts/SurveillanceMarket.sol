// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SurveillanceMarket
 * @author ProbeChain Rydberg Testnet
 * @notice Decentralized surveillance data marketplace for camera feeds, anomaly reporting, and rewards
 * @dev Camera registration, subscription-based feed access, anomaly bounties
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

contract SurveillanceMarket is Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum CameraStatus { Active, Inactive, Suspended }
    enum AnomalyStatus { Reported, Confirmed, Rejected, Rewarded }

    // ---------- Structs ----------
    struct Camera {
        uint256 id;
        address operator;
        bytes32 location;
        uint256 resolution;
        uint256 coverage;
        uint256 dailyRate;
        CameraStatus status;
        uint256 totalSubscribers;
        uint256 totalEarnings;
        uint256 registeredAt;
    }

    struct Subscription {
        uint256 id;
        uint256 cameraId;
        address subscriber;
        uint256 startTime;
        uint256 endTime;
        uint256 paid;
        bool active;
    }

    struct Anomaly {
        uint256 id;
        uint256 cameraId;
        address reporter;
        bytes32 anomalyHash;
        uint256 timestamp;
        AnomalyStatus status;
        uint256 reportedAt;
    }

    // ---------- State ----------
    uint256 public nextCameraId;
    uint256 public nextSubscriptionId;
    uint256 public nextAnomalyId;
    uint256 public anomalyReward;
    uint256 public protocolFeeBPS;

    mapping(uint256 => Camera) public cameras;
    mapping(uint256 => Subscription) public subscriptions;
    mapping(uint256 => Anomaly) public anomalies;
    mapping(address => uint256[]) public operatorCameras;
    mapping(address => uint256[]) public userSubscriptions;
    mapping(uint256 => uint256[]) public cameraAnomalies;
    mapping(address => uint256) public operatorEarnings;
    mapping(address => uint256) public reporterRewards;

    // ---------- Events ----------
    /// @notice Emitted when a camera is registered
    event CameraRegistered(uint256 indexed cameraId, address indexed operator, bytes32 location, uint256 dailyRate);
    /// @notice Emitted when a feed is subscribed to
    event FeedSubscribed(uint256 indexed subscriptionId, uint256 indexed cameraId, address indexed subscriber, uint256 duration);
    /// @notice Emitted when an anomaly is reported
    event AnomalyReported(uint256 indexed anomalyId, uint256 indexed cameraId, address indexed reporter, bytes32 anomalyHash);
    /// @notice Emitted when an anomaly is confirmed
    event AnomalyConfirmed(uint256 indexed anomalyId, uint256 indexed cameraId);
    /// @notice Emitted when an anomaly reward is claimed
    event RewardClaimed(address indexed reporter, uint256 amount);
    /// @notice Emitted when operator claims earnings
    event EarningsClaimed(address indexed operator, uint256 amount);
    /// @notice Emitted when camera status changes
    event CameraStatusChanged(uint256 indexed cameraId, CameraStatus newStatus);

    // ---------- Constructor ----------
    constructor(uint256 _anomalyReward, uint256 _feeBPS) Ownable() ReentrancyGuard() Pausable() {
        require(_feeBPS <= 500, "Fee too high");
        anomalyReward = _anomalyReward;
        protocolFeeBPS = _feeBPS;
        nextCameraId = 1;
        nextSubscriptionId = 1;
        nextAnomalyId = 1;
    }

    /**
     * @notice Register a new camera on the marketplace
     * @param location Encoded location hash
     * @param resolution Camera resolution (e.g., 1080, 4000 for 4K)
     * @param coverage Coverage area in square meters
     * @return cameraId The registered camera ID
     */
    function registerCamera(bytes32 location, uint256 resolution, uint256 coverage)
        external
        whenNotPaused
        returns (uint256 cameraId)
    {
        require(location != bytes32(0), "Empty location");
        require(resolution > 0, "Zero resolution");
        require(coverage > 0, "Zero coverage");

        cameraId = nextCameraId++;
        Camera storage c = cameras[cameraId];
        c.id = cameraId;
        c.operator = msg.sender;
        c.location = location;
        c.resolution = resolution;
        c.coverage = coverage;
        c.dailyRate = 0.01 ether;
        c.status = CameraStatus.Active;
        c.registeredAt = block.timestamp;

        operatorCameras[msg.sender].push(cameraId);
        emit CameraRegistered(cameraId, msg.sender, location, c.dailyRate);
    }

    /**
     * @notice Set daily rate for your camera
     * @param cameraId Your camera ID
     * @param dailyRate New daily rate in wei
     */
    function setDailyRate(uint256 cameraId, uint256 dailyRate) external {
        Camera storage c = cameras[cameraId];
        require(c.operator == msg.sender, "Not operator");
        require(dailyRate > 0, "Zero rate");
        c.dailyRate = dailyRate;
    }

    /**
     * @notice Subscribe to a camera feed
     * @param cameraId The camera to subscribe to
     * @param duration Duration in days
     * @return subscriptionId The subscription ID
     */
    function subscribeFeed(uint256 cameraId, uint256 duration)
        external
        payable
        whenNotPaused
        returns (uint256 subscriptionId)
    {
        Camera storage c = cameras[cameraId];
        require(c.id != 0, "Camera does not exist");
        require(c.status == CameraStatus.Active, "Camera not active");
        require(duration >= 1 && duration <= 365, "Invalid duration");

        uint256 cost = c.dailyRate * duration;
        require(msg.value >= cost, "Insufficient payment");

        subscriptionId = nextSubscriptionId++;
        Subscription storage s = subscriptions[subscriptionId];
        s.id = subscriptionId;
        s.cameraId = cameraId;
        s.subscriber = msg.sender;
        s.startTime = block.timestamp;
        s.endTime = block.timestamp + (duration * 1 days);
        s.paid = msg.value;
        s.active = true;

        c.totalSubscribers++;
        uint256 fee = (msg.value * protocolFeeBPS) / 10000;
        operatorEarnings[c.operator] += msg.value - fee;
        c.totalEarnings += msg.value - fee;

        userSubscriptions[msg.sender].push(subscriptionId);
        emit FeedSubscribed(subscriptionId, cameraId, msg.sender, duration);
    }

    /**
     * @notice Report an anomaly detected by a camera
     * @param cameraId The camera that detected the anomaly
     * @param anomalyHash Hash of the anomaly data
     * @param timestamp When the anomaly was observed
     * @return anomalyId The anomaly report ID
     */
    function reportAnomaly(uint256 cameraId, bytes32 anomalyHash, uint256 timestamp)
        external
        whenNotPaused
        returns (uint256 anomalyId)
    {
        Camera storage c = cameras[cameraId];
        require(c.id != 0, "Camera does not exist");
        require(anomalyHash != bytes32(0), "Empty anomaly hash");
        require(timestamp <= block.timestamp, "Future timestamp");

        anomalyId = nextAnomalyId++;
        Anomaly storage a = anomalies[anomalyId];
        a.id = anomalyId;
        a.cameraId = cameraId;
        a.reporter = msg.sender;
        a.anomalyHash = anomalyHash;
        a.timestamp = timestamp;
        a.status = AnomalyStatus.Reported;
        a.reportedAt = block.timestamp;

        cameraAnomalies[cameraId].push(anomalyId);
        emit AnomalyReported(anomalyId, cameraId, msg.sender, anomalyHash);
    }

    /**
     * @notice Confirm an anomaly report (owner only)
     * @param anomalyId The anomaly to confirm
     */
    function confirmAnomaly(uint256 anomalyId) external onlyOwner {
        Anomaly storage a = anomalies[anomalyId];
        require(a.status == AnomalyStatus.Reported, "Not in reported state");
        a.status = AnomalyStatus.Confirmed;
        reporterRewards[a.reporter] += anomalyReward;
        emit AnomalyConfirmed(anomalyId, a.cameraId);
    }

    /**
     * @notice Claim anomaly detection rewards
     */
    function claimReward() external nonReentrant whenNotPaused {
        uint256 amount = reporterRewards[msg.sender];
        require(amount > 0, "No rewards");
        reporterRewards[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        emit RewardClaimed(msg.sender, amount);
    }

    /**
     * @notice Operator claims accumulated earnings
     */
    function claimEarnings() external nonReentrant whenNotPaused {
        uint256 amount = operatorEarnings[msg.sender];
        require(amount > 0, "No earnings");
        operatorEarnings[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "Transfer failed");
        emit EarningsClaimed(msg.sender, amount);
    }

    /**
     * @notice Update camera status
     * @param cameraId The camera to update
     * @param status New status
     */
    function setCameraStatus(uint256 cameraId, CameraStatus status) external {
        Camera storage c = cameras[cameraId];
        require(c.operator == msg.sender || msg.sender == owner(), "Not authorized");
        c.status = status;
        emit CameraStatusChanged(cameraId, status);
    }

    // ---------- View Functions ----------
    function getOperatorCameras(address operator) external view returns (uint256[] memory) {
        return operatorCameras[operator];
    }

    function getCameraAnomalies(uint256 cameraId) external view returns (uint256[] memory) {
        return cameraAnomalies[cameraId];
    }

    function getUserSubscriptions(address user) external view returns (uint256[] memory) {
        return userSubscriptions[user];
    }

    /// @notice Fund the reward pool for anomaly bounties
    function fundRewardPool() external payable {
        require(msg.value > 0, "Must send funds");
    }

    /// @notice Withdraw protocol fees
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "No balance");
        (bool ok, ) = owner().call{value: bal}("");
        require(ok, "Withdraw failed");
    }
}
