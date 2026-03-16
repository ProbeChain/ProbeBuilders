import { ethers } from "hardhat";

async function main() {
  console.log("Deploying VoiceMarket to ProbeChain Rydberg Testnet...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "PRB");

  const VoiceMarket = await ethers.getContractFactory("VoiceMarket");
  const market = await VoiceMarket.deploy();
  await market.waitForDeployment();

  const address = await market.getAddress();
  console.log("VoiceMarket deployed to:", address);
  console.log("Platform fee:", (await market.platformFeeBps()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
