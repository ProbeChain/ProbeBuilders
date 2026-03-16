# CredStack

Verifiable credentials on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Issue Credentials** — Authorized issuers create credentials with type, data hash, and expiry.
- **Credential Chains** — Link credentials to parents for provenance tracking.
- **Delegation** — Issuers can delegate issuance power to others.
- **Verify & Revoke** — Anyone can verify; issuer or owner can revoke.
- **Auto-Expiry** — Expired credentials are marked on verification.

## Contract

`CredentialStack.sol` — Solidity 0.8.24, EVM London, inline Ownable / ReentrancyGuard / Pausable.

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
