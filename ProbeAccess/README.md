# ProbeAccess

Role-based access control for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: AccessControl.sol

Hierarchical roles with admin inheritance, grant/revoke, and role enumeration.

### Key Functions
- `createRole(roleName, adminRole)` — Create a new role
- `grantRole(role, account)` — Grant role to an account
- `revokeRole(role, account)` — Revoke role from an account
- `hasRole(role, account)` — Check if account has role

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
