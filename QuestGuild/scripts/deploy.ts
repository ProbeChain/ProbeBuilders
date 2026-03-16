import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying QuestAggregator with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const QuestAggregator = await ethers.getContractFactory("QuestAggregator");
  const questAggregator = await QuestAggregator.deploy();
  await questAggregator.waitForDeployment();

  const address = await questAggregator.getAddress();
  console.log("QuestAggregator deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
