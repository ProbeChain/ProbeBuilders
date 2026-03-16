import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying TicketNFT with account:", deployer.address);

  const feeBPS = 250; // 2.5%

  const Factory = await ethers.getContractFactory("TicketNFT");
  const contract = await Factory.deploy(feeBPS);
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log("TicketNFT deployed to:", address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
