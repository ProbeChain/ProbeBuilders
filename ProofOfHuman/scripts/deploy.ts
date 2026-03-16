import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying HumanVerifier with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const HumanVerifier = await ethers.getContractFactory("HumanVerifier");
  const humanVerifier = await HumanVerifier.deploy();
  await humanVerifier.waitForDeployment();

  const address = await humanVerifier.getAddress();
  console.log("HumanVerifier deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
