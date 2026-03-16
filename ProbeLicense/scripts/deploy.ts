import { ethers } from "hardhat";

async function main() {
  console.log("Deploying LicenseManager to ProbeChain Rydberg Testnet...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "PRB");

  const LicenseManager = await ethers.getContractFactory("LicenseManager");
  const manager = await LicenseManager.deploy();
  await manager.waitForDeployment();

  const address = await manager.getAddress();
  console.log("LicenseManager deployed to:", address);
  console.log("Platform fee:", (await manager.platformFeeBps()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
