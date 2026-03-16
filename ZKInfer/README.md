# ZKInfer — ZK Proof Verification Registry

ZK proof verification registry on ProbeChain Rydberg Testnet (Chain ID 8004).

## Features

- **Circuit Registration**: Register ZK circuits with on-chain verifier addresses
- **Proof Submission**: Submit proofs with public inputs for verification
- **Verification Tracking**: Full verification history per circuit
- **Verifier Staking**: Stake-based verifier authorization
- **Status Tracking**: Pending, Verified, Failed, Disputed states

## Contract: ZKVerifier.sol

| Function | Description |
|---|---|
| `registerCircuit` | Register a new ZK circuit with verifier address |
| `submitProof` | Submit a proof for a registered circuit |
| `verifyProof` | Verify a submitted proof (authorized verifiers only) |
| `getVerificationHistory` | Get all submission IDs for a circuit |

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```

## Network

- **Network**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
- **EVM**: London
