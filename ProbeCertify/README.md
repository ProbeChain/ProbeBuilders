# ProbeCertify - Soulbound Digital Certificates

Non-transferable (soulbound) NFT certificates on ProbeChain Rydberg Testnet.

## Contract: CertificateRegistry.sol (pCERT)

Issue, verify, and revoke credential tokens permanently bound to recipients. ERC-721 compatible for indexing but all transfers are disabled.

### Features
- **issueCertificate** - Mint a soulbound certificate to a recipient
- **verifyCertificate** - Check validity, recipient, issuer, and expiry
- **revokeCertificate** - Revoke a certificate (issuer or owner only)
- **Soulbound** - All transfer/approve functions revert
- **Expirable** - Optional expiry date per certificate
- **ERC-721 compatible** - ownerOf, balanceOf, tokenURI, supportsInterface for indexer compatibility
- **Issuer management** - Authorize multiple certificate issuers

## Network
- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc

## Setup
```bash
npm install
cp .env.example .env
# Edit .env with your private key
npm run compile
npm run deploy
```
