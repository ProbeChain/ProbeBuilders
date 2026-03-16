import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TournamentManager with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const TournamentManager = await ethers.getContractFactory("TournamentManager");
  const tournamentManager = await TournamentManager.deploy();
  await tournamentManager.waitForDeployment();

  const address = await tournamentManager.getAddress();
  console.log("TournamentManager deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
