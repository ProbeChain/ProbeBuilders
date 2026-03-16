import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying SmartFaucet with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  const SmartFaucet = await ethers.getContractFactory("SmartFaucet");
  const faucet = await SmartFaucet.deploy();
  await faucet.waitForDeployment();

  const address = await faucet.getAddress();
  console.log("SmartFaucet deployed to:", address);

  // Optionally fund the faucet
  const fundTx = await deployer.sendTransaction({
    to: address,
    value: ethers.parseEther("1.0"),
  });
  await fundTx.wait();
  console.log("Faucet funded with 1.0 ETH");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
