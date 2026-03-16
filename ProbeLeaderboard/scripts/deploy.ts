import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying Leaderboard with account:", deployer.address);

  const maxTopPlayers = 100;

  const Factory = await ethers.getContractFactory("Leaderboard");
  const contract = await Factory.deploy(maxTopPlayers);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("Leaderboard deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
