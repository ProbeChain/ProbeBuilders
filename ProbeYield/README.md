# ProbeYield

ERC-4626 compatible yield aggregator vault for ProbeChain Rydberg Testnet.

## Features

- ERC-4626 compliant vault with share-based accounting
- Pluggable strategy interface for yield generation
- Performance fee collection on harvest
- Configurable deposit cap
- Pausable deposits

## Contracts

| Contract | Address |
|---|---|
| YieldVault | `TBD` |

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
