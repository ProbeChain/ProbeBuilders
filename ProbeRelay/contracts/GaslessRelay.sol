// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GaslessRelay
 * @author ProbeChain Team
 * @notice Meta-transaction relay for gasless user experience with EIP-712 signatures
 * @dev Relayers stake tokens, execute signed transactions, and earn relay fees
 */
contract GaslessRelay {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "GaslessRelay: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "GaslessRelay: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── ReentrancyGuard ────────────────────────────────────────────────
    uint256 private _guardStatus = 1;
    modifier nonReentrant() {
        require(_guardStatus == 1, "GaslessRelay: reentrant call");
        _guardStatus = 2;
        _;
        _guardStatus = 1;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "GaslessRelay: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── EIP-712 ────────────────────────────────────────────────────────
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant RELAY_TYPEHASH = keccak256(
        "RelayRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)"
    );

    // ─── Structs ────────────────────────────────────────────────────────
    struct Relayer {
        address wallet;
        uint256 stake;
        uint256 totalRelayed;
        uint256 earnings;
        uint256 pendingEarnings;
        uint256 registeredAt;
        bool active;
    }

    struct RelayRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
    }

    struct RelayRecord {
        uint256 id;
        address from;
        address to;
        address relayer;
        uint256 value;
        bool success;
        uint256 gasUsed;
        uint256 timestamp;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public relayerCount;
    uint256 public relayCount;
    uint256 public minStake = 0.1 ether;
    uint256 public relayFee = 0.001 ether;

    mapping(address => Relayer) public relayers;
    mapping(address => uint256) public nonces;
    mapping(uint256 => RelayRecord) public relayRecords;
    mapping(address => uint256[]) public userRelays;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when a relayer registers with stake
    event RelayerRegistered(address indexed relayer, uint256 stake);
    /// @notice Emitted when a meta-transaction is relayed
    event TransactionRelayed(uint256 indexed relayId, address indexed from, address indexed to, bool success, uint256 gasUsed);
    /// @notice Emitted when a relayer withdraws earnings
    event EarningsWithdrawn(address indexed relayer, uint256 amount);
    /// @notice Emitted when a relayer withdraws stake
    event StakeWithdrawn(address indexed relayer, uint256 amount);
    /// @notice Emitted when relay fee is updated
    event RelayFeeUpdated(uint256 newFee);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);

        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("GaslessRelay"),
            keccak256("1"),
            block.chainid,
            address(this)
        ));
    }

    /// @notice Accept native token deposits for relay value
    receive() external payable {}

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register as a relayer with a stake
     */
    function registerRelayer() external payable whenNotPaused {
        require(msg.value >= minStake, "GaslessRelay: insufficient stake");
        require(relayers[msg.sender].registeredAt == 0, "GaslessRelay: already registered");

        relayerCount++;
        relayers[msg.sender] = Relayer({
            wallet: msg.sender,
            stake: msg.value,
            totalRelayed: 0,
            earnings: 0,
            pendingEarnings: 0,
            registeredAt: block.timestamp,
            active: true
        });

        emit RelayerRegistered(msg.sender, msg.value);
    }

    /**
     * @notice Add more stake
     */
    function addStake() external payable {
        require(msg.value > 0, "GaslessRelay: zero stake");
        require(relayers[msg.sender].active, "GaslessRelay: not active relayer");
        relayers[msg.sender].stake += msg.value;
    }

    /**
     * @notice Relay a meta-transaction on behalf of the user
     * @param from Original sender
     * @param to Target contract
     * @param value ETH value to forward
     * @param gasLimit Gas limit for the call
     * @param data Calldata to forward
     * @param signature EIP-712 signature from the original sender
     */
    function relay(
        address from,
        address to,
        uint256 value,
        uint256 gasLimit,
        bytes calldata data,
        bytes calldata signature
    ) external whenNotPaused nonReentrant {
        Relayer storage r = relayers[msg.sender];
        require(r.active, "GaslessRelay: not active relayer");

        // Verify EIP-712 signature
        uint256 currentNonce = nonces[from];
        bytes32 structHash = keccak256(abi.encode(
            RELAY_TYPEHASH,
            from,
            to,
            value,
            gasLimit,
            currentNonce,
            keccak256(data)
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        address signer = _recoverSigner(digest, signature);
        require(signer == from, "GaslessRelay: invalid signature");

        nonces[from] = currentNonce + 1;

        // Execute the relayed call
        uint256 gasBefore = gasleft();
        (bool success, ) = to.call{value: value, gas: gasLimit}(data);
        uint256 gasUsed = gasBefore - gasleft();

        relayCount++;
        relayRecords[relayCount] = RelayRecord({
            id: relayCount,
            from: from,
            to: to,
            relayer: msg.sender,
            value: value,
            success: success,
            gasUsed: gasUsed,
            timestamp: block.timestamp
        });

        r.totalRelayed++;
        r.pendingEarnings += relayFee;
        userRelays[from].push(relayCount);

        emit TransactionRelayed(relayCount, from, to, success, gasUsed);
    }

    /**
     * @notice Withdraw accumulated relay earnings
     */
    function withdrawRelayerEarnings() external nonReentrant {
        Relayer storage r = relayers[msg.sender];
        require(r.pendingEarnings > 0, "GaslessRelay: no earnings");

        uint256 amount = r.pendingEarnings;
        r.pendingEarnings = 0;
        r.earnings += amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "GaslessRelay: withdrawal failed");

        emit EarningsWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Withdraw relayer stake (deactivates the relayer)
     */
    function withdrawStake() external nonReentrant {
        Relayer storage r = relayers[msg.sender];
        require(r.active, "GaslessRelay: not active");

        r.active = false;
        uint256 amount = r.stake;
        r.stake = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "GaslessRelay: withdrawal failed");

        emit StakeWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Update relay fee
     * @param newFee New fee amount
     */
    function setRelayFee(uint256 newFee) external onlyOwner {
        relayFee = newFee;
        emit RelayFeeUpdated(newFee);
    }

    /**
     * @notice Update minimum stake
     * @param newMinStake New minimum stake
     */
    function setMinStake(uint256 newMinStake) external onlyOwner {
        minStake = newMinStake;
    }

    /**
     * @notice Get user's nonce
     * @param user User address
     * @return nonce Current nonce
     */
    function getNonce(address user) external view returns (uint256 nonce) {
        return nonces[user];
    }

    // ─── Internal ───────────────────────────────────────────────────────
    /**
     * @dev Recover signer from ECDSA signature
     * @param digest Message digest
     * @param signature Packed signature (r, s, v)
     * @return signer Recovered address
     */
    function _recoverSigner(bytes32 digest, bytes calldata signature) internal pure returns (address signer) {
        require(signature.length == 65, "GaslessRelay: invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) v += 27;
        require(v == 27 || v == 28, "GaslessRelay: invalid v value");

        signer = ecrecover(digest, v, r, s);
        require(signer != address(0), "GaslessRelay: invalid signer");
    }
}
