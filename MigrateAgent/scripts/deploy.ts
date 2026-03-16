import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying MigrationTracker with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const MigrationTracker = await ethers.getContractFactory("MigrationTracker");
  const tracker = await MigrationTracker.deploy();
  await tracker.waitForDeployment();

  console.log("MigrationTracker deployed to:", await tracker.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
