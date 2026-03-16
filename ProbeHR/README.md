# ProbeHR

Decentralized hiring platform for ProbeChain Rydberg Testnet (Chain ID 8004).

## Contract: HiringPlatform

- **postJob(title, description, skills[])** payable — Post a job with escrowed budget.
- **applyForJob(jobId, resumeHash)** — Submit an application.
- **hireCandidate(jobId, candidateAddress)** — Hire an applicant.
- **completeJob(jobId)** — Release escrow to the hired candidate.
- **disputeJob(jobId)** — Raise a dispute for owner resolution.
- Escrow-based payments, dispute resolution, platform fees.

## Setup

```bash
npm install
cp .env.example .env
# Add your private key to .env
npx hardhat compile
npx hardhat run scripts/deploy.ts --network rydberg
```
