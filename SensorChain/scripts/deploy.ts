import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying SensorMarket with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const SensorMarket = await ethers.getContractFactory("SensorMarket");
  const market = await SensorMarket.deploy();
  await market.waitForDeployment();

  const address = await market.getAddress();
  console.log("SensorMarket deployed to:", address);
  console.log("Platform fee:", (await market.platformFee()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
