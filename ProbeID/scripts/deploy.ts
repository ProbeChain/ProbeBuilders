import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying UniversalID with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const UniversalID = await ethers.getContractFactory("UniversalID");
  const universalID = await UniversalID.deploy();
  await universalID.waitForDeployment();

  const address = await universalID.getAddress();
  console.log("UniversalID deployed to:", address);
  console.log("Owner:", await universalID.owner());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
