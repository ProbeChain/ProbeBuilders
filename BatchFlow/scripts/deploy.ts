import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying BatchScheduler with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const BatchScheduler = await ethers.getContractFactory("BatchScheduler");
  const scheduler = await BatchScheduler.deploy();
  await scheduler.waitForDeployment();

  const address = await scheduler.getAddress();
  console.log("BatchScheduler deployed to:", address);
  console.log("Platform fee:", (await scheduler.platformFee()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
