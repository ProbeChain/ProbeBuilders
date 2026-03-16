import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying DocBounty with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const DocBounty = await ethers.getContractFactory("DocBounty");
  const bounty = await DocBounty.deploy();
  await bounty.waitForDeployment();

  console.log("DocBounty deployed to:", await bounty.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
