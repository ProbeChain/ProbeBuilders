import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying MentorPlatform with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const MentorPlatform = await ethers.getContractFactory("MentorPlatform");
  const platform = await MentorPlatform.deploy();
  await platform.waitForDeployment();

  console.log("MentorPlatform deployed to:", await platform.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
