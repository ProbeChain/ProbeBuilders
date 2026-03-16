# GasTracker

On-chain gas price analytics and predictions on ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: GasAnalytics.sol

Record historical gas prices, compute averages, predict future gas, find optimal transaction times.

### Key Functions
- `recordGasPrice(blockNumber, baseFee, priorityFee)` -- Record gas data
- `getAverageGas(fromBlock, toBlock)` -- Get average gas over range
- `predictGas(targetBlock)` -- Predict gas for a future block
- `getBestTime(maxGasWilling)` -- Find cheapest hour of day

### Deploy
```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network
- **Chain ID:** 8004
- **EVM:** London
- **Solidity:** 0.8.24
