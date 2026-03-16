import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying EventLogger with account:", deployer.address);

  const defaultSubDuration = 30 * 86400; // 30 days

  const Factory = await ethers.getContractFactory("EventLogger");
  const contract = await Factory.deploy(defaultSubDuration);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("EventLogger deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
