import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying StakeOptimizer with account:", deployer.address);

  // Replace with actual token addresses on Rydberg:
  const STAKING_TOKEN = process.env.STAKING_TOKEN || "0x0000000000000000000000000000000000000000";
  const REWARD_TOKEN = process.env.REWARD_TOKEN || "0x0000000000000000000000000000000000000000";
  const REWARD_RATE = ethers.parseEther("0.0001"); // 0.0001 tokens per second

  const StakeOptimizer = await ethers.getContractFactory("StakeOptimizer");
  const staker = await StakeOptimizer.deploy(
    STAKING_TOKEN,
    REWARD_TOKEN,
    REWARD_RATE,
    deployer.address
  );
  await staker.waitForDeployment();
  console.log("StakeOptimizer deployed to:", await staker.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
