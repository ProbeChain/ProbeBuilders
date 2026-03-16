// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DynamicAvatar
 * @author ProbeChain Rydberg Testnet
 * @notice ERC-721 dynamic avatar NFTs that evolve based on on-chain activity and XP
 * @dev Mint avatars with seed, feed XP, evolve when thresholds met, traits change dynamically
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

// ---------- Minimal ERC-721 ----------
abstract contract ERC721 {
    string public name;
    string public symbol;
    mapping(uint256 => address) internal _owners;
    mapping(address => uint256) internal _balances;
    mapping(uint256 => address) internal _tokenApprovals;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    constructor(string memory _name, string memory _symbol) { name = _name; symbol = _symbol; }
    function balanceOf(address o) public view returns (uint256) { return _balances[o]; }
    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _owners[tokenId]; require(o != address(0), "ERC721: nonexistent"); return o;
    }
    function approve(address to, uint256 tokenId) public {
        address o = ownerOf(tokenId);
        require(msg.sender == o || _operatorApprovals[o][msg.sender], "Not authorized");
        _tokenApprovals[tokenId] = to; emit Approval(o, to, tokenId);
    }
    function setApprovalForAll(address op, bool a) public {
        _operatorApprovals[msg.sender][op] = a; emit ApprovalForAll(msg.sender, op, a);
    }
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not authorized");
        _transfer(from, to, tokenId);
    }
    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0) && _owners[tokenId] == address(0), "Invalid mint");
        _balances[to]++; _owners[tokenId] = to; emit Transfer(address(0), to, tokenId);
    }
    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from && to != address(0), "Invalid transfer");
        _tokenApprovals[tokenId] = address(0); _balances[from]--; _balances[to]++;
        _owners[tokenId] = to; emit Transfer(from, to, tokenId);
    }
    function _isApprovedOrOwner(address s, uint256 t) internal view returns (bool) {
        address o = ownerOf(t);
        return (s == o || _tokenApprovals[t] == s || _operatorApprovals[o][s]);
    }
}

contract DynamicAvatar is ERC721, Ownable, ReentrancyGuard, Pausable {
    // ---------- Enums ----------
    enum ActivityType { Trading, Staking, Governance, Social, Gaming, Building, Exploring }
    enum EvolutionStage { Egg, Hatchling, Juvenile, Adult, Elder, Legendary }

    // ---------- Structs ----------
    struct AvatarTraits {
        uint256 strength;
        uint256 intelligence;
        uint256 agility;
        uint256 charisma;
        uint256 endurance;
        uint256 luck;
    }

    struct Avatar {
        uint256 id;
        address creator;
        bytes32 seed;
        EvolutionStage stage;
        uint256 totalXP;
        AvatarTraits traits;
        uint256 mintedAt;
        uint256 lastEvolution;
        uint256 activityCount;
    }

    // ---------- State ----------
    uint256 public nextAvatarId;
    uint256 public mintPrice;
    uint256 public maxSupply;
    uint256 public totalMinted;

    mapping(uint256 => Avatar) public avatars;
    mapping(address => uint256[]) public ownerAvatars;
    mapping(address => bool) public authorizedFeeders;

    // XP thresholds for evolution
    uint256[6] public evolutionThresholds;
    // XP per activity type
    mapping(ActivityType => uint256) public activityXP;

    // ---------- Events ----------
    /// @notice Emitted when a new avatar is minted
    event AvatarMinted(uint256 indexed avatarId, address indexed creator, bytes32 seed, EvolutionStage stage);
    /// @notice Emitted when an avatar gains experience
    event ExperienceFed(uint256 indexed avatarId, ActivityType activityType, uint256 xpGained, uint256 totalXP);
    /// @notice Emitted when an avatar evolves to the next stage
    event AvatarEvolved(uint256 indexed avatarId, EvolutionStage previousStage, EvolutionStage newStage);
    /// @notice Emitted when avatar traits are updated
    event TraitsUpdated(uint256 indexed avatarId, uint256 strength, uint256 intelligence, uint256 agility);

    // ---------- Constructor ----------
    constructor(uint256 _mintPrice, uint256 _maxSupply)
        ERC721("ProbeDynamicAvatar", "PAVT")
        Ownable() ReentrancyGuard() Pausable()
    {
        mintPrice = _mintPrice;
        maxSupply = _maxSupply;
        nextAvatarId = 1;

        // XP thresholds: Egg→Hatchling, Hatchling→Juvenile, etc.
        evolutionThresholds[0] = 0;
        evolutionThresholds[1] = 100;
        evolutionThresholds[2] = 500;
        evolutionThresholds[3] = 2000;
        evolutionThresholds[4] = 10000;
        evolutionThresholds[5] = 50000;

        // Default XP per activity
        activityXP[ActivityType.Trading] = 10;
        activityXP[ActivityType.Staking] = 15;
        activityXP[ActivityType.Governance] = 20;
        activityXP[ActivityType.Social] = 5;
        activityXP[ActivityType.Gaming] = 12;
        activityXP[ActivityType.Building] = 25;
        activityXP[ActivityType.Exploring] = 8;
    }

    /**
     * @notice Authorize an address to feed XP to avatars
     * @param feeder Address to authorize
     */
    function authorizeFeeder(address feeder) external onlyOwner {
        require(feeder != address(0), "Zero address");
        authorizedFeeders[feeder] = true;
    }

    /**
     * @notice Revoke feeder authorization
     * @param feeder Address to revoke
     */
    function revokeFeeder(address feeder) external onlyOwner {
        authorizedFeeders[feeder] = false;
    }

    /**
     * @notice Mint a new avatar NFT
     * @param seed Random seed determining initial traits
     * @return avatarId The minted avatar ID
     */
    function mintAvatar(bytes32 seed) external payable nonReentrant whenNotPaused returns (uint256 avatarId) {
        require(totalMinted < maxSupply, "Max supply reached");
        require(msg.value >= mintPrice, "Insufficient payment");
        require(seed != bytes32(0), "Empty seed");

        avatarId = nextAvatarId++;
        totalMinted++;

        Avatar storage a = avatars[avatarId];
        a.id = avatarId;
        a.creator = msg.sender;
        a.seed = seed;
        a.stage = EvolutionStage.Egg;
        a.mintedAt = block.timestamp;

        // Generate initial traits from seed
        a.traits = _generateTraits(seed, EvolutionStage.Egg);

        _mint(msg.sender, avatarId);
        ownerAvatars[msg.sender].push(avatarId);

        emit AvatarMinted(avatarId, msg.sender, seed, EvolutionStage.Egg);
    }

    /**
     * @notice Feed experience to an avatar based on activity
     * @param avatarId The avatar to feed XP
     * @param activityType The type of activity performed
     * @param amount Multiplier for XP (1 = base, higher for more activity)
     */
    function feedExperience(uint256 avatarId, ActivityType activityType, uint256 amount)
        external
        whenNotPaused
    {
        require(
            authorizedFeeders[msg.sender] || msg.sender == owner() || ownerOf(avatarId) == msg.sender,
            "Not authorized"
        );
        require(amount > 0 && amount <= 100, "Invalid amount");

        Avatar storage a = avatars[avatarId];
        require(a.id != 0, "Avatar does not exist");

        uint256 xpGain = activityXP[activityType] * amount;
        a.totalXP += xpGain;
        a.activityCount++;

        // Update traits based on activity
        _updateTraitsFromActivity(avatarId, activityType, xpGain);

        emit ExperienceFed(avatarId, activityType, xpGain, a.totalXP);
    }

    /**
     * @notice Evolve an avatar when XP threshold is met
     * @param avatarId The avatar to evolve
     */
    function evolveAvatar(uint256 avatarId) external whenNotPaused {
        require(ownerOf(avatarId) == msg.sender, "Not avatar owner");
        Avatar storage a = avatars[avatarId];
        require(uint256(a.stage) < uint256(EvolutionStage.Legendary), "Already max evolution");

        uint256 nextStageIdx = uint256(a.stage) + 1;
        require(a.totalXP >= evolutionThresholds[nextStageIdx], "Insufficient XP for evolution");

        EvolutionStage prevStage = a.stage;
        a.stage = EvolutionStage(nextStageIdx);
        a.lastEvolution = block.timestamp;

        // Regenerate traits for new stage
        a.traits = _generateTraits(a.seed, a.stage);

        emit AvatarEvolved(avatarId, prevStage, a.stage);
    }

    /**
     * @notice Get avatar traits
     * @param avatarId The avatar to query
     * @return traits The current trait values
     */
    function getAvatarTraits(uint256 avatarId) external view returns (AvatarTraits memory traits) {
        require(avatars[avatarId].id != 0, "Avatar does not exist");
        return avatars[avatarId].traits;
    }

    /**
     * @notice Get full avatar info
     * @param avatarId The avatar to query
     * @return stage Current evolution stage
     * @return totalXP Total accumulated XP
     * @return traits Current traits
     * @return activityCount Total activities
     */
    function getAvatarInfo(uint256 avatarId)
        external view
        returns (EvolutionStage stage, uint256 totalXP, AvatarTraits memory traits, uint256 activityCount)
    {
        Avatar storage a = avatars[avatarId];
        require(a.id != 0, "Avatar does not exist");
        return (a.stage, a.totalXP, a.traits, a.activityCount);
    }

    // ---------- Internal ----------
    function _generateTraits(bytes32 seed, EvolutionStage stage) internal pure returns (AvatarTraits memory t) {
        uint256 stageMultiplier = uint256(stage) + 1;
        uint256 h = uint256(keccak256(abi.encodePacked(seed, stage)));
        t.strength = ((h % 100) + 1) * stageMultiplier;
        t.intelligence = (((h >> 16) % 100) + 1) * stageMultiplier;
        t.agility = (((h >> 32) % 100) + 1) * stageMultiplier;
        t.charisma = (((h >> 48) % 100) + 1) * stageMultiplier;
        t.endurance = (((h >> 64) % 100) + 1) * stageMultiplier;
        t.luck = (((h >> 80) % 100) + 1) * stageMultiplier;
    }

    function _updateTraitsFromActivity(uint256 avatarId, ActivityType activityType, uint256 xpGain) internal {
        Avatar storage a = avatars[avatarId];
        uint256 boost = xpGain / 10;
        if (boost == 0) boost = 1;

        if (activityType == ActivityType.Trading) a.traits.intelligence += boost;
        else if (activityType == ActivityType.Staking) a.traits.endurance += boost;
        else if (activityType == ActivityType.Governance) a.traits.charisma += boost;
        else if (activityType == ActivityType.Social) a.traits.charisma += boost;
        else if (activityType == ActivityType.Gaming) a.traits.agility += boost;
        else if (activityType == ActivityType.Building) a.traits.strength += boost;
        else if (activityType == ActivityType.Exploring) a.traits.luck += boost;

        emit TraitsUpdated(avatarId, a.traits.strength, a.traits.intelligence, a.traits.agility);
    }

    // ---------- View/Admin ----------
    function getOwnerAvatars(address o) external view returns (uint256[] memory) {
        return ownerAvatars[o];
    }

    function setMintPrice(uint256 _price) external onlyOwner { mintPrice = _price; }
    function setActivityXP(ActivityType at, uint256 xp) external onlyOwner { activityXP[at] = xp; }

    function withdrawFunds() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "No balance");
        (bool ok, ) = owner().call{value: bal}("");
        require(ok, "Withdraw failed");
    }
}
