import { ethers } from "hardhat";

async function main() {
  console.log("Deploying ReputationSystem to Rydberg Testnet...");
  const ReputationSystem = await ethers.getContractFactory("ReputationSystem");
  const reputation = await ReputationSystem.deploy();
  await reputation.waitForDeployment();

  const address = await reputation.getAddress();
  console.log(`ReputationSystem deployed at: ${address}`);
  console.log(`Dimensions: Reliability(30%), Speed(20%), Accuracy(30%), Cooperation(20%)`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
