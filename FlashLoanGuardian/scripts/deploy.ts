import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying FlashGuard with account:", deployer.address);

  // Replace with actual oracle address or use zero address for no oracle
  const ORACLE = process.env.ORACLE_ADDRESS || ethers.ZeroAddress;

  const FlashGuard = await ethers.getContractFactory("FlashGuard");
  const guard = await FlashGuard.deploy(ORACLE);
  await guard.waitForDeployment();
  console.log("FlashGuard deployed to:", await guard.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
