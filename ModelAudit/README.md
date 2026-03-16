# ModelAudit

AI model performance verification with auditor staking and benchmark challenges on ProbeChain Rydberg Testnet.

## Features

- **Model Registration** — Register AI models across categories (NLP, Vision, Audio, Multimodal, Tabular, Reinforcement)
- **Auditor Staking** — Auditors stake tokens to submit verified benchmarks
- **Benchmark Submission** — Submit scored benchmarks with proof hashes
- **Challenge System** — Challenge suspicious results with stake-backed disputes
- **Slashing** — Auditors lose stake when challenges are upheld

## Contract: ModelBenchmark.sol

| Function | Description |
|---|---|
| `registerModel(name, modelHash, category)` | Register a model |
| `stakeAsAuditor()` | Stake to become an auditor |
| `submitBenchmark(modelId, benchmarkId, score, proofHash)` | Submit benchmark |
| `getModelScore(modelId)` | Get average model score |
| `challengeResult(benchmarkId, reason)` | Challenge a result |

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
- **EVM**: London
