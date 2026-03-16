import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying CronScheduler with account:", deployer.address);

  const minInterval = 60; // 1 minute
  const maxInterval = 86400 * 30; // 30 days
  const minReward = ethers.parseEther("0.0001");
  const keeperStake = ethers.parseEther("0.05");

  const Factory = await ethers.getContractFactory("CronScheduler");
  const contract = await Factory.deploy(minInterval, maxInterval, minReward, keeperStake);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("CronScheduler deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
