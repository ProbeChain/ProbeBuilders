import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TemplateStore with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const TemplateStore = await ethers.getContractFactory("TemplateStore");
  const store = await TemplateStore.deploy();
  await store.waitForDeployment();

  console.log("TemplateStore deployed to:", await store.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
