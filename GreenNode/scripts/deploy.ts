import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying GreenEnergy with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const GreenEnergy = await ethers.getContractFactory("GreenEnergy");
  const green = await GreenEnergy.deploy();
  await green.waitForDeployment();

  const address = await green.getAddress();
  console.log("GreenEnergy deployed to:", address);
  console.log("Owner:", await green.owner());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
