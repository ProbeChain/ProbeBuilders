import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying RWAToken with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const RWAToken = await ethers.getContractFactory("RWAToken");
  const rwa = await RWAToken.deploy();
  await rwa.waitForDeployment();

  console.log("RWAToken deployed to:", await rwa.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
