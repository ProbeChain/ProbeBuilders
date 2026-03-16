import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying GraphAnalytics with account:", deployer.address);

  const Factory = await ethers.getContractFactory("GraphAnalytics");
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("GraphAnalytics deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
