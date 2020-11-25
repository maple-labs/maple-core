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

  // TODO: Create repayment calculators, use bunk ones temporarily.
  const BUNK_ADDRESS_AMORTIZATION = "0x0000000000000000000000000000000000000001";
  const BUNK_ADDRESS_BULLET = "0x0000000000000000000000000000000000000002";
  const updateGlobalsRepaymentCalcAmortization = await mapleGlobals.setInterestStructureCalculator(
    ethers.utils.formatBytes32String('AMORTIZATION'),
    BUNK_ADDRESS_AMORTIZATION
  );
  const updateGlobalsRepaymentCalcBullet = await mapleGlobals.setInterestStructureCalculator(
    ethers.utils.formatBytes32String('BULLET'),
    BUNK_ADDRESS_BULLET
  );

  const CollateralLockerFactory = await deploy("LoanVaultCollateralLockerFactory",);

  const FundingLockerFactory = await deploy("LoanVaultFundingLockerFactory");

  const LVFactory = await deploy("LoanVaultFactory", [
    mapleGlobals.address,
    FundingLockerFactory.address,
    CollateralLockerFactory.address
  ]);

  const updateFundingLockerFactory = await LVFactory.setFundingLockerFactory(
    FundingLockerFactory.address
  );

  const updateCollateralLockerFactory = await LVFactory.setCollateralLockerFactory(
    CollateralLockerFactory.address
  );

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
