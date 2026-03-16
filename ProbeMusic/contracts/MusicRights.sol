// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MusicRights
 * @author ProbeChain
 * @notice Music rights management with per-stream micro-payments and royalty splits on ProbeChain Rydberg Testnet
 * @dev Manages track registration, streaming payments, royalty collection, and rights transfers
 */

/// @dev Minimal Ownable implementation
abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/// @dev Minimal ReentrancyGuard implementation
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/// @dev Minimal Pausable implementation
abstract contract Pausable is Ownable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    constructor() {
        _paused = false;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    function pause() public onlyOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

contract MusicRights is Ownable, ReentrancyGuard, Pausable {
    // ─── Types ───────────────────────────────────────────────────────────
    struct Artist {
        address wallet;
        uint256 splitBps; // basis points
    }

    struct Track {
        uint256 id;
        string title;
        bytes32 audioHash;
        string isrc;
        address registeredBy;
        uint256 streamPrice;
        uint256 totalStreams;
        uint256 accumulatedRoyalties;
        uint256 artistCount;
        bool active;
        uint256 registeredAt;
    }

    // ─── State ───────────────────────────────────────────────────────────
    uint256 public trackCount;
    uint256 public defaultStreamPrice = 0.0001 ether;
    uint256 public platformFeeBps = 200; // 2%

    mapping(uint256 => Track) public tracks;
    mapping(uint256 => mapping(uint256 => Artist)) public trackArtists;
    mapping(string => bool) public isrcExists;
    mapping(uint256 => mapping(address => uint256)) public pendingPayouts;

    // ─── Events ──────────────────────────────────────────────────────────
    /// @notice Emitted when a new track is registered
    event TrackRegistered(uint256 indexed trackId, string title, string isrc, address indexed registeredBy);

    /// @notice Emitted when a track is streamed
    event TrackStreamed(uint256 indexed trackId, address indexed listener, uint256 payment);

    /// @notice Emitted when royalties are collected
    event RoyaltiesCollected(uint256 indexed trackId, address indexed artist, uint256 amount);

    /// @notice Emitted when rights are transferred
    event RightsTransferred(uint256 indexed trackId, address indexed from, address indexed to, uint256 shareBps);

    /// @notice Emitted when stream price is updated
    event StreamPriceUpdated(uint256 indexed trackId, uint256 newPrice);

    // ─── Track Management ────────────────────────────────────────────────

    /**
     * @notice Register a new music track with artist splits
     * @param _title Track title
     * @param _audioHash Hash of the audio content
     * @param _isrc International Standard Recording Code
     * @param _artists Array of artist addresses
     * @param _splits Array of split percentages in basis points (must sum to 10000)
     * @return trackId The ID of the registered track
     */
    function registerTrack(
        string calldata _title,
        bytes32 _audioHash,
        string calldata _isrc,
        address[] calldata _artists,
        uint256[] calldata _splits
    ) external whenNotPaused returns (uint256 trackId) {
        require(bytes(_title).length > 0 && bytes(_title).length <= 256, "Invalid title");
        require(_audioHash != bytes32(0), "Empty audio hash");
        require(bytes(_isrc).length > 0, "Empty ISRC");
        require(!isrcExists[_isrc], "ISRC already registered");
        require(_artists.length > 0 && _artists.length <= 20, "Invalid artist count");
        require(_artists.length == _splits.length, "Arrays length mismatch");

        uint256 totalSplit;
        for (uint256 i = 0; i < _splits.length; i++) {
            require(_artists[i] != address(0), "Invalid artist address");
            require(_splits[i] > 0, "Split must be > 0");
            totalSplit += _splits[i];
        }
        require(totalSplit == 10000, "Splits must sum to 10000");

        trackId = ++trackCount;
        isrcExists[_isrc] = true;

        tracks[trackId] = Track({
            id: trackId,
            title: _title,
            audioHash: _audioHash,
            isrc: _isrc,
            registeredBy: msg.sender,
            streamPrice: defaultStreamPrice,
            totalStreams: 0,
            accumulatedRoyalties: 0,
            artistCount: _artists.length,
            active: true,
            registeredAt: block.timestamp
        });

        for (uint256 i = 0; i < _artists.length; i++) {
            trackArtists[trackId][i] = Artist({
                wallet: _artists[i],
                splitBps: _splits[i]
            });
        }

        emit TrackRegistered(trackId, _title, _isrc, msg.sender);
    }

    /**
     * @notice Stream a track (micro-payment)
     * @param _trackId The track ID
     */
    function streamTrack(uint256 _trackId)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        Track storage track = tracks[_trackId];
        require(track.active, "Track not active");
        require(msg.value >= track.streamPrice, "Insufficient payment");

        track.totalStreams++;
        track.accumulatedRoyalties += msg.value;

        uint256 platformCut = (msg.value * platformFeeBps) / 10000;
        uint256 distributable = msg.value - platformCut;

        // Distribute to artists based on splits
        for (uint256 i = 0; i < track.artistCount; i++) {
            Artist storage artist = trackArtists[_trackId][i];
            uint256 share = (distributable * artist.splitBps) / 10000;
            pendingPayouts[_trackId][artist.wallet] += share;
        }

        emit TrackStreamed(_trackId, msg.sender, msg.value);
    }

    /**
     * @notice Collect accumulated royalties for a track
     * @param _trackId The track ID
     */
    function collectRoyalties(uint256 _trackId)
        external
        whenNotPaused
        nonReentrant
    {
        uint256 payout = pendingPayouts[_trackId][msg.sender];
        require(payout > 0, "No royalties to collect");

        pendingPayouts[_trackId][msg.sender] = 0;

        (bool sent, ) = msg.sender.call{value: payout}("");
        require(sent, "Transfer failed");

        emit RoyaltiesCollected(_trackId, msg.sender, payout);
    }

    /**
     * @notice Transfer rights share to a new owner
     * @param _trackId The track ID
     * @param _shareBps Amount of share to transfer in basis points
     * @param _newOwner New owner address
     */
    function transferRights(uint256 _trackId, uint256 _shareBps, address _newOwner)
        external
        whenNotPaused
    {
        require(_newOwner != address(0) && _newOwner != msg.sender, "Invalid recipient");
        require(_shareBps > 0, "Share must be > 0");

        Track storage track = tracks[_trackId];
        require(track.active, "Track not active");

        // Find sender's artist slot and deduct
        bool found;
        for (uint256 i = 0; i < track.artistCount; i++) {
            if (trackArtists[_trackId][i].wallet == msg.sender) {
                require(trackArtists[_trackId][i].splitBps >= _shareBps, "Insufficient share");
                trackArtists[_trackId][i].splitBps -= _shareBps;
                found = true;
                break;
            }
        }
        require(found, "Not an artist on this track");

        // Find or create recipient slot
        bool recipientFound;
        for (uint256 i = 0; i < track.artistCount; i++) {
            if (trackArtists[_trackId][i].wallet == _newOwner) {
                trackArtists[_trackId][i].splitBps += _shareBps;
                recipientFound = true;
                break;
            }
        }

        if (!recipientFound) {
            uint256 newIndex = track.artistCount;
            track.artistCount++;
            trackArtists[_trackId][newIndex] = Artist({
                wallet: _newOwner,
                splitBps: _shareBps
            });
        }

        emit RightsTransferred(_trackId, msg.sender, _newOwner, _shareBps);
    }

    /**
     * @notice Set stream price for a track (registrant only)
     * @param _trackId The track ID
     * @param _newPrice New stream price in wei
     */
    function setStreamPrice(uint256 _trackId, uint256 _newPrice) external {
        require(tracks[_trackId].registeredBy == msg.sender, "Not registrant");
        require(_newPrice > 0, "Price must be > 0");
        tracks[_trackId].streamPrice = _newPrice;
        emit StreamPriceUpdated(_trackId, _newPrice);
    }

    /**
     * @notice Update platform fee
     * @param _newFeeBps New fee in basis points
     */
    function setPlatformFee(uint256 _newFeeBps) external onlyOwner {
        require(_newFeeBps <= 1000, "Fee too high");
        platformFeeBps = _newFeeBps;
    }

    /**
     * @notice Withdraw platform fees
     */
    function withdrawFees() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees");
        (bool sent, ) = owner().call{value: balance}("");
        require(sent, "Withdraw failed");
    }

    /**
     * @notice Get track details
     * @param _trackId The track ID
     */
    function getTrack(uint256 _trackId) external view returns (Track memory) {
        return tracks[_trackId];
    }

    /**
     * @notice Get artist info for a track
     * @param _trackId The track ID
     * @param _index The artist index
     */
    function getTrackArtist(uint256 _trackId, uint256 _index) external view returns (Artist memory) {
        return trackArtists[_trackId][_index];
    }
}
