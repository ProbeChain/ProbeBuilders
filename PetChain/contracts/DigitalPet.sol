// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title DigitalPet
 * @author ProbeBuilders
 * @notice ERC-721 digital pet with feeding, training, evolution, and time-based stat decay
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */
contract DigitalPet {
    // ─── ERC-721 Core ────────────────────────────────────────────────
    string public constant name = "PetChain Digital Pet";
    string public constant symbol = "DPET";

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address o) public view returns (uint256) { return _balances[o]; }
    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _owners[tokenId];
        require(o != address(0), "DigitalPet: nonexistent token");
        return o;
    }
    function approve(address to, uint256 tokenId) external {
        address o = ownerOf(tokenId);
        require(msg.sender == o || _operatorApprovals[o][msg.sender], "DigitalPet: not authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(o, to, tokenId);
    }
    function getApproved(uint256 tokenId) public view returns (address) { return _tokenApprovals[tokenId]; }
    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    function isApprovedForAll(address o, address op) public view returns (bool) { return _operatorApprovals[o][op]; }
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "DigitalPet: not authorized");
        _transfer(from, to, tokenId);
    }
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address o = ownerOf(tokenId);
        return (spender == o || getApproved(tokenId) == spender || isApprovedForAll(o, spender));
    }
    function _mint(address to, uint256 tokenId) internal {
        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }
    function _transfer(address from, address to, uint256 tokenId) internal {
        require(ownerOf(tokenId) == from, "DigitalPet: wrong owner");
        require(to != address(0), "DigitalPet: zero address");
        delete _tokenApprovals[tokenId];
        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    // ─── Ownership ───────────────────────────────────────────────────
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "DigitalPet: not owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "DigitalPet: zero address");
        owner = newOwner;
    }

    // ─── Pausable ────────────────────────────────────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "DigitalPet: paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ─── Reentrancy Guard ────────────────────────────────────────────
    uint256 private _status = 1;
    modifier nonReentrant() { require(_status != 2, "DigitalPet: reentrant"); _status = 2; _; _status = 1; }

    // ─── Pet Data ────────────────────────────────────────────────────
    enum Species { Cat, Dog, Dragon, Phoenix, Unicorn }
    enum Skill { Speed, Power, Wisdom, Endurance }

    struct Pet {
        string petName;
        Species species;
        uint256 hunger;       // 0-100, 100 = starving
        uint256 happiness;    // 0-100, 100 = ecstatic
        uint256 xp;
        uint256 level;
        uint256 evolutionStage; // 0=baby, 1=juvenile, 2=adult, 3=mythic
        uint256 lastFed;
        uint256 lastTrained;
        uint256 bornAt;
        uint256[4] skills;    // Speed, Power, Wisdom, Endurance
    }

    uint256 public nextPetId = 1;
    uint256 public adoptionFee = 0.001 ether;
    uint256 public constant DECAY_INTERVAL = 1 hours;
    uint256 public constant XP_PER_LEVEL = 50;
    uint256 public constant EVOLUTION_LEVEL_1 = 5;
    uint256 public constant EVOLUTION_LEVEL_2 = 15;
    uint256 public constant EVOLUTION_LEVEL_3 = 30;

    mapping(uint256 => Pet) public pets;

    // ─── Events ──────────────────────────────────────────────────────
    event PetAdopted(uint256 indexed petId, address indexed owner, Species species, string petName);
    event PetFed(uint256 indexed petId, uint256 newHunger, uint256 newHappiness);
    event PetTrained(uint256 indexed petId, Skill skill, uint256 xpGained);
    event PetEvolved(uint256 indexed petId, uint256 newStage, uint256 level);
    event AdoptionFeeUpdated(uint256 newFee);

    // ─── Constructor ─────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
    }

    // ─── Core Functions ──────────────────────────────────────────────

    /// @notice Adopt a new digital pet
    /// @param species The species of pet (0-4)
    /// @param petName Name for the pet
    function adoptPet(Species species, string calldata petName) external payable whenNotPaused {
        require(msg.value >= adoptionFee, "DigitalPet: insufficient fee");
        require(bytes(petName).length > 0 && bytes(petName).length <= 32, "DigitalPet: invalid name");

        uint256 petId = nextPetId++;
        uint256[4] memory baseSkills;
        if (species == Species.Cat)     { baseSkills = [uint256(10), 5, 8, 5]; }
        else if (species == Species.Dog)     { baseSkills = [uint256(8), 8, 5, 10]; }
        else if (species == Species.Dragon)  { baseSkills = [uint256(6), 12, 6, 8]; }
        else if (species == Species.Phoenix) { baseSkills = [uint256(10), 8, 10, 5]; }
        else                                 { baseSkills = [uint256(8), 6, 10, 8]; }

        pets[petId] = Pet({
            petName: petName,
            species: species,
            hunger: 50,
            happiness: 50,
            xp: 0,
            level: 1,
            evolutionStage: 0,
            lastFed: block.timestamp,
            lastTrained: block.timestamp,
            bornAt: block.timestamp,
            skills: baseSkills
        });

        _mint(msg.sender, petId);
        emit PetAdopted(petId, msg.sender, species, petName);
    }

    /// @notice Feed a pet to reduce hunger and increase happiness
    /// @param petId The pet to feed
    function feedPet(uint256 petId) external whenNotPaused {
        require(ownerOf(petId) == msg.sender, "DigitalPet: not pet owner");
        Pet storage pet = pets[petId];

        _applyDecay(pet);

        if (pet.hunger > 30) {
            pet.hunger -= 30;
        } else {
            pet.hunger = 0;
        }
        pet.happiness = pet.happiness + 15 > 100 ? 100 : pet.happiness + 15;
        pet.lastFed = block.timestamp;

        emit PetFed(petId, pet.hunger, pet.happiness);
    }

    /// @notice Train a pet in a specific skill
    /// @param petId The pet to train
    /// @param skill The skill to train (0=Speed,1=Power,2=Wisdom,3=Endurance)
    function trainPet(uint256 petId, Skill skill) external whenNotPaused {
        require(ownerOf(petId) == msg.sender, "DigitalPet: not pet owner");
        Pet storage pet = pets[petId];

        _applyDecay(pet);

        require(pet.hunger < 80, "DigitalPet: too hungry to train");
        require(pet.happiness > 20, "DigitalPet: too unhappy to train");
        require(block.timestamp >= pet.lastTrained + 5 minutes, "DigitalPet: training cooldown");

        uint256 skillIdx = uint256(skill);
        uint256 xpGain = 10 + (pet.evolutionStage * 5);
        pet.skills[skillIdx] += 1 + pet.evolutionStage;
        pet.xp += xpGain;
        pet.hunger = pet.hunger + 10 > 100 ? 100 : pet.hunger + 10;
        pet.happiness = pet.happiness > 5 ? pet.happiness - 5 : 0;
        pet.lastTrained = block.timestamp;

        // Level up check
        uint256 newLevel = (pet.xp / XP_PER_LEVEL) + 1;
        if (newLevel > pet.level) {
            pet.level = newLevel;
        }

        emit PetTrained(petId, skill, xpGain);
    }

    /// @notice Evolve a pet when level conditions are met
    /// @param petId The pet to evolve
    function evolvePet(uint256 petId) external whenNotPaused {
        require(ownerOf(petId) == msg.sender, "DigitalPet: not pet owner");
        Pet storage pet = pets[petId];

        _applyDecay(pet);

        uint256 currentStage = pet.evolutionStage;
        require(currentStage < 3, "DigitalPet: max evolution reached");

        uint256 requiredLevel;
        if (currentStage == 0) requiredLevel = EVOLUTION_LEVEL_1;
        else if (currentStage == 1) requiredLevel = EVOLUTION_LEVEL_2;
        else requiredLevel = EVOLUTION_LEVEL_3;

        require(pet.level >= requiredLevel, "DigitalPet: level too low to evolve");
        require(pet.happiness >= 40, "DigitalPet: happiness too low to evolve");

        pet.evolutionStage = currentStage + 1;

        // Boost all skills on evolution
        for (uint256 i = 0; i < 4; i++) {
            pet.skills[i] += 5 * (currentStage + 1);
        }

        emit PetEvolved(petId, pet.evolutionStage, pet.level);
    }

    // ─── Internal ────────────────────────────────────────────────────

    /// @dev Apply time-based hunger increase and happiness decrease
    function _applyDecay(Pet storage pet) internal {
        uint256 elapsed = block.timestamp - pet.lastFed;
        uint256 decayPeriods = elapsed / DECAY_INTERVAL;
        if (decayPeriods > 0) {
            uint256 hungerIncrease = decayPeriods * 5;
            pet.hunger = pet.hunger + hungerIncrease > 100 ? 100 : pet.hunger + hungerIncrease;
            uint256 happinessDecrease = decayPeriods * 3;
            pet.happiness = pet.happiness > happinessDecrease ? pet.happiness - happinessDecrease : 0;
        }
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get full pet stats with live decay applied
    function getPetStats(uint256 petId)
        external
        view
        returns (
            string memory petName,
            Species species,
            uint256 hunger,
            uint256 happiness,
            uint256 level,
            uint256 evolutionStage,
            uint256[4] memory skills
        )
    {
        Pet storage pet = pets[petId];
        uint256 elapsed = block.timestamp - pet.lastFed;
        uint256 decayPeriods = elapsed / DECAY_INTERVAL;
        uint256 liveHunger = pet.hunger + (decayPeriods * 5);
        if (liveHunger > 100) liveHunger = 100;
        uint256 happinessDrop = decayPeriods * 3;
        uint256 liveHappiness = pet.happiness > happinessDrop ? pet.happiness - happinessDrop : 0;

        return (pet.petName, pet.species, liveHunger, liveHappiness, pet.level, pet.evolutionStage, pet.skills);
    }

    // ─── Admin ───────────────────────────────────────────────────────

    /// @notice Update adoption fee
    function setAdoptionFee(uint256 newFee) external onlyOwner {
        adoptionFee = newFee;
        emit AdoptionFeeUpdated(newFee);
    }

    /// @notice Withdraw collected fees
    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = payable(owner).call{value: address(this).balance}("");
        require(success, "DigitalPet: withdraw failed");
    }

    receive() external payable {}
}
