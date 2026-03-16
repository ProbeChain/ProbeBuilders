import { ethers } from "hardhat";

async function main() {
  console.log("Deploying MusicRights to ProbeChain Rydberg Testnet...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "PRB");

  const MusicRights = await ethers.getContractFactory("MusicRights");
  const music = await MusicRights.deploy();
  await music.waitForDeployment();

  const address = await music.getAddress();
  console.log("MusicRights deployed to:", address);
  console.log("Default stream price:", ethers.formatEther(await music.defaultStreamPrice()), "PRB");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
