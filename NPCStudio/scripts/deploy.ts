import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying NPCRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const NPCRegistry = await ethers.getContractFactory("NPCRegistry");
  const npcRegistry = await NPCRegistry.deploy();
  await npcRegistry.waitForDeployment();

  const address = await npcRegistry.getAddress();
  console.log("NPCRegistry deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
