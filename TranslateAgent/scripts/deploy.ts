import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TranslationBounty with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const TranslationBounty = await ethers.getContractFactory("TranslationBounty");
  const bounty = await TranslationBounty.deploy();
  await bounty.waitForDeployment();

  console.log("TranslationBounty deployed to:", await bounty.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
