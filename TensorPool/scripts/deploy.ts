import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TrainingPool with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const TrainingPool = await ethers.getContractFactory("TrainingPool");
  const pool = await TrainingPool.deploy();
  await pool.waitForDeployment();

  const address = await pool.getAddress();
  console.log("TrainingPool deployed to:", address);
  console.log("Platform fee:", (await pool.platformFee()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
