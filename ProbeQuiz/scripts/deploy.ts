import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying QuizPlatform with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const QuizPlatform = await ethers.getContractFactory("QuizPlatform");
  const platform = await QuizPlatform.deploy();
  await platform.waitForDeployment();

  console.log("QuizPlatform deployed to:", await platform.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
