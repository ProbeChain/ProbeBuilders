import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying BugBountyPlatform with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const BugBountyPlatform = await ethers.getContractFactory("BugBountyPlatform");
  const platform = await BugBountyPlatform.deploy();
  await platform.waitForDeployment();

  console.log("BugBountyPlatform deployed to:", await platform.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
