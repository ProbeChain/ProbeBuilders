import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying EscrowService with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const EscrowService = await ethers.getContractFactory("EscrowService");
  const escrow = await EscrowService.deploy();
  await escrow.waitForDeployment();

  const address = await escrow.getAddress();
  console.log("EscrowService deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
