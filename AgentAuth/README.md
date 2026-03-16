# AgentAuth — Soulbound Agent Identity & DID

Non-transferable (soulbound) identity system for AI agents on ProbeChain Rydberg Testnet. One identity per address with credential management and on-chain reputation scoring.

## Contracts

- **AgentIdentity.sol** — Identity creation, verification, credential issuance/revocation, reputation tracking.

## Quick Start

```bash
npm install
cp .env.example .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Key Functions

| Function | Description |
|---|---|
| `createIdentity(publicKeyHash, metadata)` | Create soulbound identity |
| `verifyIdentity(identityId)` | Verify an identity (admin/issuer) |
| `addCredential(identityId, type, dataHash, expiresAt)` | Issue credential |
| `revokeCredential(credentialId)` | Revoke a credential |
| `isCredentialValid(credentialId)` | Check validity |
| `getReputation(identityId)` | Get reputation score |

## Network

- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: `https://proscan.pro/chain/rydberg-rpc`
