import { ethers } from "hardhat";

async function main() {
  console.log("Deploying GenerativeArt to ProbeChain Rydberg Testnet...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "PRB");

  const GenerativeArt = await ethers.getContractFactory("GenerativeArt");
  const art = await GenerativeArt.deploy();
  await art.waitForDeployment();

  const address = await art.getAddress();
  console.log("GenerativeArt deployed to:", address);
  console.log("Platform fee:", (await art.platformFeeBps()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
