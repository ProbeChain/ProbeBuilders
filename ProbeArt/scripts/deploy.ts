import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying ArtGallery with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  const ArtGallery = await ethers.getContractFactory("ArtGallery");
  const artGallery = await ArtGallery.deploy();
  await artGallery.waitForDeployment();

  const address = await artGallery.getAddress();
  console.log("ArtGallery deployed to:", address);

  // Set feature threshold: 3 curators, min 70 avg score
  const tx = await artGallery.setFeatureThreshold(3, 70);
  await tx.wait();
  console.log("Feature threshold: 3 curators, min score 70");

  console.log("Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
