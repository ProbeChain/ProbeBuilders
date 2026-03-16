import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying BattleArena with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const BattleArena = await ethers.getContractFactory("BattleArena");
  const arena = await BattleArena.deploy();
  await arena.waitForDeployment();

  console.log("BattleArena deployed to:", await arena.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
