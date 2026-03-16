# ProbeInsure

Parametric insurance for ProbeChain Rydberg Testnet (Chain ID 8004).

## Contract: ParametricInsurance

- **createPolicy(eventType, threshold, payout, duration)** payable — Create an insurance policy by paying premium.
- **triggerPolicy(policyId, oracleData)** — Oracle triggers when threshold is met.
- **claimPayout(policyId)** — Policyholder claims the payout after trigger.
- **expirePolicy(policyId)** — Mark expired policies.
- Authorized oracle system, auto-execution on threshold, insurance pool.

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```
