import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying KnowledgeGraph with account:", deployer.address);

  const rewardPerContribution = ethers.parseEther("0.001");

  const Factory = await ethers.getContractFactory("KnowledgeGraph");
  const contract = await Factory.deploy(rewardPerContribution);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("KnowledgeGraph deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
