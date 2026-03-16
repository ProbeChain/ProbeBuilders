import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying SimpleSwapRouter with account:", deployer.address);

  const SimpleSwapRouter = await ethers.getContractFactory("SimpleSwapRouter");
  const router = await SimpleSwapRouter.deploy();
  await router.waitForDeployment();
  const routerAddr = await router.getAddress();

  console.log("SimpleSwapRouter deployed to:", routerAddr);
  console.log("---");
  console.log("Save these addresses in your .env or frontend config.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
