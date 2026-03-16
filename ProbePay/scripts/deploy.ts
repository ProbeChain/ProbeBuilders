import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying PaymentGateway with account:", deployer.address);

  const PaymentGateway = await ethers.getContractFactory("PaymentGateway");
  const gateway = await PaymentGateway.deploy(deployer.address);
  await gateway.waitForDeployment();
  console.log("PaymentGateway deployed to:", await gateway.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
