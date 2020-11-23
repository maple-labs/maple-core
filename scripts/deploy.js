const { deploy } = require("@maplelabs/hardhat-scripts");

const mintableUSDC = require("../../contracts/localhost/addresses/MintableTokenUSDC.address.js");
const uniswapRouter = require("../../contracts/localhost/addresses/UniswapV2Router02.address.js");

async function main() {
  const mapleToken = await deploy("MapleToken", [
    "MapleToken",
    "MPL",
    mintableUSDC,
  ]);

  // Governor = accounts[0]
  const accounts = await ethers.provider.listAccounts();

  const mapleGlobals = await deploy("MapleGlobals", [
    accounts[0],
    mapleToken.address,
  ]);

  const LPStakeLockerFactory = await deploy("LPStakeLockerFactory");

  const liquidAssetLockerFactory = await deploy("LiquidAssetLockerFactory");

  const LPFactory = await deploy("LPFactory");

  const mapleTreasury = await deploy("MapleTreasury", [
    mapleToken.address,
    mintableUSDC,
    uniswapRouter,
    mapleGlobals.address,
  ]);

  const updateGlobals = await mapleGlobals.setMapleTreasury(
    mapleTreasury.address
  );

  const LVFactory = await deploy("LoanVaultFactory");

  const CollateralLockerFactory = await deploy(
    "LoanVaultCollateralLockerFactory",
    [LVFactory.address]
  );

  const FundingLockerFactory = await deploy("LoanVaultFundingLockerFactory", [
    LVFactory.address,
  ]);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
