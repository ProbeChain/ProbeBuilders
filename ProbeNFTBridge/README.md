# ProbeNFTBridge

Cross-chain NFT bridge for ProbeChain Rydberg Testnet (Chain ID: 8004).

## Contract: NFTBridge.sol

Lock-based NFT bridging with relayer verification and timeout cancellation.

### Key Functions
- `lockNFT(nftContract, tokenId, destChain)` — Lock NFT for bridging
- `claimNFT(lockId, bridgeProof)` — Claim bridged NFT (relayer)
- `cancelLock(lockId)` — Cancel lock after timeout

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
