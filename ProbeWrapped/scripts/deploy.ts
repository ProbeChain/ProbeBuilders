import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TokenWrapper with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

  const TokenWrapper = await ethers.getContractFactory("TokenWrapper");
  const wrapper = await TokenWrapper.deploy();
  await wrapper.waitForDeployment();

  const address = await wrapper.getAddress();
  console.log("TokenWrapper (wPROBE) deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
