import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ChessTournament with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const ChessTournament = await ethers.getContractFactory("ChessTournament");
  const chessTournament = await ChessTournament.deploy();
  await chessTournament.waitForDeployment();

  const address = await chessTournament.getAddress();
  console.log("ChessTournament deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
