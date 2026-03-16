# ProbeFee

Protocol fee collection for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: FeeCollector.sol

Configurable fee types, collection on ERC20/native, withdrawal, and statistics.

### Key Functions
- `setFee(feeType, basisPoints)` — Configure a fee type
- `collectFee(feeType, token, amount)` — Collect ERC20 fee
- `collectFeeETH(feeType)` — Collect native PROBE fee
- `withdrawFees(token)` — Withdraw collected fees
- `getFeeStats()` — Get global fee statistics

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
