# ProbeCamp

On-chain bootcamp progress tracking with certificates on ProbeChain Rydberg Testnet.

## Features

- Create courses with multiple modules
- Student enrollment and progress tracking
- Module completion with proof of work
- Certificate issuance by instructor
- Graduation and certificate count tracking
- Per-student progress queries

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: BootcampTracker

| Function | Description |
|---|---|
| `createCourse(title, modules[], certificateReward)` | Create a course |
| `enrollStudent(courseId)` | Enroll in a course |
| `completeModule(courseId, moduleIndex, proofHash)` | Complete a module |
| `issueCertificate(courseId, student)` | Issue certificate (instructor) |
| `getProgress(courseId, student)` | Get student progress |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
