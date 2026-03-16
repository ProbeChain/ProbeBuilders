import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying AggregatorRouter with account:", deployer.address);

  const AggregatorRouter = await ethers.getContractFactory("AggregatorRouter");
  const router = await AggregatorRouter.deploy(deployer.address); // fee collector = deployer
  await router.waitForDeployment();
  console.log("AggregatorRouter deployed to:", await router.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
