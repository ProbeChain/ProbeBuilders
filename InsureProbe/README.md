# InsureProbe

DeFi insurance protocol for ProbeChain Rydberg Testnet.

## Features

- Configurable policy types (smart contract hack, depeg, etc.)
- Premium calculation based on coverage and duration
- Claim filing with evidence (IPFS hash)
- Oracle/agent-based claim resolution
- Underwriter pool with deposit/withdraw
- Solvency checks on withdrawal

## Contracts

| Contract | Address |
|---|---|
| InsurancePool | `TBD` |

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
