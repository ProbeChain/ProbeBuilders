import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying UpgradeableProxy with account:", deployer.address);
  console.log("Balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)));

  // NOTE: In production, deploy your implementation contract first,
  // then pass its address as the first constructor argument.
  // This example uses a placeholder — replace with your actual implementation.
  //
  // const Implementation = await ethers.getContractFactory("YourImplementation");
  // const impl = await Implementation.deploy();
  // await impl.waitForDeployment();
  // const implAddr = await impl.getAddress();

  // For demonstration, we deploy with the deployer as admin and empty init data.
  // You MUST provide a valid implementation address when deploying.
  console.log("To deploy UpgradeableProxy:");
  console.log("  1. Deploy your implementation contract first");
  console.log("  2. Call: UpgradeableProxy.deploy(implAddress, adminAddress, initData)");
  console.log("");
  console.log("Example:");
  console.log("  const Proxy = await ethers.getContractFactory('UpgradeableProxy');");
  console.log("  const proxy = await Proxy.deploy(implAddr, deployer.address, '0x');");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
