// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SoulboundToken
 * @author ProbeChain
 * @notice Non-transferable soulbound tokens for achievements, credentials, and memberships
 * @dev Deployed on ProbeChain Rydberg Testnet (Chain ID 8004)
 */

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() { require(msg.sender == _owner, "Ownable: not owner"); _; }
    function owner() public view returns (address) { return _owner; }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract Pausable {
    bool private _paused;
    event Paused(address account);
    event Unpaused(address account);

    constructor() { _paused = false; }
    modifier whenNotPaused() { require(!_paused, "Pausable: paused"); _; }
    modifier whenPaused() { require(_paused, "Pausable: not paused"); _; }
    function paused() public view returns (bool) { return _paused; }
    function _pause() internal whenNotPaused { _paused = true; emit Paused(msg.sender); }
    function _unpause() internal whenPaused { _paused = false; emit Unpaused(msg.sender); }
}

contract SoulboundToken is Ownable, Pausable {
    /// @notice Token types
    enum TokenType { Achievement, Credential, Membership }

    /// @notice Soulbound token data
    struct SBToken {
        uint256 id;
        address recipient;
        TokenType tokenType;
        string metadataURI;
        uint256 issuedAt;
        bool revoked;
        address issuedBy;
    }

    /// @dev Token name
    string public name;

    /// @dev Token symbol
    string public symbol;

    /// @dev Token ID counter
    uint256 private _nextTokenId;

    /// @dev Token ID => token data
    mapping(uint256 => SBToken) private _tokens;

    /// @dev Address => token IDs
    mapping(address => uint256[]) private _holderTokens;

    /// @dev Address => token count (active only)
    mapping(address => uint256) private _balances;

    /// @dev Authorized issuers
    mapping(address => bool) public issuers;

    // ───────── Events ─────────

    /// @notice Emitted when a soulbound token is issued
    event TokenIssued(uint256 indexed tokenId, address indexed recipient, TokenType tokenType, string metadataURI);

    /// @notice Emitted when a token is revoked
    event TokenRevoked(uint256 indexed tokenId, address indexed revokedBy);

    /// @notice Emitted when an issuer is updated
    event IssuerUpdated(address indexed issuer, bool status);

    /// @notice Emitted when a transfer is attempted (always reverts)
    event TransferAttempted(address indexed from, address indexed to, uint256 indexed tokenId);

    // ───────── Constructor ─────────

    constructor() {
        name = "ProbeChain Soulbound Token";
        symbol = "PSBT";
        _nextTokenId = 1;
    }

    // ───────── Admin ─────────

    /// @notice Set issuer status
    function setIssuer(address issuer, bool status) external onlyOwner {
        require(issuer != address(0), "SBT: zero address");
        issuers[issuer] = status;
        emit IssuerUpdated(issuer, status);
    }

    /// @notice Pause the contract
    function pause() external onlyOwner { _pause(); }

    /// @notice Unpause the contract
    function unpause() external onlyOwner { _unpause(); }

    // ───────── Core Functions ─────────

    /// @notice Issue a soulbound token to a recipient
    /// @param recipient The address to receive the token
    /// @param tokenType The type of token
    /// @param metadataURI URI pointing to token metadata
    /// @return tokenId The new token ID
    function issue(
        address recipient,
        TokenType tokenType,
        string calldata metadataURI
    ) external whenNotPaused returns (uint256 tokenId) {
        require(issuers[msg.sender] || msg.sender == owner(), "SBT: not issuer");
        require(recipient != address(0), "SBT: zero address");
        require(bytes(metadataURI).length > 0, "SBT: empty URI");

        tokenId = _nextTokenId++;

        _tokens[tokenId] = SBToken({
            id: tokenId,
            recipient: recipient,
            tokenType: tokenType,
            metadataURI: metadataURI,
            issuedAt: block.timestamp,
            revoked: false,
            issuedBy: msg.sender
        });

        _holderTokens[recipient].push(tokenId);
        _balances[recipient]++;

        emit TokenIssued(tokenId, recipient, tokenType, metadataURI);
    }

    /// @notice Revoke a soulbound token
    /// @param tokenId The token to revoke
    function revoke(uint256 tokenId) external whenNotPaused {
        SBToken storage token = _tokens[tokenId];
        require(token.id != 0, "SBT: not found");
        require(!token.revoked, "SBT: already revoked");
        require(
            msg.sender == token.issuedBy || msg.sender == owner(),
            "SBT: not authorized"
        );

        token.revoked = true;
        _balances[token.recipient]--;

        emit TokenRevoked(tokenId, msg.sender);
    }

    /// @notice Verify a token is valid (exists and not revoked)
    /// @param tokenId The token to verify
    /// @return True if the token is valid
    function verify(uint256 tokenId) external view returns (bool) {
        SBToken memory token = _tokens[tokenId];
        return token.id != 0 && !token.revoked;
    }

    /// @notice Transfer is disabled for soulbound tokens
    /// @dev Always reverts
    function transfer(address /*to*/, uint256 /*tokenId*/) external pure {
        revert("SBT: soulbound tokens are non-transferable");
    }

    /// @notice TransferFrom is disabled for soulbound tokens
    /// @dev Always reverts
    function transferFrom(address /*from*/, address /*to*/, uint256 /*tokenId*/) external pure {
        revert("SBT: soulbound tokens are non-transferable");
    }

    /// @notice Approve is disabled for soulbound tokens
    /// @dev Always reverts
    function approve(address /*to*/, uint256 /*tokenId*/) external pure {
        revert("SBT: soulbound tokens are non-transferable");
    }

    // ───────── View Functions ─────────

    /// @notice Get token details
    /// @param tokenId The token ID
    /// @return The token struct
    function getToken(uint256 tokenId) external view returns (SBToken memory) {
        require(_tokens[tokenId].id != 0, "SBT: not found");
        return _tokens[tokenId];
    }

    /// @notice Get token balance for an address (active tokens only)
    /// @param holder The holder address
    /// @return The balance
    function balanceOf(address holder) external view returns (uint256) {
        return _balances[holder];
    }

    /// @notice Get all token IDs for a holder
    /// @param holder The holder address
    /// @return Array of token IDs
    function getHolderTokens(address holder) external view returns (uint256[] memory) {
        return _holderTokens[holder];
    }

    /// @notice Get the token metadata URI
    /// @param tokenId The token ID
    /// @return The metadata URI
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_tokens[tokenId].id != 0, "SBT: not found");
        return _tokens[tokenId].metadataURI;
    }

    /// @notice Get total tokens issued
    /// @return count The total count
    function totalSupply() external view returns (uint256 count) {
        return _nextTokenId - 1;
    }
}
