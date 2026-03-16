import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying GrowthTracker with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const GrowthTracker = await ethers.getContractFactory("GrowthTracker");
  const tracker = await GrowthTracker.deploy();
  await tracker.waitForDeployment();

  console.log("GrowthTracker deployed to:", await tracker.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
