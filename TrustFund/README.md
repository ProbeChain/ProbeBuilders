# TrustFund

Conditional trust fund vault for ProbeChain Rydberg Testnet (Chain ID 8004).

## Contract: TrustVault

- **createTrust(beneficiary, releaseCondition, releaseTime)** payable — Create a trust with locked funds.
- **releaseFunds(trustId)** — Release funds when time condition is met.
- **addTrustee(trustId, trustee)** — Add an authorized trustee.
- **revokeTrust(trustId)** — Revoke before release; funds return to grantor.
- Multiple trustees, time-locked release, revocation support.

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```
