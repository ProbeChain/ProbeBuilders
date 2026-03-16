# DataDAO — Community Data Governance

Community data governance DAO on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Policy Proposals**: Members propose and vote on data governance policies
- **Stake-Weighted Voting**: Voting power proportional to staked tokens
- **Data Curation**: Curator-reviewed data submissions with multi-approval threshold
- **Curator Rewards**: Automatic rewards from pool for curation work
- **Membership**: Stake-based DAO membership

## Contract: DataGovernance.sol

| Function | Description |
|---|---|
| `proposePolicyChange` | Create a new policy change proposal |
| `voteOnPolicy` | Vote on an active proposal |
| `executePolicy` | Execute a proposal after voting period |
| `submitData` | Submit data for community review |
| `approveData` | Curators approve/reject data submissions |

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
