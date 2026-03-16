# ProbeProfile

On-chain identity profiles on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Unique Usernames** — Alphanumeric + underscore, max 32 chars, enforced uniqueness.
- **Rich Profiles** — Avatar hash, bio, social links.
- **Verification** — Authorized verifiers attest identity.
- **Registration Fee** — Optional configurable fee.

## Contract

`ProfileRegistry.sol` — Solidity 0.8.24, EVM London, inline Ownable / ReentrancyGuard / Pausable.

## Quick Start

```bash
cp .env.example .env
npm install
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

| Parameter | Value |
|-----------|-------|
| Network   | ProbeChain Rydberg Testnet |
| RPC       | https://proscan.pro/chain/rydberg-rpc |
| Chain ID  | 8004 |
| EVM       | London |
