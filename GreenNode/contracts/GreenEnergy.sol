// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title GreenEnergy
 * @author ProbeChain
 * @notice Green energy verification and credit system on ProbeChain Rydberg Testnet
 * @dev Tracks renewable energy sources, auditor verification, and tradeable green credits
 */
contract GreenEnergy {
    // ─── Ownable ────────────────────────────────────────────────────────
    address private _owner;
    modifier onlyOwner() { require(msg.sender == _owner, "Not owner"); _; }
    event OwnershipTransferred(address indexed prev, address indexed next_);
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // ─── Pausable ───────────────────────────────────────────────────────
    bool private _paused;
    modifier whenNotPaused() { require(!_paused, "Paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
    event Paused(address account);
    event Unpaused(address account);

    // ─── Enums & Structs ────────────────────────────────────────────────
    enum EnergyType { Solar, Wind, Hydro, Biomass, Geothermal }

    struct EnergySource {
        address sourceOwner;
        EnergyType energyType;
        string location;
        bytes32 certHash;
        bool verified;
        uint256 totalCredits;
        uint256 registeredAt;
    }

    struct GreenCredit {
        uint256 sourceId;
        address holder;
        uint256 amount;
        bool redeemed;
        uint256 mintedAt;
    }

    // ─── State ──────────────────────────────────────────────────────────
    mapping(uint256 => EnergySource) public sources;
    mapping(uint256 => GreenCredit) public credits;
    mapping(address => uint256) public creditBalance;
    mapping(address => bool) public auditors;
    uint256 public nextSourceId;
    uint256 public nextCreditId;
    uint256 public totalCreditsIssued;
    uint256 public totalCreditsRedeemed;

    // ─── Events ─────────────────────────────────────────────────────────
    event SourceRegistered(uint256 indexed sourceId, address indexed sourceOwner, EnergyType energyType);
    event CertificateVerified(uint256 indexed sourceId, address indexed auditor);
    event CreditsMinted(uint256 indexed creditId, uint256 indexed sourceId, uint256 amount);
    event CreditsRedeemed(uint256 indexed creditId, address indexed redeemer, uint256 amount);
    event CreditsTransferred(address indexed from, address indexed to, uint256 amount);
    event AuditorUpdated(address indexed auditor, bool status);

    // ─── Constructor ────────────────────────────────────────────────────
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    // ─── Admin ──────────────────────────────────────────────────────────
    function setAuditor(address auditor, bool status) external onlyOwner {
        auditors[auditor] = status;
        emit AuditorUpdated(auditor, status);
    }

    // ─── Core Functions ─────────────────────────────────────────────────
    /**
     * @notice Register a green energy source
     * @param energyType Type of renewable energy
     * @param location Human-readable location
     * @param certHash Hash of the energy certificate document
     */
    function registerSource(
        EnergyType energyType,
        string calldata location,
        bytes32 certHash
    ) external whenNotPaused returns (uint256) {
        require(bytes(location).length > 0, "Empty location");
        require(certHash != bytes32(0), "Empty cert hash");

        uint256 id = nextSourceId++;
        sources[id] = EnergySource({
            sourceOwner: msg.sender,
            energyType: energyType,
            location: location,
            certHash: certHash,
            verified: false,
            totalCredits: 0,
            registeredAt: block.timestamp
        });

        emit SourceRegistered(id, msg.sender, energyType);
        return id;
    }

    /**
     * @notice Verify a source's certificate (auditor only)
     * @param sourceId The source to verify
     */
    function verifyCertificate(uint256 sourceId) external whenNotPaused {
        require(auditors[msg.sender], "Not auditor");
        EnergySource storage s = sources[sourceId];
        require(s.registeredAt != 0, "Source not found");
        require(!s.verified, "Already verified");

        s.verified = true;
        emit CertificateVerified(sourceId, msg.sender);
    }

    /**
     * @notice Mint green credits for verified energy generation
     * @param sourceId The verified source
     * @param kwhGenerated Amount of kWh generated
     */
    function mintGreenCredits(uint256 sourceId, uint256 kwhGenerated) external whenNotPaused returns (uint256) {
        EnergySource storage s = sources[sourceId];
        require(msg.sender == s.sourceOwner, "Not source owner");
        require(s.verified, "Not verified");
        require(kwhGenerated > 0, "Zero generation");

        uint256 creditId = nextCreditId++;
        credits[creditId] = GreenCredit({
            sourceId: sourceId,
            holder: msg.sender,
            amount: kwhGenerated,
            redeemed: false,
            mintedAt: block.timestamp
        });

        s.totalCredits += kwhGenerated;
        creditBalance[msg.sender] += kwhGenerated;
        totalCreditsIssued += kwhGenerated;

        emit CreditsMinted(creditId, sourceId, kwhGenerated);
        return creditId;
    }

    /**
     * @notice Redeem green credits
     * @param creditId The credit to redeem
     */
    function redeemCredits(uint256 creditId) external whenNotPaused {
        GreenCredit storage c = credits[creditId];
        require(c.holder == msg.sender, "Not credit holder");
        require(!c.redeemed, "Already redeemed");

        c.redeemed = true;
        creditBalance[msg.sender] -= c.amount;
        totalCreditsRedeemed += c.amount;

        emit CreditsRedeemed(creditId, msg.sender, c.amount);
    }

    /**
     * @notice Transfer green credits to another address
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function transferCredits(address to, uint256 amount) external whenNotPaused {
        require(to != address(0), "Zero address");
        require(creditBalance[msg.sender] >= amount, "Insufficient balance");

        creditBalance[msg.sender] -= amount;
        creditBalance[to] += amount;

        emit CreditsTransferred(msg.sender, to, amount);
    }
}
