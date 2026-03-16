# AirdropAgent

Smart airdrop distribution using Merkle tree proofs on ProbeChain Rydberg Testnet.

## Features

- Create airdrop campaigns with ERC-20 tokens
- Gas-efficient Merkle proof based claiming
- Expiry-based clawback for unclaimed tokens
- Multiple concurrent airdrops support
- Proof verification before claiming
- Claim tracking per address
- Emergency token recovery

## Setup

```bash
npm install
cp .env.example .env
# Edit .env with your private key
npx hardhat compile
npm run deploy
```

## Contract: AirdropDistributor

| Function | Description |
|---|---|
| `createAirdrop(token, merkleRoot, totalAmount, expiry, desc)` | Create airdrop campaign |
| `claim(airdropId, amount, merkleProof)` | Claim with Merkle proof |
| `clawback(airdropId)` | Reclaim unclaimed after expiry |
| `verifyProof(airdropId, account, amount, proof)` | Verify proof validity |
| `getAirdropStatus(airdropId)` | Check remaining/expired/claimed% |
| `updateMerkleRoot(airdropId, newRoot)` | Update root before claims |

## Merkle Tree Generation

Generate your Merkle tree off-chain with libraries like `merkletreejs`:

```javascript
const { MerkleTree } = require('merkletreejs');
const keccak256 = require('keccak256');
const { ethers } = require('ethers');

const leaves = recipients.map(r =>
  keccak256(ethers.solidityPacked(['address', 'uint256'], [r.address, r.amount]))
);
const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
const root = tree.getHexRoot();
```

## Network

- **Network:** ProbeChain Rydberg Testnet
- **Chain ID:** 8004
- **RPC:** https://proscan.pro/chain/rydberg-rpc
