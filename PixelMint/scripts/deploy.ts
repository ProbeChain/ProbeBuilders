import { ethers } from "hardhat";

async function main() {
  console.log("Deploying ImageMintFactory to ProbeChain Rydberg Testnet...");

  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "PRB");

  const ImageMintFactory = await ethers.getContractFactory("ImageMintFactory");
  const factory = await ImageMintFactory.deploy();
  await factory.waitForDeployment();

  const address = await factory.getAddress();
  console.log("ImageMintFactory deployed to:", address);
  console.log("Mint fee:", ethers.formatEther(await factory.mintFee()), "PRB");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
