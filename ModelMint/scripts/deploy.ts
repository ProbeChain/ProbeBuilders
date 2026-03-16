import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ModelNFT with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const ModelNFT = await ethers.getContractFactory("ModelNFT");
  const model = await ModelNFT.deploy();
  await model.waitForDeployment();

  console.log("ModelNFT deployed to:", await model.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
