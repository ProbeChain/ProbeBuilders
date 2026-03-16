# ProbeNotary - Document Notarization Service

Smart contract for blockchain-based document notarization on ProbeChain Rydberg Testnet.

## Contract: NotaryService.sol

Notarize documents by hash with timestamp proof and multi-party witness support.

### Features
- **notarize** - Submit a document hash with metadata for timestamp proof
- **verify** - Verify a document's notarization status, timestamp, and notarizer
- **addWitness** - Third parties can attest to a notarized document
- **revokeNotarization** - Revoke a notarization (by original notarizer or owner)
- **Multi-party witnesses** - Multiple parties can witness the same document
- **Optional fees** - Configurable notarization fee

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
