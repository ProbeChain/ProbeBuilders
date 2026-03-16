import { ethers } from "hardhat";

async function main() {
  console.log("Deploying CommitRevealVote to Rydberg Testnet...");
  const CommitRevealVote = await ethers.getContractFactory("CommitRevealVote");
  const vote = await CommitRevealVote.deploy();
  await vote.waitForDeployment();

  const address = await vote.getAddress();
  console.log(`CommitRevealVote deployed at: ${address}`);
  console.log(`Min commit duration: 1 hour`);
  console.log(`Min reveal duration: 1 hour`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
