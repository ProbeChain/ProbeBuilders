import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying LendingPool with account:", deployer.address);

  const LendingPool = await ethers.getContractFactory("LendingPool");
  const pool = await LendingPool.deploy();
  await pool.waitForDeployment();
  console.log("LendingPool deployed to:", await pool.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
