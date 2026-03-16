# ProbeSwapV2

Concentrated liquidity AMM for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: ConcentratedAMM.sol

Uniswap V3-style AMM with tick-based pricing, concentrated liquidity positions, and fee tiers.

### Key Functions
- `createPool(tokenA, tokenB, fee)` — Create a liquidity pool
- `addLiquidity(poolId, tickLower, tickUpper, amount)` — Add concentrated liquidity
- `removeLiquidity(positionId)` — Remove liquidity and collect fees
- `swap(poolId, amountIn, minOut, zeroForOne)` — Execute a swap

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
