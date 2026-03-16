import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying PortfolioVault with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const PortfolioVault = await ethers.getContractFactory("PortfolioVault");
  const vault = await PortfolioVault.deploy();
  await vault.waitForDeployment();

  const address = await vault.getAddress();
  console.log("PortfolioVault deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
