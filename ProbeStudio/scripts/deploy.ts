import { ethers } from "hardhat";

async function main() {
  console.log("Deploying CreatorStudio to ProbeChain Rydberg Testnet...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "PRB");

  const CreatorStudio = await ethers.getContractFactory("CreatorStudio");
  const studio = await CreatorStudio.deploy();
  await studio.waitForDeployment();

  const address = await studio.getAddress();
  console.log("CreatorStudio deployed to:", address);
  console.log("Platform fee:", (await studio.platformFeeBps()).toString(), "bps");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
