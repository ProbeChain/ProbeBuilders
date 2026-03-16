# AnnotateDAO — Data Labeling Pool

Data labeling pool on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Task Creation**: Create labeling tasks with data hash, instructions, and per-label rewards
- **Label Submission**: Labelers submit label hashes for tasks
- **Validation**: Authorized validators verify label correctness
- **Consensus Rewards**: Correct labelers earn rewards, accuracy tracked per labeler
- **Budget Management**: Unused budget refunded on task close

## Contract: LabelingPool.sol

| Function | Description |
|---|---|
| `createLabelTask` | Create a labeling task with budget |
| `submitLabel` | Submit a label for a task |
| `validateLabel` | Validator marks label as correct/incorrect |
| `claimLabelReward` | Claim accumulated labeling rewards |

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
