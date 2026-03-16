# ProbeSwap

DEX router with AI-optimized order splitting for ProbeChain Rydberg Testnet.

## Features

- Constant-product AMM (x*y=k) with 0.3% swap fee
- ERC20 pair factory with LP token minting/burning
- Multi-hop swap path support via `swapExactTokensForTokens`
- `getAmountsOut` for price quotes along arbitrary paths

## Contracts

| Contract | Address |
|---|---|
| SimpleSwapRouter | `TBD` |

## Quick Start

```bash
cp .env.example .env   # Add your private key
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- RPC: `https://proscan.pro/chain/rydberg-rpc`
- Chain ID: `8004`
