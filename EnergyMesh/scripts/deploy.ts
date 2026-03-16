import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying EnergyMarket with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const EnergyMarket = await ethers.getContractFactory("EnergyMarket");
  const market = await EnergyMarket.deploy();
  await market.waitForDeployment();

  const address = await market.getAddress();
  console.log("EnergyMarket deployed to:", address);
  console.log("Platform fee:", (await market.platformFee()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
