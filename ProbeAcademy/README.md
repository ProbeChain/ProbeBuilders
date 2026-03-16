# ProbeAcademy

Decentralized course marketplace on ProbeChain Rydberg Testnet.

## Features

- Publish courses with content hash, price, and category
- Student enrollment with payment
- Instructor marks course completion
- Rating system (1-5 stars)
- Category-based discovery
- Instructor revenue withdrawal
- Platform fee collection

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: CourseMarket

| Function | Description |
|---|---|
| `publishCourse(title, contentHash, price, category)` | Publish course |
| `enrollInCourse(courseId)` | Enroll (payable) |
| `completeCourse(courseId, student)` | Mark complete (instructor) |
| `rateCourse(courseId, score)` | Rate 1-5 stars |
| `getTopCourses(category)` | Get top courses |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
