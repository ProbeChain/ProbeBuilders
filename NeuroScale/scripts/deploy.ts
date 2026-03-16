import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying AutoScaler with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const AutoScaler = await ethers.getContractFactory("AutoScaler");
  const scaler = await AutoScaler.deploy();
  await scaler.waitForDeployment();

  const address = await scaler.getAddress();
  console.log("AutoScaler deployed to:", address);
  console.log("Platform fee:", (await scaler.platformFee()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
