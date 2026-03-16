import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying PaymentStream with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const PaymentStream = await ethers.getContractFactory("PaymentStream");
  const stream = await PaymentStream.deploy();
  await stream.waitForDeployment();

  const address = await stream.getAddress();
  console.log("PaymentStream deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
