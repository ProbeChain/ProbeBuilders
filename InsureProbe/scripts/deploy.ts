import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying InsurancePool with account:", deployer.address);

  const InsurancePool = await ethers.getContractFactory("InsurancePool");
  const pool = await InsurancePool.deploy();
  await pool.waitForDeployment();
  console.log("InsurancePool deployed to:", await pool.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
