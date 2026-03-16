# SupplyAgent - Supply Chain Tracking

Smart contract for immutable supply chain provenance on ProbeChain Rydberg Testnet.

## Contract: SupplyChain.sol

Track products from origin through checkpoints with verifier attestations and custody transfers.

### Features
- **createProduct** - Register a product with SKU, origin, and metadata
- **addCheckpoint** - Record location, status, and verifier at each step
- **transferCustody** - Transfer product custody to a new party
- **getHistory** - Full checkpoint history for any product
- **SKU lookup** - Find products by stock keeping unit
- **Authorized verifiers** - Only approved verifiers can add checkpoints

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
