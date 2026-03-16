import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying OTCDesk with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const OTCDesk = await ethers.getContractFactory("OTCDesk");
  const desk = await OTCDesk.deploy();
  await desk.waitForDeployment();

  const address = await desk.getAddress();
  console.log("OTCDesk deployed to:", address);
  console.log("Owner:", await desk.owner());
  console.log("Fee (bps):", (await desk.feeBps()).toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
