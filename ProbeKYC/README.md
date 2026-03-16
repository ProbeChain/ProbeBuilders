# ProbeKYC - Privacy KYC Verification Registry

Smart contract for privacy-preserving KYC attestations on ProbeChain Rydberg Testnet.

## Contract: KYCRegistry.sol

Verifiers attest to user identity levels without storing personal data on-chain. Only document hashes are recorded.

### Features
- **submitVerification** - Verifier attests to a user's KYC level
- **isVerified** - Check if a user holds valid verification at a given level
- **revokeVerification** - Revoke a previously issued verification
- **Levels**: None, Basic (email+phone), Standard (government ID), Enhanced (full due diligence)
- **Expiration** - Verifications expire after a configurable period (default 365 days)
- **Verifier management** - Add/remove authorized verifiers

## Network
- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc

## Setup
```bash
npm install
cp .env.example .env
# Edit .env with your private key
npm run compile
npm run deploy
```
