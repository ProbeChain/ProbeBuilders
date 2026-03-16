# ChessAgent - On-Chain Chess with Ranking

On-chain chess game manager with ELO rating system, wagered matches, and timeout forfeits on ProbeChain Rydberg Testnet.

## Features
- Create and join wagered chess games
- Submit moves on-chain (move validation via oracle)
- ELO rating updates on win/loss
- Timeout forfeit mechanism (24h)
- Draw proposals (mutual agreement)
- Full move history stored on-chain

## Deploy
```bash
npm install
cp .env.example .env  # add your private key
npx hardhat compile
npm run deploy
```

## Network
- **Chain**: ProbeChain Rydberg Testnet
- **Chain ID**: 8004
- **RPC**: https://proscan.pro/chain/rydberg-rpc
