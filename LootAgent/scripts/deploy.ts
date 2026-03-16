import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying LootDistributor with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const LootDistributor = await ethers.getContractFactory("LootDistributor");
  const lootDistributor = await LootDistributor.deploy();
  await lootDistributor.waitForDeployment();

  const address = await lootDistributor.getAddress();
  console.log("LootDistributor deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
