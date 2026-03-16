import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying IntentAggregator with account:", deployer.address);

  const minBatch = 2;
  const maxBatch = 50;
  const feeBPS = 300; // 3%

  const Factory = await ethers.getContractFactory("IntentAggregator");
  const contract = await Factory.deploy(minBatch, maxBatch, feeBPS);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("IntentAggregator deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
