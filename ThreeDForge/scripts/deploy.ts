import { ethers } from "hardhat";

async function main() {
  console.log("Deploying ThreeDMarket to ProbeChain Rydberg Testnet...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "PRB");

  const ThreeDMarket = await ethers.getContractFactory("ThreeDMarket");
  const market = await ThreeDMarket.deploy();
  await market.waitForDeployment();

  const address = await market.getAddress();
  console.log("ThreeDMarket deployed to:", address);
  console.log("Mint fee:", ethers.formatEther(await market.mintFee()), "PRB");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
