# ProbeQuiz

Quiz-to-earn platform with on-chain answer verification on ProbeChain Rydberg Testnet.

## Features

- Create funded quizzes with hashed questions and answers
- On-chain answer verification
- Configurable reward per correct answer
- Maximum attempts per participant
- Claim rewards after answering
- Quiz funding and deactivation

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: QuizPlatform

| Function | Description |
|---|---|
| `createQuiz(questions[], answers[], rewardPerCorrect, maxAttempts)` | Create quiz (payable) |
| `submitAnswers(quizId, answers[])` | Submit answers |
| `claimReward(attemptId)` | Claim reward |
| `fundQuiz(quizId)` | Add funds (payable) |
| `deactivateQuiz(quizId)` | Deactivate and withdraw |

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
