// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ABIRegistry
 * @author ProbeChain Team
 * @notice On-chain ABI verification and discovery registry
 * @dev Allows registering, verifying, and looking up contract ABIs by address
 */
contract ABIRegistry {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() {
        require(msg.sender == _owner, "ABIRegistry: caller is not owner");
        _;
    }
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ABIRegistry: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "ABIRegistry: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Structs ────────────────────────────────────────────────────────
    struct ABIEntry {
        address contractAddr;
        bytes32 abiHash;
        string contractName;
        address registrant;
        uint256 registeredAt;
        uint256 verificationCount;
        bool verified;
    }

    struct ABIVersion {
        bytes32 abiHash;
        string contractName;
        uint256 timestamp;
    }

    // ─── State ──────────────────────────────────────────────────────────
    uint256 public entryCount;
    mapping(address => ABIEntry) public abiEntries;
    mapping(address => ABIVersion[]) public abiHistory;
    mapping(address => mapping(address => bool)) public hasVerified;
    mapping(string => address[]) public nameToContracts;
    address[] public registeredContracts;
    mapping(address => bool) public trustedVerifiers;

    // ─── Events ─────────────────────────────────────────────────────────
    /// @notice Emitted when an ABI is registered
    event ABIRegistered(address indexed contractAddr, bytes32 abiHash, string contractName, address indexed registrant);
    /// @notice Emitted when an ABI is updated
    event ABIUpdated(address indexed contractAddr, bytes32 newAbiHash, string contractName);
    /// @notice Emitted when an ABI verification occurs
    event ABIVerified(address indexed contractAddr, bytes32 abiHash, bool matches, address indexed verifier);
    /// @notice Emitted when a contract is marked as officially verified
    event ContractVerified(address indexed contractAddr, address indexed verifier);
    /// @notice Emitted when a trusted verifier is set
    event TrustedVerifierSet(address indexed verifier, bool status);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Verifier Management ────────────────────────────────────────────
    /**
     * @notice Set or revoke trusted verifier status
     * @param verifier Address of the verifier
     * @param status Trust status
     */
    function setTrustedVerifier(address verifier, bool status) external onlyOwner {
        trustedVerifiers[verifier] = status;
        emit TrustedVerifierSet(verifier, status);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register an ABI for a contract address
     * @param contractAddr The contract address
     * @param abiHash Hash of the ABI JSON
     * @param contractName Human-readable contract name
     */
    function registerABI(
        address contractAddr,
        bytes32 abiHash,
        string calldata contractName
    ) external whenNotPaused {
        require(contractAddr != address(0), "ABIRegistry: zero address");
        require(abiHash != bytes32(0), "ABIRegistry: empty hash");
        require(bytes(contractName).length > 0 && bytes(contractName).length <= 64, "ABIRegistry: invalid name");

        if (abiEntries[contractAddr].registeredAt == 0) {
            // New entry
            entryCount++;
            abiEntries[contractAddr] = ABIEntry({
                contractAddr: contractAddr,
                abiHash: abiHash,
                contractName: contractName,
                registrant: msg.sender,
                registeredAt: block.timestamp,
                verificationCount: 0,
                verified: false
            });

            registeredContracts.push(contractAddr);
            nameToContracts[contractName].push(contractAddr);

            emit ABIRegistered(contractAddr, abiHash, contractName, msg.sender);
        } else {
            // Update existing
            ABIEntry storage entry = abiEntries[contractAddr];
            require(
                msg.sender == entry.registrant || msg.sender == _owner,
                "ABIRegistry: not registrant"
            );

            abiHistory[contractAddr].push(ABIVersion({
                abiHash: entry.abiHash,
                contractName: entry.contractName,
                timestamp: block.timestamp
            }));

            entry.abiHash = abiHash;
            entry.contractName = contractName;
            entry.verified = false;
            entry.verificationCount = 0;

            emit ABIUpdated(contractAddr, abiHash, contractName);
        }
    }

    /**
     * @notice Verify an ABI hash against the registered one
     * @param contractAddr Contract to check
     * @param abiHash Hash to verify
     * @return matches True if the hash matches the registered ABI
     */
    function verifyABI(
        address contractAddr,
        bytes32 abiHash
    ) external returns (bool matches) {
        ABIEntry storage entry = abiEntries[contractAddr];
        require(entry.registeredAt > 0, "ABIRegistry: not registered");

        matches = entry.abiHash == abiHash;

        if (matches && !hasVerified[contractAddr][msg.sender]) {
            hasVerified[contractAddr][msg.sender] = true;
            entry.verificationCount++;

            if (trustedVerifiers[msg.sender] && !entry.verified) {
                entry.verified = true;
                emit ContractVerified(contractAddr, msg.sender);
            }
        }

        emit ABIVerified(contractAddr, abiHash, matches, msg.sender);
    }

    /**
     * @notice Get the ABI entry for a contract
     * @param contractAddr Contract address to look up
     * @return abiHash The registered ABI hash
     * @return contractName The contract name
     * @return registrant Who registered it
     * @return verified Whether it has been verified by a trusted verifier
     * @return verificationCount Number of verifications
     */
    function getABI(address contractAddr) external view returns (
        bytes32 abiHash,
        string memory contractName,
        address registrant,
        bool verified,
        uint256 verificationCount
    ) {
        ABIEntry storage entry = abiEntries[contractAddr];
        require(entry.registeredAt > 0, "ABIRegistry: not registered");
        return (entry.abiHash, entry.contractName, entry.registrant, entry.verified, entry.verificationCount);
    }

    /**
     * @notice Get contracts by name
     * @param contractName Name to search for
     * @return addrs Array of contract addresses
     */
    function getContractsByName(string calldata contractName) external view returns (address[] memory addrs) {
        return nameToContracts[contractName];
    }

    /**
     * @notice Get ABI history for a contract
     * @param contractAddr Contract address
     * @return versions Array of historical ABI versions
     */
    function getABIHistory(address contractAddr) external view returns (ABIVersion[] memory versions) {
        return abiHistory[contractAddr];
    }

    /**
     * @notice Get total registered contracts count
     * @return count Number of registered contracts
     */
    function getRegisteredCount() external view returns (uint256 count) {
        return registeredContracts.length;
    }
}
