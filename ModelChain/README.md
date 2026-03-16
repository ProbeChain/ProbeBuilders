# ModelChain

Model version registry for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: ModelVersioning.sol

Tracks AI/ML model versions on-chain with changelogs, comparison, and deprecation support.

### Key Functions
- `registerModel(name, initialHash)` — Register a new model
- `pushVersion(modelId, versionHash, changelog)` — Push a new version
- `getLatestVersion(modelId)` — Get the latest version
- `compareVersions(modelId, v1, v2)` — Compare two versions
- `deprecateVersion(modelId, versionNumber)` — Deprecate a version

## Setup
```bash
npm install
cp .env.example .env
npx hardhat compile
npm run deploy
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
