import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying RoyaltyEnforcer with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  const RoyaltyEnforcer = await ethers.getContractFactory("RoyaltyEnforcer");
  const royaltyEnforcer = await RoyaltyEnforcer.deploy();
  await royaltyEnforcer.waitForDeployment();

  const address = await royaltyEnforcer.getAddress();
  console.log("RoyaltyEnforcer deployed to:", address);

  // Set registration fee
  const tx = await royaltyEnforcer.setRegistrationFee(ethers.parseEther("0.001"));
  await tx.wait();
  console.log("Registration fee set to 0.001 ETH");

  console.log("Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
