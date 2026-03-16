// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title LootForge
 * @notice Procedural game item generation as ERC-721 NFTs with randomized attributes
 * @dev Uses block hash + seed for on-chain pseudo-random attribute generation
 */
contract LootForge {
    // ──────────────────── Ownership ────────────────────
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ──────────────────── Pausable ────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "Paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ──────────────────── ERC-721 Core ────────────────────
    string public name = "LootForge Items";
    string public symbol = "LOOT";
    uint256 public totalSupply;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _approvals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ──────────────────── Item Data ────────────────────
    enum Rarity { Common, Rare, Epic, Legendary }

    struct Item {
        uint16 attack;
        uint16 defense;
        uint16 speed;
        uint16 luck;
        Rarity rarity;
        uint256 seed;
        uint256 mintedAt;
        bool equipped;
    }

    mapping(uint256 => Item) public items;
    mapping(address => uint256) public equippedItem;
    uint256 public mintPrice = 0.01 ether;
    uint256 public maxSupply = 10000;

    event ItemMinted(uint256 indexed tokenId, address indexed to, Rarity rarity, uint16 attack, uint16 defense, uint16 speed, uint16 luck);
    event ItemEquipped(uint256 indexed tokenId, address indexed player);
    event ItemUnequipped(uint256 indexed tokenId, address indexed player);
    event MintPriceUpdated(uint256 newPrice);

    constructor() {
        owner = msg.sender;
    }

    // ──────────────────── ERC-721 Implementation ────────────────────

    function balanceOf(address _addr) external view returns (uint256) {
        require(_addr != address(0), "Zero address");
        return _balances[_addr];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "Nonexistent token");
        return o;
    }

    function approve(address to, uint256 tokenId) external {
        address tokenOwner = ownerOf(tokenId);
        require(msg.sender == tokenOwner || _operatorApprovals[tokenOwner][msg.sender], "Not authorized");
        _approvals[tokenId] = to;
        emit Approval(tokenOwner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(_owners[tokenId] != address(0), "Nonexistent token");
        return _approvals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address _owner, address operator) public view returns (bool) {
        return _operatorApprovals[_owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public whenNotPaused {
        require(to != address(0), "Zero address");
        address tokenOwner = ownerOf(tokenId);
        require(from == tokenOwner, "Not token owner");
        require(
            msg.sender == tokenOwner ||
            getApproved(tokenId) == msg.sender ||
            isApprovedForAll(tokenOwner, msg.sender),
            "Not authorized"
        );

        // Unequip if equipped
        if (items[tokenId].equipped) {
            items[tokenId].equipped = false;
            equippedItem[from] = 0;
            emit ItemUnequipped(tokenId, from);
        }

        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;
        delete _approvals[tokenId];

        emit Transfer(from, to, tokenId);
    }

    // ──────────────────── Minting ────────────────────

    /**
     * @notice Mint a new procedurally generated item
     * @param seed User-provided seed for randomness
     * @return tokenId The ID of the minted item
     */
    function mintItem(uint256 seed) external payable whenNotPaused returns (uint256) {
        require(msg.value >= mintPrice, "Insufficient payment");
        require(totalSupply < maxSupply, "Max supply reached");

        uint256 tokenId = ++totalSupply;
        uint256 entropy = uint256(keccak256(abi.encodePacked(
            blockhash(block.number - 1),
            seed,
            msg.sender,
            tokenId,
            block.timestamp
        )));

        // Generate attributes from entropy
        uint16 attack = uint16((entropy % 100) + 1);
        entropy = entropy >> 16;
        uint16 defense = uint16((entropy % 100) + 1);
        entropy = entropy >> 16;
        uint16 speed = uint16((entropy % 100) + 1);
        entropy = entropy >> 16;
        uint16 luck = uint16((entropy % 100) + 1);
        entropy = entropy >> 16;

        // Determine rarity from total stats
        uint256 totalStats = uint256(attack) + uint256(defense) + uint256(speed) + uint256(luck);
        Rarity rarity;
        if (totalStats >= 340) {
            rarity = Rarity.Legendary; // ~2.5% chance
        } else if (totalStats >= 280) {
            rarity = Rarity.Epic;      // ~12% chance
        } else if (totalStats >= 220) {
            rarity = Rarity.Rare;      // ~30% chance
        } else {
            rarity = Rarity.Common;    // ~55% chance
        }

        // Legendary items get a stat boost
        if (rarity == Rarity.Legendary) {
            attack = attack > 80 ? 100 : attack + 20;
            defense = defense > 80 ? 100 : defense + 20;
        }

        items[tokenId] = Item({
            attack: attack,
            defense: defense,
            speed: speed,
            luck: luck,
            rarity: rarity,
            seed: seed,
            mintedAt: block.timestamp,
            equipped: false
        });

        _owners[tokenId] = msg.sender;
        _balances[msg.sender]++;

        emit Transfer(address(0), msg.sender, tokenId);
        emit ItemMinted(tokenId, msg.sender, rarity, attack, defense, speed, luck);

        return tokenId;
    }

    // ──────────────────── Equip System ────────────────────

    /**
     * @notice Equip an item (one item per player)
     */
    function equipItem(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not your item");
        require(!items[tokenId].equipped, "Already equipped");

        // Unequip current if any
        uint256 current = equippedItem[msg.sender];
        if (current != 0) {
            items[current].equipped = false;
            emit ItemUnequipped(current, msg.sender);
        }

        items[tokenId].equipped = true;
        equippedItem[msg.sender] = tokenId;
        emit ItemEquipped(tokenId, msg.sender);
    }

    /**
     * @notice Unequip current item
     */
    function unequipItem(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Not your item");
        require(items[tokenId].equipped, "Not equipped");

        items[tokenId].equipped = false;
        equippedItem[msg.sender] = 0;
        emit ItemUnequipped(tokenId, msg.sender);
    }

    /**
     * @notice Get item attributes
     */
    function getItem(uint256 tokenId) external view returns (Item memory) {
        require(_owners[tokenId] != address(0), "Nonexistent token");
        return items[tokenId];
    }

    // ──────────────────── Admin ────────────────────

    function setMintPrice(uint256 newPrice) external onlyOwner {
        mintPrice = newPrice;
        emit MintPriceUpdated(newPrice);
    }

    function withdraw() external onlyOwner {
        (bool ok, ) = owner.call{value: address(this).balance}("");
        require(ok, "Withdraw failed");
    }

    /**
     * @dev ERC-165 interface detection
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd || // ERC-721
               interfaceId == 0x01ffc9a7;   // ERC-165
    }

    receive() external payable {}
}
