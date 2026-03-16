import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TipJar with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const TipJar = await ethers.getContractFactory("TipJar");
  const tipJar = await TipJar.deploy();
  await tipJar.waitForDeployment();

  console.log("TipJar deployed to:", await tipJar.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
