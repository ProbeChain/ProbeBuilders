// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title LandRegistry
 * @author ProbeChain Builders
 * @notice Virtual land registry with 2D coordinate grid, building system, and ERC-721 plots
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004, EVM London)
 */

// ──────────────────────────────────────────────────────────────
// Inline Ownable
// ──────────────────────────────────────────────────────────────
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed prev, address indexed next_);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address n) external onlyOwner {
        require(n != address(0), "Ownable: zero");
        emit OwnershipTransferred(_owner, n);
        _owner = n;
    }
}

// ──────────────────────────────────────────────────────────────
// Inline ReentrancyGuard
// ──────────────────────────────────────────────────────────────
abstract contract ReentrancyGuard {
    uint256 private _s = 1;
    modifier nonReentrant() { require(_s == 1, "ReentrancyGuard: reentrant"); _s = 2; _; _s = 1; }
}

// ──────────────────────────────────────────────────────────────
// Inline Pausable
// ──────────────────────────────────────────────────────────────
abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner { _paused = false; emit Unpaused(msg.sender); }
}

// ──────────────────────────────────────────────────────────────
// Minimal ERC-721 Implementation
// ──────────────────────────────────────────────────────────────
abstract contract ERC721Minimal {
    string public name;
    string public symbol;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _approvals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner_, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner_, address indexed operator, bool approved);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function balanceOf(address o) public view returns (uint256) {
        require(o != address(0), "ERC721: zero");
        return _balances[o];
    }

    function ownerOf(uint256 id) public view returns (address) {
        address o = _owners[id];
        require(o != address(0), "ERC721: nonexistent");
        return o;
    }

    function approve(address to, uint256 id) external {
        address o = ownerOf(id);
        require(msg.sender == o || _operatorApprovals[o][msg.sender], "ERC721: not authorized");
        _approvals[id] = to;
        emit Approval(o, to, id);
    }

    function setApprovalForAll(address op, bool ok) external {
        _operatorApprovals[msg.sender][op] = ok;
        emit ApprovalForAll(msg.sender, op, ok);
    }

    function getApproved(uint256 id) public view returns (address) { return _approvals[id]; }
    function isApprovedForAll(address o, address op) public view returns (bool) { return _operatorApprovals[o][op]; }

    function transferFrom(address from, address to, uint256 id) public {
        require(_isApprovedOrOwner(msg.sender, id), "ERC721: not authorized");
        _transfer(from, to, id);
    }

    function _mint(address to, uint256 id) internal {
        require(to != address(0), "ERC721: mint to zero");
        require(_owners[id] == address(0), "ERC721: already minted");
        _balances[to]++;
        _owners[id] = to;
        emit Transfer(address(0), to, id);
    }

    function _transfer(address from, address to, uint256 id) internal {
        require(ownerOf(id) == from, "ERC721: wrong owner");
        require(to != address(0), "ERC721: zero");
        _approvals[id] = address(0);
        _balances[from]--;
        _balances[to]++;
        _owners[id] = to;
        emit Transfer(from, to, id);
    }

    function _isApprovedOrOwner(address spender, uint256 id) internal view returns (bool) {
        address o = ownerOf(id);
        return (spender == o || _approvals[id] == spender || _operatorApprovals[o][spender]);
    }

    function _exists(uint256 id) internal view returns (bool) { return _owners[id] != address(0); }
}

// ──────────────────────────────────────────────────────────────
// LandRegistry
// ──────────────────────────────────────────────────────────────
contract LandRegistry is ERC721Minimal, Ownable, ReentrancyGuard, Pausable {

    enum BuildingType { None, Residential, Commercial, Industrial, Park, Special }

    struct Plot {
        int128 x;
        int128 y;
        uint256 size;        // 1 = 1x1, 2 = 2x2, etc.
        BuildingType buildingType;
        bytes32 buildingDataHash;
        uint256 mintedAt;
    }

    // ── State ────────────────────────────────────────────────
    uint256 public plotCounter;
    uint256 public mintFee;

    mapping(uint256 => Plot) public plots;
    /// @dev coordinate hash => plotId (0 = empty)
    mapping(bytes32 => uint256) public coordinateToPlot;

    // ── Events ───────────────────────────────────────────────
    event PlotMinted(uint256 indexed plotId, address indexed owner_, int128 x, int128 y, uint256 size);
    event PlotTransferred(uint256 indexed plotId, address indexed from, address indexed to);
    event BuildingPlaced(uint256 indexed plotId, BuildingType buildingType, bytes32 dataHash);
    event MintFeeUpdated(uint256 oldFee, uint256 newFee);

    // ── Constructor ──────────────────────────────────────────
    constructor(uint256 _mintFee) ERC721Minimal("ProbeWorld Land", "PWLAND") {
        mintFee = _mintFee;
    }

    // ── Core Functions ───────────────────────────────────────

    /**
     * @notice Mint a new plot at coordinates (x, y) with given size
     * @param x X-coordinate on the 2D grid
     * @param y Y-coordinate on the 2D grid
     * @param size Plot size (1 = 1x1, 2 = 2x2, etc.)
     * @return plotId The minted plot ID
     */
    function mintPlot(int128 x, int128 y, uint256 size)
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 plotId)
    {
        require(size >= 1 && size <= 10, "LandRegistry: invalid size");
        require(msg.value >= mintFee * size, "LandRegistry: insufficient fee");

        // Check all cells in the size x size area are free
        for (int128 dx = 0; dx < int128(int256(size)); dx++) {
            for (int128 dy = 0; dy < int128(int256(size)); dy++) {
                bytes32 coordHash = keccak256(abi.encodePacked(x + dx, y + dy));
                require(coordinateToPlot[coordHash] == 0, "LandRegistry: cell occupied");
            }
        }

        plotId = ++plotCounter;
        plots[plotId] = Plot({
            x: x,
            y: y,
            size: size,
            buildingType: BuildingType.None,
            buildingDataHash: bytes32(0),
            mintedAt: block.timestamp
        });

        // Mark all cells as occupied
        for (int128 dx = 0; dx < int128(int256(size)); dx++) {
            for (int128 dy = 0; dy < int128(int256(size)); dy++) {
                bytes32 coordHash = keccak256(abi.encodePacked(x + dx, y + dy));
                coordinateToPlot[coordHash] = plotId;
            }
        }

        _mint(msg.sender, plotId);
        emit PlotMinted(plotId, msg.sender, x, y, size);
    }

    /**
     * @notice Transfer a plot to another address
     * @param to Recipient address
     * @param plotId The plot token ID
     */
    function transferPlot(address to, uint256 plotId) external whenNotPaused {
        transferFrom(msg.sender, to, plotId);
        emit PlotTransferred(plotId, msg.sender, to);
    }

    /**
     * @notice Build on a plot you own
     * @param plotId The plot to build on
     * @param buildingType Type of building to place
     * @param dataHash IPFS hash of building data/metadata
     */
    function buildOnPlot(uint256 plotId, BuildingType buildingType, bytes32 dataHash)
        external
        whenNotPaused
    {
        require(_exists(plotId), "LandRegistry: plot does not exist");
        require(ownerOf(plotId) == msg.sender, "LandRegistry: not plot owner");
        require(buildingType != BuildingType.None, "LandRegistry: invalid building type");

        plots[plotId].buildingType = buildingType;
        plots[plotId].buildingDataHash = dataHash;

        emit BuildingPlaced(plotId, buildingType, dataHash);
    }

    /**
     * @notice Get full info of a plot
     * @param plotId The plot ID
     */
    function getPlotInfo(uint256 plotId)
        external
        view
        returns (
            address plotOwner,
            int128 x,
            int128 y,
            uint256 size,
            BuildingType buildingType,
            bytes32 buildingDataHash,
            uint256 mintedAt
        )
    {
        require(_exists(plotId), "LandRegistry: nonexistent");
        Plot storage p = plots[plotId];
        plotOwner = ownerOf(plotId);
        x = p.x;
        y = p.y;
        size = p.size;
        buildingType = p.buildingType;
        buildingDataHash = p.buildingDataHash;
        mintedAt = p.mintedAt;
    }

    /**
     * @notice Get neighboring plot IDs (4-directional) for a plot
     * @param plotId The plot to check neighbors for
     * @return neighborIds Array of neighboring plot IDs (0 = no neighbor)
     */
    function getNeighbors(uint256 plotId) external view returns (uint256[4] memory neighborIds) {
        require(_exists(plotId), "LandRegistry: nonexistent");
        Plot storage p = plots[plotId];

        // North, East, South, West
        int128[4] memory dxs = [int128(0), int128(int256(p.size)), int128(0), int128(-1)];
        int128[4] memory dys = [int128(int256(p.size)), int128(0), int128(-1), int128(0)];

        for (uint256 i = 0; i < 4; i++) {
            bytes32 coordHash = keccak256(abi.encodePacked(p.x + dxs[i], p.y + dys[i]));
            neighborIds[i] = coordinateToPlot[coordHash];
        }
    }

    // ── Admin ────────────────────────────────────────────────

    function setMintFee(uint256 _fee) external onlyOwner {
        emit MintFeeUpdated(mintFee, _fee);
        mintFee = _fee;
    }

    function withdraw() external onlyOwner nonReentrant {
        (bool sent,) = owner().call{value: address(this).balance}("");
        require(sent, "LandRegistry: withdraw failed");
    }
}
