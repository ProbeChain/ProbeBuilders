// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title CertificateRegistry
 * @author ProbeBuilders
 * @notice Soulbound (non-transferable) digital certificate NFTs for ProbeChain Rydberg Testnet.
 *         Issue, verify, and revoke credential tokens bound to recipients.
 * @dev Inline Ownable, ReentrancyGuard, Pausable. EVM London compatible.
 *      Minimal ERC-721-like interface — transfers disabled (soulbound).
 */

/* ───────── Abstract helpers (inlined) ───────── */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed prev, address indexed next_);
    error OwnableUnauthorized();
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), msg.sender); }
    modifier onlyOwner() { if (msg.sender != _owner) revert OwnableUnauthorized(); _; }
    function owner() public view returns (address) { return _owner; }
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero addr");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract ReentrancyGuard {
    uint256 private _status = 1;
    error ReentrancyGuardLocked();
    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuardLocked();
        _status = 2;
        _;
        _status = 1;
    }
}

abstract contract Pausable is Ownable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);
    error ContractPaused();
    error ContractNotPaused();
    modifier whenNotPaused() { if (_paused) revert ContractPaused(); _; }
    modifier whenPaused() { if (!_paused) revert ContractNotPaused(); _; }
    function paused() public view returns (bool) { return _paused; }
    function pause() external onlyOwner whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function unpause() external onlyOwner whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

/* ───────── Main Contract ───────── */

contract CertificateRegistry is Ownable, ReentrancyGuard, Pausable {

    /* ── Token metadata ── */

    string public constant name   = "ProbeChain Certificate";
    string public constant symbol = "pCERT";

    /* ── Structs ── */

    /// @notice A soulbound certificate
    struct Certificate {
        uint256 id;
        address recipient;
        string  title;
        address issuer;
        string  metadataURI;    // IPFS or URL to certificate metadata/image
        uint256 issuedAt;
        uint256 expiry;         // 0 = no expiry
        bool    revoked;
    }

    /* ── State ── */

    uint256 public nextCertId;
    mapping(uint256 => Certificate) public certificates;
    mapping(address => bool) public authorizedIssuers;
    mapping(address => uint256[]) private _recipientCerts;
    mapping(address => uint256[]) private _issuerCerts;

    /// @notice Total certificates issued
    uint256 public totalIssued;
    /// @notice Total certificates revoked
    uint256 public totalRevoked;

    /* ── Events (ERC-721 compatible subset) ── */

    /// @notice ERC-721 Transfer event (for indexers; soulbound so only mint/burn)
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    /// @notice Emitted when a certificate is issued
    event CertificateIssued(uint256 indexed certId, address indexed recipient, string title, address indexed issuer, uint256 expiry);
    /// @notice Emitted when a certificate is revoked
    event CertificateRevoked(uint256 indexed certId, address indexed revokedBy);
    /// @notice Emitted when issuer authorization changes
    event IssuerUpdated(address indexed issuer, bool status);

    /* ── Errors ── */

    error NotIssuer();
    error NotCertIssuer();
    error CertNotFound();
    error CertRevoked();
    error CertExpired();
    error SoulboundNonTransferable();
    error AlreadyRevoked();

    /* ── Modifiers ── */

    modifier onlyIssuer() {
        if (!authorizedIssuers[msg.sender] && msg.sender != owner()) revert NotIssuer();
        _;
    }

    /* ── Constructor ── */

    constructor() Ownable() {
        authorizedIssuers[msg.sender] = true;
        emit IssuerUpdated(msg.sender, true);
    }

    /* ── Issuer management ── */

    /// @notice Add or remove an authorized certificate issuer
    function setIssuer(address issuer, bool status) external onlyOwner {
        require(issuer != address(0), "zero addr");
        authorizedIssuers[issuer] = status;
        emit IssuerUpdated(issuer, status);
    }

    /* ── Core functions ── */

    /**
     * @notice Issue a soulbound certificate to a recipient
     * @param recipient The certificate holder
     * @param title Certificate title (e.g. "Solidity Developer Level 2")
     * @param metadataURI URI pointing to certificate metadata/image
     * @param expiry Expiration timestamp (0 for no expiry)
     * @return certId The minted certificate ID
     */
    function issueCertificate(
        address recipient,
        string calldata title,
        string calldata metadataURI,
        uint256 expiry
    ) external onlyIssuer whenNotPaused returns (uint256 certId) {
        require(recipient != address(0), "zero recipient");
        require(bytes(title).length > 0, "empty title");
        require(expiry == 0 || expiry > block.timestamp, "already expired");

        certId = nextCertId++;
        certificates[certId] = Certificate({
            id: certId,
            recipient: recipient,
            title: title,
            issuer: msg.sender,
            metadataURI: metadataURI,
            issuedAt: block.timestamp,
            expiry: expiry,
            revoked: false
        });

        _recipientCerts[recipient].push(certId);
        _issuerCerts[msg.sender].push(certId);
        totalIssued++;

        // ERC-721 mint event
        emit Transfer(address(0), recipient, certId);
        emit CertificateIssued(certId, recipient, title, msg.sender, expiry);
    }

    /**
     * @notice Verify a certificate is valid (exists, not revoked, not expired)
     * @param certId The certificate to verify
     * @return valid True if the certificate is currently valid
     * @return recipient The certificate holder
     * @return title The certificate title
     * @return issuer The issuing authority
     * @return issuedAt Issue timestamp
     * @return expiry Expiration timestamp (0 = none)
     */
    function verifyCertificate(uint256 certId) external view returns (
        bool    valid,
        address recipient,
        string memory title,
        address issuer,
        uint256 issuedAt,
        uint256 expiry
    ) {
        Certificate storage cert = certificates[certId];
        if (cert.issuedAt == 0) return (false, address(0), "", address(0), 0, 0);

        recipient = cert.recipient;
        title = cert.title;
        issuer = cert.issuer;
        issuedAt = cert.issuedAt;
        expiry = cert.expiry;

        valid = !cert.revoked && (cert.expiry == 0 || block.timestamp < cert.expiry);
    }

    /**
     * @notice Revoke a certificate (only original issuer or owner)
     * @param certId The certificate to revoke
     */
    function revokeCertificate(uint256 certId) external whenNotPaused {
        Certificate storage cert = certificates[certId];
        if (cert.issuedAt == 0) revert CertNotFound();
        if (cert.issuer != msg.sender && msg.sender != owner()) revert NotCertIssuer();
        if (cert.revoked) revert AlreadyRevoked();

        cert.revoked = true;
        totalRevoked++;

        // ERC-721 burn event
        emit Transfer(cert.recipient, address(0), certId);
        emit CertificateRevoked(certId, msg.sender);
    }

    /* ── ERC-721 minimal read interface (soulbound) ── */

    /// @notice Get the owner of a token (soulbound: always the recipient)
    function ownerOf(uint256 certId) external view returns (address) {
        Certificate storage cert = certificates[certId];
        if (cert.issuedAt == 0) revert CertNotFound();
        if (cert.revoked) revert CertRevoked();
        return cert.recipient;
    }

    /// @notice Get the number of certificates held by an address
    function balanceOf(address account) external view returns (uint256) {
        return _recipientCerts[account].length;
    }

    /// @notice Get the token URI for a certificate
    function tokenURI(uint256 certId) external view returns (string memory) {
        Certificate storage cert = certificates[certId];
        if (cert.issuedAt == 0) revert CertNotFound();
        return cert.metadataURI;
    }

    /// @dev Soulbound: all transfer functions revert
    function transferFrom(address, address, uint256) external pure {
        revert SoulboundNonTransferable();
    }

    /// @dev Soulbound: all transfer functions revert
    function safeTransferFrom(address, address, uint256) external pure {
        revert SoulboundNonTransferable();
    }

    /// @dev Soulbound: all transfer functions revert
    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert SoulboundNonTransferable();
    }

    /// @dev Soulbound: approval not supported
    function approve(address, uint256) external pure {
        revert SoulboundNonTransferable();
    }

    /// @dev Soulbound: approval not supported
    function setApprovalForAll(address, bool) external pure {
        revert SoulboundNonTransferable();
    }

    /* ── View helpers ── */

    /// @notice Get all certificate IDs held by a recipient
    function getRecipientCerts(address recipient) external view returns (uint256[] memory) {
        return _recipientCerts[recipient];
    }

    /// @notice Get all certificate IDs issued by an issuer
    function getIssuerCerts(address issuer) external view returns (uint256[] memory) {
        return _issuerCerts[issuer];
    }

    /// @notice Check if a certificate is currently valid
    function isValid(uint256 certId) external view returns (bool) {
        Certificate storage cert = certificates[certId];
        return cert.issuedAt != 0 && !cert.revoked && (cert.expiry == 0 || block.timestamp < cert.expiry);
    }

    /// @notice ERC-165 supportsInterface
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd  // ERC-721
            || interfaceId == 0x01ffc9a7; // ERC-165
    }
}
