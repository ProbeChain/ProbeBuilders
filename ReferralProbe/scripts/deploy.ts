import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ReferralSystem with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const ReferralSystem = await ethers.getContractFactory("ReferralSystem");
  const system = await ReferralSystem.deploy();
  await system.waitForDeployment();

  console.log("ReferralSystem deployed to:", await system.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
