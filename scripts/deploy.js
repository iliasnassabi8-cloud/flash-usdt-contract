// This script deploys the FlashUSDT contract

async function main() {
  console.log("Deploying FlashUSDT contract...");

  const FlashUSDT = await ethers.getContractFactory("FlashUSDT");
  const flashUSDT = await FlashUSDT.deploy();

  await flashUSDT.deployed();

  console.log("FlashUSDT contract deployed to:", flashUSDT.address);
  console.log("Owner:", await flashUSDT.owner());
  console.log("Total Supply:", await flashUSDT.totalSupply());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
