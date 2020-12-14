const { deploy } = require("@maplelabs/hardhat-scripts");
const artpath = '../../contracts/' + network.name + '/';

const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");
const WETHAddress = require(artpath + "addresses/WETH9.address.js");
const WBTCAddress = require(artpath + "addresses/WBTC.address.js");
const uniswapRouter = require(artpath + "addresses/UniswapV2Router02.address.js");
const ChainLinkFactoryAddress = require(artpath + "addresses/ChainLinkEmulatorFactory.address.js");
const ChainLinkFactoryABI = require(artpath + "abis/ChainLinkEmulatorFactory.abi.js");

const ChainLinkEmulatorABI = require(artpath + "abis/ChainLinkEmulator.abi.js");

async function main() {

  ChainLinkFactory = new ethers.Contract(
    ChainLinkFactoryAddress,
    ChainLinkFactoryABI,
    ethers.provider.getSigner(0)
  );

  const PAIR_ONE = "ETH / USD";
  const PAIR_TWO = "BTC / USD";
  const PAIR_THREE = "DAI / USD";

  await ChainLinkFactory.newAgg(PAIR_ONE);
  await ChainLinkFactory.newAgg(PAIR_TWO);
  await ChainLinkFactory.newAgg(PAIR_THREE);

  const ETH_USD_ORACLE_ADDRESS = ChainLinkFactory.getOracle(PAIR_ONE);
  const BTC_USD_ORACLE_ADDRESS = ChainLinkFactory.getOracle(PAIR_TWO);
  const DAI_USD_ORACLE_ADDRESS = ChainLinkFactory.getOracle(PAIR_THREE);

  ETH_USD_ORACLE = new ethers.Contract(
    ETH_USD_ORACLE_ADDRESS,
    ChainLinkEmulatorABI,
    ethers.provider.getSigner(0)
  );
  BTC_USD_ORACLE = new ethers.Contract(
    BTC_USD_ORACLE_ADDRESS,
    ChainLinkEmulatorABI,
    ethers.provider.getSigner(0)
  );
  DAI_USD_ORACLE = new ethers.Contract(
    DAI_USD_ORACLE_ADDRESS,
    ChainLinkEmulatorABI,
    ethers.provider.getSigner(0)
  );
  
  // Note: All ChainLink price feeds use 8 decimals for precision.
  await ETH_USD_ORACLE.setPrice("59452607912");
  await BTC_USD_ORACLE.setPrice("1895510185012");
  await DAI_USD_ORACLE.setPrice("100232161");

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

  const StakeLockerFactory = await deploy("StakeLockerFactory");

  const LiquidityLockerFactory = await deploy("LiquidityLockerFactory");

  const LiquidityPoolFactory = await deploy("LiquidityPoolFactory", [
    mapleGlobals.address,
    StakeLockerFactory.address,
    LiquidityLockerFactory.address,
  ]);

  const mapleTreasury = await deploy("MapleTreasury", [
    mapleToken.address,
    USDCAddress,
    uniswapRouter,
    mapleGlobals.address,
  ]);

  const updateGlobals = await mapleGlobals.setMapleTreasury(
    mapleTreasury.address
  );

  await mapleGlobals.addBorrowToken(USDCAddress);
  await mapleGlobals.addBorrowToken(DAIAddress);
  await mapleGlobals.addCollateralToken(DAIAddress);
  await mapleGlobals.addCollateralToken(USDCAddress);
  await mapleGlobals.addCollateralToken(WETHAddress);
  await mapleGlobals.addCollateralToken(WBTCAddress);

  const AmortizationRepaymentCalculator = await deploy("AmortizationRepaymentCalculator");
  const BulletRepaymentCalculator = await deploy("BulletRepaymentCalculator");

  await mapleGlobals.setInterestStructureCalculator(
    ethers.utils.formatBytes32String("AMORTIZATION"),
    AmortizationRepaymentCalculator.address
  );
  await mapleGlobals.setInterestStructureCalculator(
    ethers.utils.formatBytes32String("BULLET"),
    BulletRepaymentCalculator.BUNK_ADDRESS_BULLET
  );

  const CollateralLockerFactory = await deploy(
    "CollateralLockerFactory"
  );

  const FundingLockerFactory = await deploy("FundingLockerFactory");

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

  await mapleGlobals.setLiquidityPoolFactory(LiquidityPoolFactory.address);
  await mapleGlobals.setLoanVaultFactory(LVFactory.address);

  await mapleGlobals.assignPriceFeed(USDCAddress, DAI_USD_ORACLE_ADDRESS);
  await mapleGlobals.assignPriceFeed(DAIAddress, DAI_USD_ORACLE_ADDRESS);
  await mapleGlobals.assignPriceFeed(WBTCAddress, BTC_USD_ORACLE_ADDRESS);
  await mapleGlobals.assignPriceFeed(WETHAddress, ETH_USD_ORACLE_ADDRESS);
  
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
