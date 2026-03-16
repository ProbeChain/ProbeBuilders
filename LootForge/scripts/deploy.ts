import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying LootForge with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const LootForge = await ethers.getContractFactory("LootForge");
  const loot = await LootForge.deploy();
  await loot.waitForDeployment();

  console.log("LootForge deployed to:", await loot.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
