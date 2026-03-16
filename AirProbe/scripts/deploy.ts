import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying AirQualityDAO with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const AirQualityDAO = await ethers.getContractFactory("AirQualityDAO");
  const dao = await AirQualityDAO.deploy();
  await dao.waitForDeployment();

  const address = await dao.getAddress();
  console.log("AirQualityDAO deployed to:", address);
  console.log("Member count:", (await dao.memberCount()).toString());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
