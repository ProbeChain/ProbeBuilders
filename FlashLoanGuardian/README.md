# FlashLoanGuardian

Flash loan protection with reentrancy guards and sandwich attack detection for ProbeChain Rydberg Testnet.

## Features

- Pre/post transaction guard hooks for protected contracts
- Price deviation detection via oracle integration
- Sandwich attack detection (same-block tx counting)
- Flash loan detection via balance snapshot comparison
- Circuit breaker with configurable cooldown
- Per-token price deviation thresholds

## Contracts

| Contract | Address |
|---|---|
| FlashGuard | `TBD` |

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- RPC: `https://proscan.pro/chain/rydberg-rpc`
- Chain ID: `8004`
