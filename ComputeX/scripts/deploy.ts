import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ComputeExchange with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const ComputeExchange = await ethers.getContractFactory("ComputeExchange");
  const exchange = await ComputeExchange.deploy();
  await exchange.waitForDeployment();

  const address = await exchange.getAddress();
  console.log("ComputeExchange deployed to:", address);
  console.log("Platform fee:", (await exchange.platformFee()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
