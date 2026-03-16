# ProbeTreasury

Treasury management for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: TreasuryManager.sol

Council-approved treasury with deposits, spending proposals, and budget tracking.

### Key Functions
- `deposit()` — Deposit funds into treasury
- `proposeSpend(recipient, amount, reason)` — Propose a spend
- `approveSpend(spendId)` — Approve a proposal (council)
- `executeSpend(spendId)` — Execute approved spend
- `getBalance()` / `getBudget()` — Query treasury state

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
