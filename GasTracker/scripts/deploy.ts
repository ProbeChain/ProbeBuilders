import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying GasAnalytics with account:", deployer.address);

  const Factory = await ethers.getContractFactory("GasAnalytics");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("GasAnalytics deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
