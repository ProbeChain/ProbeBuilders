# ProbeGovernance

Protocol governance for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: ProtocolGovernor.sol

Full governance lifecycle with proposals, voting, timelock, and quorum enforcement.

### Key Functions
- `propose(targets[], values[], calldatas[], description)` — Create a proposal
- `castVote(proposalId, support)` — Cast a vote
- `queue(proposalId)` — Queue a succeeded proposal
- `execute(proposalId)` — Execute after timelock

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
