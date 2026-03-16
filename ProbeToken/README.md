# ProbeToken

PROBE token utilities for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: ProbeUtilities.sol

Gas-efficient batch transfers, multicall, and balance queries for ERC20 and native tokens.

### Key Functions
- `batchTransfer(token, recipients[], amounts[])` — Batch ERC20 transfers
- `batchTransferETH(recipients[], amounts[])` — Batch native PROBE transfers
- `approveAndTransfer(token, from, to, amount)` — Approve + transfer helper
- `getBalances(token, addresses[])` — Query multiple ERC20 balances
- `multicall(targets[], calldatas[])` — Execute multiple calls

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
