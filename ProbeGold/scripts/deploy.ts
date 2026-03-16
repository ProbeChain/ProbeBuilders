import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying GoldToken with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const GoldToken = await ethers.getContractFactory("GoldToken");
  const gold = await GoldToken.deploy();
  await gold.waitForDeployment();

  const address = await gold.getAddress();
  console.log("GoldToken deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
