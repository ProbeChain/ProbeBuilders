import { ethers } from "hardhat";

async function main() {
  console.log("Deploying ModelExchange to ProbeChain Rydberg Testnet...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "PRB");

  const ModelExchange = await ethers.getContractFactory("ModelExchange");
  const exchange = await ModelExchange.deploy();
  await exchange.waitForDeployment();

  const address = await exchange.getAddress();
  console.log("ModelExchange deployed to:", address);
  console.log("Platform fee:", (await exchange.platformFeeBps()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
