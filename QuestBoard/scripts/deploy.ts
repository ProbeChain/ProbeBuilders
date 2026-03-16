import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying QuestSystem with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const QuestSystem = await ethers.getContractFactory("QuestSystem");
  const quest = await QuestSystem.deploy();
  await quest.waitForDeployment();

  console.log("QuestSystem deployed to:", await quest.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
