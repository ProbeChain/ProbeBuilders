# ProbeDAO — DAO Governance with AI-Assisted Proposals

Full governance system for ProbeChain Rydberg Testnet. Create proposals, vote (For/Against/Abstain), queue with timelock, and execute on-chain. Proposal lifecycle: Pending -> Active -> Succeeded/Defeated -> Queued -> Executed.

## Contracts

- **GovernorAgent.sol** — Proposal creation, voting, timelock queue, execution, cancellation.

## Quick Start

```bash
npm install
cp .env.example .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Key Functions

| Function | Description |
|---|---|
| `createProposal(description, targets, values, actions)` | Create proposal |
| `vote(proposalId, support)` | Cast vote (0=Against, 1=For, 2=Abstain) |
| `queueProposal(proposalId)` | Queue for timelock |
| `executeProposal(proposalId)` | Execute after timelock |
| `getProposalState(proposalId)` | Get current state |

## Network

- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: `https://proscan.pro/chain/rydberg-rpc`
