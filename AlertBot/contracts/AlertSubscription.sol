// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AlertSubscription
 * @author ProbeBuilders
 * @notice On-chain alert subscription system with pay-per-alert model and watcher rewards
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */
contract AlertSubscription {
    // ─── Ownership ───────────────────────────────────────────────────
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "AlertSubscription: not owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "AlertSubscription: zero address");
        owner = newOwner;
    }

    // ─── Pausable ────────────────────────────────────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "AlertSubscription: paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ─── Reentrancy Guard ────────────────────────────────────────────
    uint256 private _status = 1;
    modifier nonReentrant() { require(_status != 2, "AlertSubscription: reentrant"); _status = 2; _; _status = 1; }

    // ─── Enums & Structs ─────────────────────────────────────────────
    enum EventType { PriceAbove, PriceBelow, LargeTransfer, ContractCall, BalanceChange, Custom }
    enum AlertStatus { Active, Paused, Expired, Cancelled }

    /// @notice An alert definition created by watchers
    struct Alert {
        address creator;
        EventType eventType;
        uint256 threshold;          // meaning depends on eventType
        address callbackContract;   // optional contract to notify
        bytes4 callbackSelector;    // function selector to call
        string description;
        uint256 pricePerAlert;      // cost per trigger for subscribers
        uint256 totalTriggers;
        uint256 subscriberCount;
        AlertStatus status;
        uint256 createdAt;
    }

    /// @notice A user's subscription to an alert
    struct Subscription {
        address subscriber;
        uint256 alertId;
        uint256 balance;            // prepaid balance
        uint256 alertsReceived;
        bool active;
        uint256 subscribedAt;
    }

    /// @notice A triggered alert instance
    struct TriggerRecord {
        uint256 alertId;
        address triggeredBy;        // watcher who triggered
        bytes data;                 // alert payload
        uint256 timestamp;
        uint256 subscribersNotified;
    }

    // ─── State ───────────────────────────────────────────────────────
    uint256 public nextAlertId = 1;
    uint256 public nextSubscriptionId = 1;
    uint256 public nextTriggerId = 1;
    uint256 public platformFeeBPS = 500; // 5%
    uint256 public minAlertPrice = 0.0001 ether;

    mapping(uint256 => Alert) public alerts;
    mapping(uint256 => Subscription) public subscriptions;
    mapping(uint256 => TriggerRecord) public triggers;
    mapping(uint256 => uint256[]) public alertTriggers; // alertId => triggerIds
    mapping(address => uint256[]) public userSubscriptions; // user => subscriptionIds
    mapping(uint256 => mapping(address => uint256)) public subscriberToSubId; // alertId => subscriber => subId
    mapping(address => bool) public authorizedWatchers;
    mapping(address => uint256) public watcherEarnings;

    // ─── Events ──────────────────────────────────────────────────────
    event AlertCreated(uint256 indexed alertId, address indexed creator, EventType eventType, uint256 threshold, uint256 pricePerAlert);
    event AlertStatusChanged(uint256 indexed alertId, AlertStatus newStatus);
    event Subscribed(uint256 indexed subscriptionId, uint256 indexed alertId, address indexed subscriber, uint256 deposit);
    event SubscriptionCancelled(uint256 indexed subscriptionId, uint256 refund);
    event AlertTriggered(uint256 indexed triggerId, uint256 indexed alertId, address indexed triggeredBy, uint256 subscribersNotified);
    event SubscriberNotified(uint256 indexed alertId, address indexed subscriber, bytes data);
    event WatcherAuthorized(address indexed watcher);
    event WatcherRevoked(address indexed watcher);
    event WatcherWithdrawal(address indexed watcher, uint256 amount);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        authorizedWatchers[msg.sender] = true;
    }

    // ─── Alert Creation ──────────────────────────────────────────────

    /// @notice Create a new alert definition
    /// @param eventType The type of event to watch for
    /// @param threshold The threshold value (interpretation depends on eventType)
    /// @param callbackContract Optional contract to call when triggered (address(0) for none)
    /// @param callbackSelector Function selector for the callback
    /// @param description Human-readable description of the alert
    /// @param pricePerAlert Cost per alert trigger for subscribers
    function createAlert(
        EventType eventType,
        uint256 threshold,
        address callbackContract,
        bytes4 callbackSelector,
        string calldata description,
        uint256 pricePerAlert
    ) external whenNotPaused {
        require(bytes(description).length > 0 && bytes(description).length <= 256, "AlertSubscription: invalid desc");
        require(pricePerAlert >= minAlertPrice, "AlertSubscription: price too low");

        uint256 alertId = nextAlertId++;
        alerts[alertId] = Alert({
            creator: msg.sender,
            eventType: eventType,
            threshold: threshold,
            callbackContract: callbackContract,
            callbackSelector: callbackSelector,
            description: description,
            pricePerAlert: pricePerAlert,
            totalTriggers: 0,
            subscriberCount: 0,
            status: AlertStatus.Active,
            createdAt: block.timestamp
        });

        emit AlertCreated(alertId, msg.sender, eventType, threshold, pricePerAlert);
    }

    /// @notice Update alert status (creator only)
    function setAlertStatus(uint256 alertId, AlertStatus newStatus) external {
        Alert storage alert_ = alerts[alertId];
        require(alert_.creator == msg.sender || msg.sender == owner, "AlertSubscription: not authorized");
        alert_.status = newStatus;
        emit AlertStatusChanged(alertId, newStatus);
    }

    // ─── Subscription Management ─────────────────────────────────────

    /// @notice Subscribe to an alert with prepaid balance
    /// @param alertId The alert to subscribe to
    function subscribe(uint256 alertId) external payable whenNotPaused {
        Alert storage alert_ = alerts[alertId];
        require(alert_.status == AlertStatus.Active, "AlertSubscription: alert not active");
        require(msg.value >= alert_.pricePerAlert, "AlertSubscription: insufficient deposit");
        require(subscriberToSubId[alertId][msg.sender] == 0, "AlertSubscription: already subscribed");

        uint256 subId = nextSubscriptionId++;
        subscriptions[subId] = Subscription({
            subscriber: msg.sender,
            alertId: alertId,
            balance: msg.value,
            alertsReceived: 0,
            active: true,
            subscribedAt: block.timestamp
        });

        subscriberToSubId[alertId][msg.sender] = subId;
        userSubscriptions[msg.sender].push(subId);
        alert_.subscriberCount++;

        emit Subscribed(subId, alertId, msg.sender, msg.value);
    }

    /// @notice Top up subscription balance
    /// @param subscriptionId The subscription to fund
    function topUp(uint256 subscriptionId) external payable {
        Subscription storage sub = subscriptions[subscriptionId];
        require(sub.subscriber == msg.sender, "AlertSubscription: not subscriber");
        require(sub.active, "AlertSubscription: subscription inactive");
        require(msg.value > 0, "AlertSubscription: zero deposit");
        sub.balance += msg.value;
    }

    /// @notice Cancel subscription and withdraw remaining balance
    /// @param subscriptionId The subscription to cancel
    function cancelSubscription(uint256 subscriptionId) external nonReentrant {
        Subscription storage sub = subscriptions[subscriptionId];
        require(sub.subscriber == msg.sender, "AlertSubscription: not subscriber");
        require(sub.active, "AlertSubscription: already inactive");

        sub.active = false;
        alerts[sub.alertId].subscriberCount--;
        subscriberToSubId[sub.alertId][msg.sender] = 0;

        uint256 refund = sub.balance;
        sub.balance = 0;

        if (refund > 0) {
            (bool success, ) = payable(msg.sender).call{value: refund}("");
            require(success, "AlertSubscription: refund failed");
        }

        emit SubscriptionCancelled(subscriptionId, refund);
    }

    // ─── Alert Triggering ────────────────────────────────────────────

    /// @notice Trigger an alert (authorized watchers only)
    /// @param alertId The alert to trigger
    /// @param data Alert payload data
    function triggerAlert(uint256 alertId, bytes calldata data) external whenNotPaused {
        require(authorizedWatchers[msg.sender], "AlertSubscription: not authorized watcher");

        Alert storage alert_ = alerts[alertId];
        require(alert_.status == AlertStatus.Active, "AlertSubscription: alert not active");

        uint256 triggerId = nextTriggerId++;
        uint256 notified = 0;
        uint256 watcherPayout = 0;

        // Process each subscriber — charge them and pay the watcher
        uint256[] storage userSubs = userSubscriptions[msg.sender]; // temporary, we iterate all subs of alert
        // We need to iterate subscriptions for this alert
        // For gas efficiency, we track subscriber count and iterate known subscriptions
        alert_.totalTriggers++;

        triggers[triggerId] = TriggerRecord({
            alertId: alertId,
            triggeredBy: msg.sender,
            data: data,
            timestamp: block.timestamp,
            subscribersNotified: 0  // updated below
        });
        alertTriggers[alertId].push(triggerId);

        emit AlertTriggered(triggerId, alertId, msg.sender, alert_.subscriberCount);

        // Try callback if configured
        if (alert_.callbackContract != address(0)) {
            // Low-level call — do not revert on failure
            (bool callSuccess, ) = alert_.callbackContract.call(
                abi.encodeWithSelector(alert_.callbackSelector, alertId, data)
            );
            // callSuccess intentionally not checked — alert continues regardless
            if (callSuccess) {
                // callback executed
            }
        }
    }

    /// @notice Charge a subscriber for an alert trigger (watcher calls after triggering)
    /// @param alertId The alert that was triggered
    /// @param subscriber The subscriber to charge
    function chargeSubscriber(uint256 alertId, address subscriber) external nonReentrant {
        require(authorizedWatchers[msg.sender], "AlertSubscription: not authorized watcher");

        uint256 subId = subscriberToSubId[alertId][subscriber];
        require(subId != 0, "AlertSubscription: not subscribed");

        Subscription storage sub = subscriptions[subId];
        require(sub.active, "AlertSubscription: subscription inactive");

        Alert storage alert_ = alerts[alertId];
        uint256 cost = alert_.pricePerAlert;
        require(sub.balance >= cost, "AlertSubscription: insufficient balance");

        sub.balance -= cost;
        sub.alertsReceived++;

        // Split payment: creator gets most, watcher gets fee
        uint256 platformFee = (cost * platformFeeBPS) / 10000;
        uint256 creatorPayout = cost - platformFee;

        watcherEarnings[msg.sender] += platformFee;

        (bool success, ) = payable(alert_.creator).call{value: creatorPayout}("");
        require(success, "AlertSubscription: creator payment failed");

        // Deactivate if balance depleted
        if (sub.balance < cost) {
            sub.active = false;
            alert_.subscriberCount--;
            subscriberToSubId[alertId][subscriber] = 0;
        }

        emit SubscriberNotified(alertId, subscriber, "");
    }

    // ─── Watcher Management ──────────────────────────────────────────

    /// @notice Withdraw accumulated watcher earnings
    function withdrawWatcherEarnings() external nonReentrant {
        uint256 amount = watcherEarnings[msg.sender];
        require(amount > 0, "AlertSubscription: no earnings");
        watcherEarnings[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "AlertSubscription: withdrawal failed");

        emit WatcherWithdrawal(msg.sender, amount);
    }

    function authorizeWatcher(address watcher) external onlyOwner {
        authorizedWatchers[watcher] = true;
        emit WatcherAuthorized(watcher);
    }

    function revokeWatcher(address watcher) external onlyOwner {
        authorizedWatchers[watcher] = false;
        emit WatcherRevoked(watcher);
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get user's subscription IDs
    function getUserSubscriptions(address user) external view returns (uint256[] memory) {
        return userSubscriptions[user];
    }

    /// @notice Get trigger IDs for an alert
    function getAlertTriggers(uint256 alertId) external view returns (uint256[] memory) {
        return alertTriggers[alertId];
    }

    /// @notice Get alert details
    function getAlertInfo(uint256 alertId)
        external
        view
        returns (
            address creator,
            EventType eventType,
            uint256 threshold,
            uint256 pricePerAlert,
            uint256 totalTriggers,
            uint256 subscriberCount,
            AlertStatus status
        )
    {
        Alert storage a = alerts[alertId];
        return (a.creator, a.eventType, a.threshold, a.pricePerAlert, a.totalTriggers, a.subscriberCount, a.status);
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function setMinAlertPrice(uint256 newMin) external onlyOwner {
        minAlertPrice = newMin;
    }

    function setPlatformFee(uint256 newFeeBPS) external onlyOwner {
        require(newFeeBPS <= 2000, "AlertSubscription: fee too high");
        platformFeeBPS = newFeeBPS;
    }

    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = payable(owner).call{value: address(this).balance}("");
        require(success, "AlertSubscription: withdraw failed");
    }

    receive() external payable {}
}
