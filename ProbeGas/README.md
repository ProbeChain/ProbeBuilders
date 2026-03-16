# ProbeGas

Gas optimizer for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: GasOptimizer.sol

Provides gas estimation, batched transactions, and refund mechanisms.

### Key Functions
- `estimateGas(target, calldata)` — Estimate gas for a call
- `suggestOptimalGas(target)` — Suggest optimal gas parameters
- `batchTransactions(targets[], calldatas[])` — Batch multiple transactions
- `refundUnusedGas()` — Claim refund of unused gas deposits

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
