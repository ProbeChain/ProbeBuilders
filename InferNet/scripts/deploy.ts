import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying InferenceNetwork with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const InferenceNetwork = await ethers.getContractFactory("InferenceNetwork");
  const network = await InferenceNetwork.deploy();
  await network.waitForDeployment();

  const address = await network.getAddress();
  console.log("InferenceNetwork deployed to:", address);
  console.log("Platform fee:", (await network.platformFee()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
