import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying CarbonCredit with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const CarbonCredit = await ethers.getContractFactory("CarbonCredit");
  const carbon = await CarbonCredit.deploy();
  await carbon.waitForDeployment();

  const address = await carbon.getAddress();
  console.log("CarbonCredit deployed to:", address);
  console.log("Name:", await carbon.name());
  console.log("Symbol:", await carbon.symbol());
  console.log("Owner:", await carbon.owner());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
