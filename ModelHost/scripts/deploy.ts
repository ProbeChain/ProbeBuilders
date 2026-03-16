import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ModelServing with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const ModelServing = await ethers.getContractFactory("ModelServing");
  const serving = await ModelServing.deploy();
  await serving.waitForDeployment();

  const address = await serving.getAddress();
  console.log("ModelServing deployed to:", address);
  console.log("Min stake:", ethers.formatEther(await serving.minStake()), "ETH");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
