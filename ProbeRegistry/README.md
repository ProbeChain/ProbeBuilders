# ProbeRegistry

Universal name registry for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: NameRegistry.sol

ENS-like name registration, resolution, transfer, and custom resolvers.

### Key Functions
- `registerName(name, owner, metadata)` — Register a name
- `transferName(name, newOwner)` — Transfer name ownership
- `resolveName(name)` — Resolve name to address
- `setResolver(name, resolverAddr)` — Set custom resolver

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
