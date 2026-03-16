import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying RaceTrack with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  // Use deployer as initial oracle
  const oracleAddress = deployer.address;

  const RaceTrack = await ethers.getContractFactory("RaceTrack");
  const raceTrack = await RaceTrack.deploy(oracleAddress);
  await raceTrack.waitForDeployment();

  const address = await raceTrack.getAddress();
  console.log("RaceTrack deployed to:", address);
  console.log("Oracle set to:", oracleAddress);
  console.log("Current season:", (await raceTrack.currentSeason()).toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
