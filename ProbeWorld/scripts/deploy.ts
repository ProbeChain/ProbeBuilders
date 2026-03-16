import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying LandRegistry with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const mintFee = ethers.parseEther("0.01"); // 0.01 ETH per cell

  const LandRegistry = await ethers.getContractFactory("LandRegistry");
  const landRegistry = await LandRegistry.deploy(mintFee);
  await landRegistry.waitForDeployment();

  const address = await landRegistry.getAddress();
  console.log("LandRegistry deployed to:", address);
  console.log("Mint fee per cell:", ethers.formatEther(mintFee));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
