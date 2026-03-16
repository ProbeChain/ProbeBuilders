import { ethers } from "hardhat";

async function main() {
  console.log("Deploying SkillMarketplace to Rydberg Testnet...");
  const SkillMarketplace = await ethers.getContractFactory("SkillMarketplace");
  const marketplace = await SkillMarketplace.deploy();
  await marketplace.waitForDeployment();

  const address = await marketplace.getAddress();
  console.log(`SkillMarketplace deployed at: ${address}`);
  console.log(`Platform fee: 2.5%`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
