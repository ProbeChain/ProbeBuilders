# ProbeCI

Immutable CI/CD build result registry on ProbeChain Rydberg Testnet.

## Features

- Register CI/CD pipelines with repo hash
- Record build results with commit hash, status, and artifact hash
- Immutable build provenance trail
- Authorized runner system
- Build history retrieval
- Artifact hash verification
- Success rate tracking

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: CIRegistry

| Function | Description |
|---|---|
| `registerPipeline(name, repoHash)` | Register a new pipeline |
| `recordBuild(pipelineId, commitHash, status, artifactHash, timestamp, duration)` | Record a build |
| `getBuildHistory(pipelineId, limit)` | Get recent builds |
| `verifyArtifact(buildId, artifactHash)` | Verify artifact hash |
| `getSuccessRate(pipelineId)` | Get pipeline success rate |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
