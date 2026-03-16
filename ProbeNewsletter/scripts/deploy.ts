import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying NewsletterDAO with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const NewsletterDAO = await ethers.getContractFactory("NewsletterDAO");
  const dao = await NewsletterDAO.deploy();
  await dao.waitForDeployment();

  console.log("NewsletterDAO deployed to:", await dao.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
