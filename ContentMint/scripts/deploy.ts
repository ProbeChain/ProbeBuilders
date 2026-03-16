import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ContentNFT with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const ContentNFT = await ethers.getContractFactory("ContentNFT");
  const contentNFT = await ContentNFT.deploy();
  await contentNFT.waitForDeployment();

  const address = await contentNFT.getAddress();
  console.log("ContentNFT deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
