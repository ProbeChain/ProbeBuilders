import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying PaperTrading with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const PaperTrading = await ethers.getContractFactory("PaperTrading");
  const paperTrading = await PaperTrading.deploy();
  await paperTrading.waitForDeployment();

  console.log("PaperTrading deployed to:", await paperTrading.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
