import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying CloudPlatform with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const CloudPlatform = await ethers.getContractFactory("CloudPlatform");
  const cloud = await CloudPlatform.deploy();
  await cloud.waitForDeployment();

  const address = await cloud.getAddress();
  console.log("CloudPlatform deployed to:", address);
  console.log("Base price:", ethers.formatEther(await cloud.basePricePerHour()), "ETH/hour");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
