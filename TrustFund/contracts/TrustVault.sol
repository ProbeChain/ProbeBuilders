// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title TrustVault
 * @author ProbeChain Labs
 * @notice Conditional trust fund contract — create trusts with time-locked
 *         releases, multiple trustees, and revocation before release.
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
contract TrustVault is Ownable, ReentrancyGuard, Pausable {

    enum TrustStatus { Active, Released, Revoked }

    struct Trust {
        uint256 id;
        address grantor;
        address beneficiary;
        uint256 amount;
        string releaseCondition;   // human-readable condition description
        uint256 releaseTime;       // earliest unix timestamp for release
        TrustStatus status;
        uint256 createdAt;
        uint256 releasedAt;
    }

    uint256 private _nextTrustId;
    mapping(uint256 => Trust) public trusts;
    mapping(uint256 => mapping(address => bool)) public trustees;
    mapping(uint256 => address[]) public trustTrustees;
    mapping(address => uint256[]) public grantorTrusts;
    mapping(address => uint256[]) public beneficiaryTrusts;

    // ---- Events ----------------------------------------------------------
    event TrustCreated(uint256 indexed trustId, address indexed grantor, address indexed beneficiary, uint256 amount, uint256 releaseTime, string releaseCondition);
    event FundsReleased(uint256 indexed trustId, address indexed beneficiary, uint256 amount);
    event TrustRevoked(uint256 indexed trustId, address indexed grantor, uint256 amountReturned);
    event TrusteeAdded(uint256 indexed trustId, address indexed trustee);
    event TrusteeRemoved(uint256 indexed trustId, address indexed trustee);

    constructor() {
        _nextTrustId = 1;
    }

    // ---- Core Functions --------------------------------------------------

    /**
     * @notice Create a new trust fund. Sends native PROBE as the trust amount.
     * @param beneficiary      Recipient of the trust funds.
     * @param releaseCondition Human-readable description of the release condition.
     * @param releaseTime      Earliest unix timestamp when funds can be released.
     * @return trustId         The new trust identifier.
     */
    function createTrust(
        address beneficiary,
        string calldata releaseCondition,
        uint256 releaseTime
    ) external payable whenNotPaused returns (uint256 trustId) {
        require(beneficiary != address(0), "Zero beneficiary");
        require(beneficiary != msg.sender, "Cannot be own beneficiary");
        require(msg.value > 0, "Zero amount");
        require(releaseTime > block.timestamp, "Release time must be future");
        require(bytes(releaseCondition).length > 0, "Empty condition");

        trustId = _nextTrustId++;
        trusts[trustId] = Trust({
            id: trustId,
            grantor: msg.sender,
            beneficiary: beneficiary,
            amount: msg.value,
            releaseCondition: releaseCondition,
            releaseTime: releaseTime,
            status: TrustStatus.Active,
            createdAt: block.timestamp,
            releasedAt: 0
        });

        // Grantor is automatically a trustee
        trustees[trustId][msg.sender] = true;
        trustTrustees[trustId].push(msg.sender);

        grantorTrusts[msg.sender].push(trustId);
        beneficiaryTrusts[beneficiary].push(trustId);

        emit TrustCreated(trustId, msg.sender, beneficiary, msg.value, releaseTime, releaseCondition);
    }

    /**
     * @notice Release funds to the beneficiary when conditions are met.
     * @param trustId The trust to release.
     */
    function releaseFunds(uint256 trustId) external nonReentrant whenNotPaused {
        Trust storage t = trusts[trustId];
        require(t.id != 0, "Trust not found");
        require(t.status == TrustStatus.Active, "Trust not active");
        require(block.timestamp >= t.releaseTime, "Release time not reached");
        require(
            trustees[trustId][msg.sender] || msg.sender == t.beneficiary,
            "Not authorized"
        );

        t.status = TrustStatus.Released;
        t.releasedAt = block.timestamp;

        (bool success, ) = payable(t.beneficiary).call{value: t.amount}("");
        require(success, "Transfer failed");

        emit FundsReleased(trustId, t.beneficiary, t.amount);
    }

    /**
     * @notice Add a trustee who can authorize release.
     * @param trustId The trust to modify.
     * @param trustee The new trustee address.
     */
    function addTrustee(uint256 trustId, address trustee) external whenNotPaused {
        Trust storage t = trusts[trustId];
        require(t.id != 0, "Trust not found");
        require(t.status == TrustStatus.Active, "Trust not active");
        require(msg.sender == t.grantor, "Not grantor");
        require(trustee != address(0), "Zero address");
        require(!trustees[trustId][trustee], "Already a trustee");

        trustees[trustId][trustee] = true;
        trustTrustees[trustId].push(trustee);

        emit TrusteeAdded(trustId, trustee);
    }

    /**
     * @notice Remove a trustee (grantor cannot remove themselves).
     * @param trustId The trust to modify.
     * @param trustee The trustee to remove.
     */
    function removeTrustee(uint256 trustId, address trustee) external whenNotPaused {
        Trust storage t = trusts[trustId];
        require(t.id != 0 && t.status == TrustStatus.Active, "Invalid trust");
        require(msg.sender == t.grantor, "Not grantor");
        require(trustee != t.grantor, "Cannot remove grantor");
        require(trustees[trustId][trustee], "Not a trustee");

        trustees[trustId][trustee] = false;
        emit TrusteeRemoved(trustId, trustee);
    }

    /**
     * @notice Revoke a trust before it is released. Funds return to grantor.
     * @param trustId The trust to revoke.
     */
    function revokeTrust(uint256 trustId) external nonReentrant whenNotPaused {
        Trust storage t = trusts[trustId];
        require(t.id != 0, "Trust not found");
        require(t.status == TrustStatus.Active, "Trust not active");
        require(msg.sender == t.grantor, "Not grantor");

        t.status = TrustStatus.Revoked;
        uint256 amount = t.amount;

        (bool success, ) = payable(t.grantor).call{value: amount}("");
        require(success, "Refund failed");

        emit TrustRevoked(trustId, t.grantor, amount);
    }

    // ---- Views -----------------------------------------------------------

    function getTrust(uint256 trustId) external view returns (Trust memory) {
        require(trusts[trustId].id != 0, "Not found");
        return trusts[trustId];
    }

    function getTrustTrustees(uint256 trustId) external view returns (address[] memory) {
        return trustTrustees[trustId];
    }

    function getGrantorTrustIds(address grantor) external view returns (uint256[] memory) {
        return grantorTrusts[grantor];
    }

    function getBeneficiaryTrustIds(address beneficiary) external view returns (uint256[] memory) {
        return beneficiaryTrusts[beneficiary];
    }

    function totalTrusts() external view returns (uint256) {
        return _nextTrustId - 1;
    }

    function isTrustee(uint256 trustId, address account) external view returns (bool) {
        return trustees[trustId][account];
    }
}
