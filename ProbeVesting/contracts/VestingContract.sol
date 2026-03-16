// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title VestingContract
 * @author ProbeChain
 * @notice Token vesting with linear release and cliff period
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() { _status = _NOT_ENTERED; }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

abstract contract Pausable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function _pause() internal whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function _unpause() internal whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

contract VestingContract is Ownable, ReentrancyGuard, Pausable {
    /// @notice Vesting schedule
    struct VestingSchedule {
        uint256 id;
        address beneficiary;
        uint256 totalAmount;
        uint256 released;
        uint256 startTime;
        uint256 cliffEnd;
        uint256 vestingEnd;
        bool revocable;
        bool revoked;
        address creator;
    }

    /// @dev Schedule counter
    uint256 private _nextScheduleId;

    /// @dev Schedule ID => VestingSchedule
    mapping(uint256 => VestingSchedule) private _schedules;

    /// @dev Beneficiary => schedule IDs
    mapping(address => uint256[]) private _beneficiarySchedules;

    /// @dev All schedule IDs
    uint256[] private _allScheduleIds;

    /// @dev Total vested amount
    uint256 public totalVested;

    /// @dev Total released amount
    uint256 public totalReleased;

    // ───────── Events ─────────

    /// @notice Emitted when a vesting schedule is created
    event VestingScheduleCreated(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount, uint256 cliffDuration, uint256 vestingDuration);

    /// @notice Emitted when tokens are released
    event TokensReleased(uint256 indexed scheduleId, address indexed beneficiary, uint256 amount);

    /// @notice Emitted when a schedule is revoked
    event VestingRevoked(uint256 indexed scheduleId, address indexed revoker, uint256 refunded);

    /// @notice Emitted when PROBE is deposited for vesting
    event Deposited(address indexed sender, uint256 amount);

    // ───────── Constructor ─────────

    constructor() {
        _nextScheduleId = 1;
    }

    /// @notice Receive PROBE deposits
    receive() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    // ───────── Admin ─────────

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Create a vesting schedule for a beneficiary
    /// @param beneficiary The address receiving vested tokens
    /// @param amount Total PROBE amount to vest
    /// @param startTime When vesting starts (unix timestamp)
    /// @param cliffDuration Cliff period in seconds
    /// @param vestingDuration Total vesting period in seconds (includes cliff)
    /// @param revocable Whether the schedule can be revoked
    /// @return scheduleId The new schedule ID
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration,
        bool revocable
    ) external payable whenNotPaused returns (uint256 scheduleId) {
        require(beneficiary != address(0), "Vesting: zero address");
        require(amount > 0, "Vesting: zero amount");
        require(msg.value >= amount, "Vesting: insufficient deposit");
        require(vestingDuration > 0, "Vesting: zero duration");
        require(cliffDuration <= vestingDuration, "Vesting: cliff > vesting");
        require(startTime >= block.timestamp, "Vesting: start in past");

        scheduleId = _nextScheduleId++;

        _schedules[scheduleId] = VestingSchedule({
            id: scheduleId,
            beneficiary: beneficiary,
            totalAmount: amount,
            released: 0,
            startTime: startTime,
            cliffEnd: startTime + cliffDuration,
            vestingEnd: startTime + vestingDuration,
            revocable: revocable,
            revoked: false,
            creator: msg.sender
        });

        _beneficiarySchedules[beneficiary].push(scheduleId);
        _allScheduleIds.push(scheduleId);
        totalVested += amount;

        // Refund excess
        if (msg.value > amount) {
            (bool sent, ) = msg.sender.call{value: msg.value - amount}("");
            require(sent, "Vesting: refund failed");
        }

        emit VestingScheduleCreated(scheduleId, beneficiary, amount, cliffDuration, vestingDuration);
    }

    /// @notice Release vested tokens for a schedule
    /// @param scheduleId The schedule to release from
    function release(uint256 scheduleId) external whenNotPaused nonReentrant {
        VestingSchedule storage s = _schedules[scheduleId];
        require(s.id != 0, "Vesting: not found");
        require(!s.revoked, "Vesting: revoked");
        require(msg.sender == s.beneficiary, "Vesting: not beneficiary");

        uint256 releasable = _computeReleasable(s);
        require(releasable > 0, "Vesting: nothing to release");

        s.released += releasable;
        totalReleased += releasable;

        (bool sent, ) = s.beneficiary.call{value: releasable}("");
        require(sent, "Vesting: transfer failed");

        emit TokensReleased(scheduleId, s.beneficiary, releasable);
    }

    /// @notice Revoke a vesting schedule (creator/owner only)
    /// @param scheduleId The schedule to revoke
    function revoke(uint256 scheduleId) external whenNotPaused nonReentrant {
        VestingSchedule storage s = _schedules[scheduleId];
        require(s.id != 0, "Vesting: not found");
        require(s.revocable, "Vesting: not revocable");
        require(!s.revoked, "Vesting: already revoked");
        require(msg.sender == s.creator || msg.sender == owner(), "Vesting: not authorized");

        // Release any vested amount to beneficiary first
        uint256 releasable = _computeReleasable(s);
        if (releasable > 0) {
            s.released += releasable;
            totalReleased += releasable;
            (bool sent1, ) = s.beneficiary.call{value: releasable}("");
            require(sent1, "Vesting: release failed");
            emit TokensReleased(scheduleId, s.beneficiary, releasable);
        }

        s.revoked = true;

        // Refund unvested to creator
        uint256 refund = s.totalAmount - s.released;
        if (refund > 0) {
            totalVested -= refund;
            (bool sent2, ) = s.creator.call{value: refund}("");
            require(sent2, "Vesting: refund failed");
        }

        emit VestingRevoked(scheduleId, msg.sender, refund);
    }

    // ───────── Internal ─────────

    /// @dev Compute releasable amount for a schedule
    function _computeReleasable(VestingSchedule memory s) internal view returns (uint256) {
        uint256 vested = _computeVested(s);
        return vested - s.released;
    }

    /// @dev Compute total vested amount for a schedule
    function _computeVested(VestingSchedule memory s) internal view returns (uint256) {
        if (block.timestamp < s.cliffEnd) {
            return 0;
        }
        if (block.timestamp >= s.vestingEnd) {
            return s.totalAmount;
        }
        // Linear vesting between cliff end and vesting end
        uint256 elapsed = block.timestamp - s.startTime;
        uint256 duration = s.vestingEnd - s.startTime;
        return (s.totalAmount * elapsed) / duration;
    }

    // ───────── View Functions ─────────

    /// @notice Get schedule details
    function getSchedule(uint256 scheduleId) external view returns (VestingSchedule memory) {
        require(_schedules[scheduleId].id != 0, "Vesting: not found");
        return _schedules[scheduleId];
    }

    /// @notice Get releasable amount
    function getReleasable(uint256 scheduleId) external view returns (uint256) {
        VestingSchedule memory s = _schedules[scheduleId];
        if (s.id == 0 || s.revoked) return 0;
        return _computeReleasable(s);
    }

    /// @notice Get vested amount
    function getVested(uint256 scheduleId) external view returns (uint256) {
        VestingSchedule memory s = _schedules[scheduleId];
        if (s.id == 0) return 0;
        return _computeVested(s);
    }

    /// @notice Get schedules for a beneficiary
    function getBeneficiarySchedules(address beneficiary) external view returns (uint256[] memory) {
        return _beneficiarySchedules[beneficiary];
    }

    /// @notice Total schedules created
    function totalSchedules() external view returns (uint256) {
        return _nextScheduleId - 1;
    }

    /// @notice Get contract balance
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
