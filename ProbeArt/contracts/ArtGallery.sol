// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ArtGallery
 * @author ProbeBuilders
 * @notice AI art gallery with curator consensus for featuring and direct purchases
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */
contract ArtGallery {
    // ─── Ownership ───────────────────────────────────────────────────
    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "ArtGallery: not owner"); _; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ArtGallery: zero address");
        owner = newOwner;
    }

    // ─── Pausable ────────────────────────────────────────────────────
    bool public paused;
    modifier whenNotPaused() { require(!paused, "ArtGallery: paused"); _; }
    function pause() external onlyOwner { paused = true; }
    function unpause() external onlyOwner { paused = false; }

    // ─── Reentrancy Guard ────────────────────────────────────────────
    uint256 private _status = 1;
    modifier nonReentrant() { require(_status != 2, "ArtGallery: reentrant"); _status = 2; _; _status = 1; }

    // ─── Structs ─────────────────────────────────────────────────────

    /// @notice An artwork submission
    struct Artwork {
        address artist;
        bytes32 artHash;         // content hash for verification
        string metadataURI;      // IPFS or HTTP URI for metadata
        uint256 price;           // sale price (0 = not for sale)
        uint256 totalScore;      // sum of curator scores
        uint256 curatorCount;    // number of curators who scored
        bool featured;           // featured in gallery
        bool sold;
        address buyer;
        uint256 submittedAt;
    }

    /// @notice Curator profile
    struct Curator {
        bool active;
        uint256 artworksReviewed;
        uint256 addedAt;
    }

    // ─── State ───────────────────────────────────────────────────────
    uint256 public nextArtworkId = 1;
    uint256 public activeCuratorCount;
    uint256 public featureThreshold = 3;     // curators needed to feature
    uint256 public featureMinScore = 70;     // min average score (out of 100) to feature
    uint256 public platformFeeBPS = 500;     // 5%
    uint256 public submissionFee = 0.0005 ether;

    mapping(uint256 => Artwork) public artworks;
    mapping(address => Curator) public curators;
    mapping(uint256 => mapping(address => bool)) public hasScored; // artworkId => curator => scored
    mapping(uint256 => mapping(address => uint256)) public curatorScores; // artworkId => curator => score
    mapping(address => uint256[]) public artistArtworks;

    // ─── Events ──────────────────────────────────────────────────────
    event ArtworkSubmitted(uint256 indexed artworkId, address indexed artist, bytes32 artHash, string metadataURI);
    event ArtworkCurated(uint256 indexed artworkId, address indexed curator, uint256 score);
    event ArtworkFeatured(uint256 indexed artworkId, uint256 averageScore);
    event ArtworkPurchased(uint256 indexed artworkId, address indexed buyer, uint256 price);
    event ArtworkPriceSet(uint256 indexed artworkId, uint256 price);
    event CuratorAdded(address indexed curator);
    event CuratorRemoved(address indexed curator);
    event FeatureThresholdUpdated(uint256 newThreshold, uint256 newMinScore);

    // ─── Modifiers ───────────────────────────────────────────────────
    modifier onlyCurator() {
        require(curators[msg.sender].active, "ArtGallery: not a curator");
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────
    constructor() {
        owner = msg.sender;
        // Owner is the first curator
        curators[msg.sender] = Curator({ active: true, artworksReviewed: 0, addedAt: block.timestamp });
        activeCuratorCount = 1;
    }

    // ─── Artist Functions ────────────────────────────────────────────

    /// @notice Submit an artwork to the gallery
    /// @param artHash Content hash of the artwork
    /// @param metadataURI URI pointing to the artwork metadata
    /// @param price Sale price in wei (0 = not for sale initially)
    function submitArtwork(bytes32 artHash, string calldata metadataURI, uint256 price)
        external
        payable
        whenNotPaused
    {
        require(artHash != bytes32(0), "ArtGallery: empty art hash");
        require(bytes(metadataURI).length > 0, "ArtGallery: empty URI");
        require(msg.value >= submissionFee, "ArtGallery: insufficient fee");

        uint256 artworkId = nextArtworkId++;
        artworks[artworkId] = Artwork({
            artist: msg.sender,
            artHash: artHash,
            metadataURI: metadataURI,
            price: price,
            totalScore: 0,
            curatorCount: 0,
            featured: false,
            sold: false,
            buyer: address(0),
            submittedAt: block.timestamp
        });
        artistArtworks[msg.sender].push(artworkId);

        emit ArtworkSubmitted(artworkId, msg.sender, artHash, metadataURI);
    }

    /// @notice Set or update the sale price of your artwork
    /// @param artworkId The artwork to price
    /// @param price New price in wei (0 to remove from sale)
    function setPrice(uint256 artworkId, uint256 price) external {
        Artwork storage art = artworks[artworkId];
        require(art.artist == msg.sender, "ArtGallery: not artist");
        require(!art.sold, "ArtGallery: already sold");
        art.price = price;
        emit ArtworkPriceSet(artworkId, price);
    }

    // ─── Curator Functions ───────────────────────────────────────────

    /// @notice Curate an artwork with a score
    /// @param artworkId The artwork to curate
    /// @param score Quality score from 0-100
    function curateArtwork(uint256 artworkId, uint256 score) external onlyCurator whenNotPaused {
        require(score <= 100, "ArtGallery: score out of range");
        Artwork storage art = artworks[artworkId];
        require(art.artist != address(0), "ArtGallery: artwork does not exist");
        require(art.artist != msg.sender, "ArtGallery: cannot curate own art");
        require(!hasScored[artworkId][msg.sender], "ArtGallery: already scored");

        hasScored[artworkId][msg.sender] = true;
        curatorScores[artworkId][msg.sender] = score;
        art.totalScore += score;
        art.curatorCount++;
        curators[msg.sender].artworksReviewed++;

        emit ArtworkCurated(artworkId, msg.sender, score);

        // Check for featuring via consensus
        if (!art.featured && art.curatorCount >= featureThreshold) {
            uint256 avgScore = art.totalScore / art.curatorCount;
            if (avgScore >= featureMinScore) {
                art.featured = true;
                emit ArtworkFeatured(artworkId, avgScore);
            }
        }
    }

    // ─── Purchase Functions ──────────────────────────────────────────

    /// @notice Purchase an artwork
    /// @param artworkId The artwork to buy
    function purchaseArtwork(uint256 artworkId) external payable nonReentrant whenNotPaused {
        Artwork storage art = artworks[artworkId];
        require(!art.sold, "ArtGallery: already sold");
        require(art.price > 0, "ArtGallery: not for sale");
        require(msg.value >= art.price, "ArtGallery: insufficient payment");
        require(msg.sender != art.artist, "ArtGallery: cannot buy own art");

        art.sold = true;
        art.buyer = msg.sender;

        uint256 fee = (art.price * platformFeeBPS) / 10000;
        uint256 artistPayout = art.price - fee;

        (bool success, ) = payable(art.artist).call{value: artistPayout}("");
        require(success, "ArtGallery: artist payment failed");

        emit ArtworkPurchased(artworkId, msg.sender, art.price);
    }

    // ─── Curator Management (Owner) ──────────────────────────────────

    /// @notice Add a new curator
    function addCurator(address curator) external onlyOwner {
        require(curator != address(0), "ArtGallery: zero address");
        require(!curators[curator].active, "ArtGallery: already curator");
        curators[curator] = Curator({ active: true, artworksReviewed: 0, addedAt: block.timestamp });
        activeCuratorCount++;
        emit CuratorAdded(curator);
    }

    /// @notice Remove a curator
    function removeCurator(address curator) external onlyOwner {
        require(curators[curator].active, "ArtGallery: not active curator");
        require(curator != owner, "ArtGallery: cannot remove owner curator");
        curators[curator].active = false;
        activeCuratorCount--;
        emit CuratorRemoved(curator);
    }

    /// @notice Update feature threshold parameters
    function setFeatureThreshold(uint256 newThreshold, uint256 newMinScore) external onlyOwner {
        require(newThreshold > 0, "ArtGallery: zero threshold");
        require(newMinScore <= 100, "ArtGallery: invalid min score");
        featureThreshold = newThreshold;
        featureMinScore = newMinScore;
        emit FeatureThresholdUpdated(newThreshold, newMinScore);
    }

    // ─── View Functions ──────────────────────────────────────────────

    /// @notice Get an artist's artwork IDs
    function getArtistArtworks(address artist) external view returns (uint256[] memory) {
        return artistArtworks[artist];
    }

    /// @notice Get artwork average score
    function getAverageScore(uint256 artworkId) external view returns (uint256) {
        Artwork storage art = artworks[artworkId];
        if (art.curatorCount == 0) return 0;
        return art.totalScore / art.curatorCount;
    }

    // ─── Admin ───────────────────────────────────────────────────────

    function setSubmissionFee(uint256 newFee) external onlyOwner { submissionFee = newFee; }
    function setPlatformFee(uint256 newFeeBPS) external onlyOwner {
        require(newFeeBPS <= 1000, "ArtGallery: fee too high");
        platformFeeBPS = newFeeBPS;
    }

    function withdraw() external onlyOwner nonReentrant {
        (bool success, ) = payable(owner).call{value: address(this).balance}("");
        require(success, "ArtGallery: withdraw failed");
    }

    receive() external payable {}
}
