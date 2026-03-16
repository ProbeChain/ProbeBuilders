// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title AirdropDistributor
 * @author ProbeBuilders
 * @notice Smart airdrop distribution using Merkle tree proofs for gas efficiency
 * @dev Supports multiple concurrent airdrops, expiry-based clawback, and claim tracking
 */

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

abstract contract Ownable {
    address private _owner;
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert OwnableInvalidOwner(address(0));
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    modifier onlyOwner() {
        if (msg.sender != _owner) revert OwnableUnauthorizedAccount(msg.sender);
        _;
    }

    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert OwnableInvalidOwner(address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardReentrantCall();
    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardReentrantCall();
        _status = 2;
        _;
        _status = 1;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error EnforcedPause();
    modifier whenNotPaused() { if (_paused) revert EnforcedPause(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
}

/// @title AirdropDistributor — Merkle tree based airdrop distribution
contract AirdropDistributor is Ownable, ReentrancyGuard, Pausable {

    /// @notice Airdrop campaign
    struct Airdrop {
        address creator;
        address token;
        bytes32 merkleRoot;
        uint256 totalAmount;
        uint256 claimedAmount;
        uint64 expiry;
        uint64 createdAt;
        bool clawedBack;
        string description;
    }

    uint256 public nextAirdropId = 1;
    uint256 public totalAirdrops;
    uint256 public totalClaimed;

    mapping(uint256 => Airdrop) public airdrops;
    /// @notice airdropId => claimer => claimed
    mapping(uint256 => mapping(address => bool)) public hasClaimed;
    /// @notice airdropId => claimer => amount claimed
    mapping(uint256 => mapping(address => uint256)) public claimedAmounts;
    /// @notice creator => airdropIds
    mapping(address => uint256[]) public creatorAirdrops;

    event AirdropCreated(
        uint256 indexed airdropId,
        address indexed creator,
        address indexed token,
        uint256 totalAmount,
        bytes32 merkleRoot,
        uint64 expiry
    );
    event Claimed(uint256 indexed airdropId, address indexed claimer, uint256 amount);
    event Clawback(uint256 indexed airdropId, address indexed creator, uint256 remainingAmount);
    event MerkleRootUpdated(uint256 indexed airdropId, bytes32 newMerkleRoot);

    error AirdropNotFound();
    error AirdropExpired();
    error AirdropNotExpired();
    error AlreadyClaimed();
    error InvalidProof();
    error InvalidAmount();
    error InsufficientAllowance();
    error TransferFailed();
    error NotAirdropCreator();
    error AlreadyClawedBack();
    error ZeroAddress();

    constructor() Ownable(msg.sender) {}

    /// @notice Create a new airdrop campaign
    /// @param token ERC-20 token to airdrop
    /// @param merkleRoot Merkle root of the distribution tree
    /// @param totalAmount Total tokens to distribute
    /// @param expiry Expiration timestamp (after which creator can clawback)
    /// @param description Human-readable description
    /// @return airdropId Created airdrop ID
    function createAirdrop(
        address token,
        bytes32 merkleRoot,
        uint256 totalAmount,
        uint64 expiry,
        string calldata description
    ) external whenNotPaused returns (uint256 airdropId) {
        if (token == address(0)) revert ZeroAddress();
        if (totalAmount == 0) revert InvalidAmount();
        require(expiry > block.timestamp, "Expiry must be in future");
        require(merkleRoot != bytes32(0), "Invalid merkle root");

        // Transfer tokens from creator to this contract
        bool success = IERC20(token).transferFrom(msg.sender, address(this), totalAmount);
        if (!success) revert TransferFailed();

        airdropId = nextAirdropId++;
        airdrops[airdropId] = Airdrop({
            creator: msg.sender,
            token: token,
            merkleRoot: merkleRoot,
            totalAmount: totalAmount,
            claimedAmount: 0,
            expiry: expiry,
            createdAt: uint64(block.timestamp),
            clawedBack: false,
            description: description
        });

        creatorAirdrops[msg.sender].push(airdropId);
        totalAirdrops++;

        emit AirdropCreated(airdropId, msg.sender, token, totalAmount, merkleRoot, expiry);
    }

    /// @notice Claim airdrop tokens with Merkle proof
    /// @param airdropId Airdrop to claim from
    /// @param amount Amount to claim
    /// @param merkleProof Array of proof hashes
    function claim(
        uint256 airdropId,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external whenNotPaused nonReentrant {
        Airdrop storage a = airdrops[airdropId];
        if (a.creator == address(0)) revert AirdropNotFound();
        if (block.timestamp > a.expiry) revert AirdropExpired();
        if (hasClaimed[airdropId][msg.sender]) revert AlreadyClaimed();
        if (a.clawedBack) revert AlreadyClawedBack();
        if (amount == 0) revert InvalidAmount();

        // Verify Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        if (!_verifyProof(merkleProof, a.merkleRoot, leaf)) revert InvalidProof();

        // Check sufficient remaining
        require(a.claimedAmount + amount <= a.totalAmount, "Exceeds total");

        hasClaimed[airdropId][msg.sender] = true;
        claimedAmounts[airdropId][msg.sender] = amount;
        a.claimedAmount += amount;
        totalClaimed += amount;

        bool success = IERC20(a.token).transfer(msg.sender, amount);
        if (!success) revert TransferFailed();

        emit Claimed(airdropId, msg.sender, amount);
    }

    /// @notice Clawback unclaimed tokens after expiry
    /// @param airdropId Airdrop to clawback
    function clawback(uint256 airdropId) external nonReentrant {
        Airdrop storage a = airdrops[airdropId];
        if (a.creator != msg.sender) revert NotAirdropCreator();
        if (block.timestamp <= a.expiry) revert AirdropNotExpired();
        if (a.clawedBack) revert AlreadyClawedBack();

        a.clawedBack = true;
        uint256 remaining = a.totalAmount - a.claimedAmount;

        if (remaining > 0) {
            bool success = IERC20(a.token).transfer(msg.sender, remaining);
            if (!success) revert TransferFailed();
        }

        emit Clawback(airdropId, msg.sender, remaining);
    }

    /// @notice Update merkle root (before anyone claims, creator only)
    /// @param airdropId Airdrop ID
    /// @param newMerkleRoot New Merkle root
    function updateMerkleRoot(uint256 airdropId, bytes32 newMerkleRoot) external {
        Airdrop storage a = airdrops[airdropId];
        if (a.creator != msg.sender) revert NotAirdropCreator();
        require(a.claimedAmount == 0, "Already has claims");
        require(newMerkleRoot != bytes32(0), "Invalid root");

        a.merkleRoot = newMerkleRoot;
        emit MerkleRootUpdated(airdropId, newMerkleRoot);
    }

    /// @notice Verify a Merkle proof
    /// @param proof Array of sibling hashes
    /// @param root Merkle root
    /// @param leaf Leaf hash to verify
    /// @return True if proof is valid
    function _verifyProof(
        bytes32[] calldata proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computedHash <= proofElement) {
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash == root;
    }

    /// @notice Public Merkle proof verification
    /// @param airdropId Airdrop ID
    /// @param account Account to verify
    /// @param amount Amount to verify
    /// @param proof Merkle proof
    /// @return valid True if proof is valid
    function verifyProof(
        uint256 airdropId,
        address account,
        uint256 amount,
        bytes32[] calldata proof
    ) external view returns (bool valid) {
        bytes32 leaf = keccak256(abi.encodePacked(account, amount));
        return _verifyProof(proof, airdrops[airdropId].merkleRoot, leaf);
    }

    /// @notice Get airdrop status
    /// @param airdropId Airdrop to query
    /// @return remaining Unclaimed tokens
    /// @return expired Whether airdrop has expired
    /// @return claimedPct Percentage claimed (basis points)
    function getAirdropStatus(uint256 airdropId)
        external
        view
        returns (uint256 remaining, bool expired, uint256 claimedPct)
    {
        Airdrop storage a = airdrops[airdropId];
        remaining = a.totalAmount - a.claimedAmount;
        expired = block.timestamp > a.expiry;
        claimedPct = a.totalAmount > 0 ? (a.claimedAmount * 10000) / a.totalAmount : 0;
    }

    /// @notice Check if address has claimed
    function hasAddressClaimed(uint256 airdropId, address account) external view returns (bool) {
        return hasClaimed[airdropId][account];
    }

    /// @notice Get creator's airdrop IDs
    function getCreatorAirdrops(address creator) external view returns (uint256[] memory) {
        return creatorAirdrops[creator];
    }

    /// @notice Emergency token recovery (owner only, for stuck tokens)
    function emergencyRecover(address token, uint256 amount) external onlyOwner nonReentrant {
        bool success = IERC20(token).transfer(owner(), amount);
        if (!success) revert TransferFailed();
    }
}
