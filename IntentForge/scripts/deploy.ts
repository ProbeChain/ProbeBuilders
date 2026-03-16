import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying IntentEngine with account:", deployer.address);

  const solverStake = ethers.parseEther("0.1");
  const disputeWindow = 3600; // 1 hour
  const feeBPS = 200; // 2%

  const Factory = await ethers.getContractFactory("IntentEngine");
  const contract = await Factory.deploy(solverStake, disputeWindow, feeBPS);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("IntentEngine deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
