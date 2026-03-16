import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying BootcampTracker with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const BootcampTracker = await ethers.getContractFactory("BootcampTracker");
  const tracker = await BootcampTracker.deploy();
  await tracker.waitForDeployment();

  console.log("BootcampTracker deployed to:", await tracker.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
