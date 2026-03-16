import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying NotaryService with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const NotaryService = await ethers.getContractFactory("NotaryService");
  const notary = await NotaryService.deploy();
  await notary.waitForDeployment();

  const address = await notary.getAddress();
  console.log("NotaryService deployed to:", address);
  console.log("Owner:", await notary.owner());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
