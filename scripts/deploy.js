const { deploy } = require("@maplelabs/hardhat-scripts");

const DAIAddress = require("../../contracts/localhost/addresses/MintableTokenDAI.address.js");
const USDCAddress = require("../../contracts/localhost/addresses/MintableTokenUSDC.address.js");
const WETHAddress = require("../../contracts/localhost/addresses/WETH9.address.js");
const WBTCAddress = require("../../contracts/localhost/addresses/WBTC.address.js");
const uniswapRouter = require("../../contracts/localhost/addresses/UniswapV2Router02.address.js");

async function main() {
  const mapleToken = await deploy("MapleToken", [
    "MapleToken",
    "MPL",
    USDCAddress,
  ]);

  // Governor = accounts[0]
  const accounts = await ethers.provider.listAccounts();

  const mapleGlobals = await deploy("MapleGlobals", [
    accounts[0],
    mapleToken.address,
  ]);

  const LPStakeLockerFactory = await deploy("LPStakeLockerFactory");

  const LiquidityLockerFactory = await deploy("LiquidityLockerFactory");

  const LPFactory = await deploy("LPFactory");

  const mapleTreasury = await deploy("MapleTreasury", [
    mapleToken.address,
    USDCAddress,
    uniswapRouter,
    mapleGlobals.address,
  ]);

  const updateGlobals = await mapleGlobals.setMapleTreasury(
    mapleTreasury.address
  );

  await mapleGlobals.addCollateralToken(DAIAddress);
  await mapleGlobals.addBorrowToken(DAIAddress);
  await mapleGlobals.addCollateralToken(USDCAddress);
  await mapleGlobals.addBorrowToken(USDCAddress);
  await mapleGlobals.addCollateralToken(WETHAddress);
  await mapleGlobals.addBorrowToken(WETHAddress);
  await mapleGlobals.addCollateralToken(WBTCAddress);
  await mapleGlobals.addBorrowToken(WBTCAddress);

  // TODO: Create repayment calculators, use bunk ones temporarily.
  const BUNK_ADDRESS_AMORTIZATION =
    "0x0000000000000000000000000000000000000001";
  const BUNK_ADDRESS_BULLET = "0x0000000000000000000000000000000000000002";
  const updateGlobalsRepaymentCalcAmortization = await mapleGlobals.setInterestStructureCalculator(
    ethers.utils.formatBytes32String("AMORTIZATION"),
    BUNK_ADDRESS_AMORTIZATION
  );
  const updateGlobalsRepaymentCalcBullet = await mapleGlobals.setInterestStructureCalculator(
    ethers.utils.formatBytes32String("BULLET"),
    BUNK_ADDRESS_BULLET
  );

  const CollateralLockerFactory = await deploy(
    "LoanVaultCollateralLockerFactory"
  );

  const FundingLockerFactory = await deploy("LoanVaultFundingLockerFactory");

  const LVFactory = await deploy("LoanVaultFactory", [
    mapleGlobals.address,
    FundingLockerFactory.address,
    CollateralLockerFactory.address,
  ]);

  const updateFundingLockerFactory = await LVFactory.setFundingLockerFactory(
    FundingLockerFactory.address
  );

  const updateCollateralLockerFactory = await LVFactory.setCollateralLockerFactory(
    CollateralLockerFactory.address
  );

  await mapleGlobals.setLiquidityPoolFactory(LPFactory.address);

  await mapleGlobals.setLoanVaultFactory(LVFactory.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
