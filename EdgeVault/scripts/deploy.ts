import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying EdgeStorage with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const EdgeStorage = await ethers.getContractFactory("EdgeStorage");
  const storage = await EdgeStorage.deploy();
  await storage.waitForDeployment();

  const address = await storage.getAddress();
  console.log("EdgeStorage deployed to:", address);
  console.log("Platform fee:", (await storage.platformFee()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
