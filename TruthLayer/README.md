# TruthLayer — Data Provenance

Data provenance tracking on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Origin Registration**: Register data origins with source, timestamp, and metadata
- **Transformation Tracking**: Chain of transformations from origin to current form
- **Provenance Verification**: Verify full provenance chain for any data hash
- **Auditor Certification**: Authorized auditors certify data authenticity
- **Hash Indexing**: Lookup by origin hash or any transformation output hash

## Contract: ProvenanceTracker.sol

| Function | Description |
|---|---|
| `registerOrigin` | Register data origin with source and metadata |
| `addTransformation` | Add a transformation step to an origin |
| `verifyProvenance` | Verify full provenance chain for a data hash |
| `certifyData` | Auditor certifies data authenticity |

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
- **EVM**: London
