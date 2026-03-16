import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying DCAVault with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const DCAVault = await ethers.getContractFactory("DCAVault");
  const vault = await DCAVault.deploy();
  await vault.waitForDeployment();

  const address = await vault.getAddress();
  console.log("DCAVault deployed to:", address);
  console.log("Owner:", await vault.owner());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
