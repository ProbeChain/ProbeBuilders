import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying DigitalPet with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  const DigitalPet = await ethers.getContractFactory("DigitalPet");
  const digitalPet = await DigitalPet.deploy();
  await digitalPet.waitForDeployment();

  const address = await digitalPet.getAddress();
  console.log("DigitalPet deployed to:", address);

  // Set adoption fee
  const tx = await digitalPet.setAdoptionFee(ethers.parseEther("0.001"));
  await tx.wait();
  console.log("Adoption fee set to 0.001 ETH");

  console.log("Deployment complete!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
