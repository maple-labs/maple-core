const { expect } = require("chai");
const { BigNumber } = require("ethers");
const artpath = "../../contracts/" + network.name + "/";

const BCreatorABI = require(artpath + "abis/BCreator.abi.js");
const BCreatorAddress = require(artpath + "addresses/BCreator.address.js");

const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");
const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
const WETHAddress = require(artpath + "addresses/WETH9.address.js");
const WBTCAddress = require(artpath + "addresses/WBTC.address.js");

const MapleGlobalsAddress = require(artpath +
  "addresses/MapleGlobals.address.js");
const MapleGlobalsABI = require(artpath + "abis/MapleGlobals.abi.js");
const LoanVaultFactoryAddress = require(artpath +
  "addresses/LoanVaultFactory.address.js");
const LoanVaultFactoryABI = require(artpath + "abis/LoanVaultFactory.abi.js");
const LiquidityPoolFactoryAddress = require(artpath +
  "addresses/LiquidityPoolFactory.address");
const CollateralLockerFactoryAddress = require(artpath +
  "addresses/CollateralLockerFactory.address.js");
const mapleTreasuryAddress = require(artpath +
  "addresses/MapleTreasury.address.js");
const FundingLockerFactoryAddress = require(artpath +
  "addresses/FundingLockerFactory.address.js");
const ChainLinkFactoryAddress = require(artpath +
  "addresses/ChainLinkEmulatorFactory.address.js");
const ChainLinkFactoryABI = require(artpath +
  "abis/ChainLinkEmulatorFactory.abi.js");

const ChainLinkEmulatorABI = require(artpath + "abis/ChainLinkEmulator.abi.js");
async function main() {
  ChainLinkFactory = new ethers.Contract(
    ChainLinkFactoryAddress,
    ChainLinkFactoryABI,
    ethers.provider.getSigner(0)
  );

  // Fetch the official Maple balancer pool address.
  BCreator = new ethers.Contract(
    BCreatorAddress,
    BCreatorABI,
    ethers.provider.getSigner(0)
  );
  MapleBPoolAddress = await BCreator.getBPoolAddress(0);

  mapleGlobals = new ethers.Contract(
    MapleGlobalsAddress,
    MapleGlobalsABI,
    ethers.provider.getSigner(0)
  );

  await mapleGlobals.setMapleBPool(MapleBPoolAddress);
  await mapleGlobals.setMapleBPoolAssetPair(USDCAddress);

  // Update the MapleGlobals pool delegate whitelist.
  const accounts = await ethers.provider.listAccounts();

  await mapleGlobals.setPoolDelegateWhitelist(accounts[0], true);
  await mapleGlobals.setPoolDelegateWhitelist(accounts[1], true);
  await mapleGlobals.setPoolDelegateWhitelist(accounts[2], true);
  await mapleGlobals.setPoolDelegateWhitelist(accounts[3], true);
  await mapleGlobals.setPoolDelegateWhitelist(accounts[4], true);
  await mapleGlobals.setPoolDelegateWhitelist(accounts[5], true);
  await mapleGlobals.setPoolDelegateWhitelist(accounts[6], true);
  await mapleGlobals.setPoolDelegateWhitelist(accounts[7], true);
  await mapleGlobals.setPoolDelegateWhitelist(accounts[8], true);

  const PAIR_ONE = "ETH / USD";
  const PAIR_TWO = "BTC / USD";
  const PAIR_THREE = "DAI / USD";

  const ETH_USD_ORACLE_ADDRESS = ChainLinkFactory.getOracle(PAIR_ONE);
  const BTC_USD_ORACLE_ADDRESS = ChainLinkFactory.getOracle(PAIR_TWO);
  const DAI_USD_ORACLE_ADDRESS = ChainLinkFactory.getOracle(PAIR_THREE);

  await mapleGlobals.assignPriceFeed(USDCAddress, DAI_USD_ORACLE_ADDRESS);
  await mapleGlobals.assignPriceFeed(DAIAddress, DAI_USD_ORACLE_ADDRESS);
  await mapleGlobals.assignPriceFeed(WBTCAddress, BTC_USD_ORACLE_ADDRESS);
  await mapleGlobals.assignPriceFeed(WETHAddress, ETH_USD_ORACLE_ADDRESS);

  const updateGlobals = await mapleGlobals.setMapleTreasury(
    mapleTreasuryAddress
  );

  await mapleGlobals.addBorrowToken(USDCAddress);
  await mapleGlobals.addBorrowToken(DAIAddress);
  await mapleGlobals.addCollateralToken(DAIAddress);
  await mapleGlobals.addCollateralToken(USDCAddress);
  await mapleGlobals.addCollateralToken(WETHAddress);
  await mapleGlobals.addCollateralToken(WBTCAddress);

  // TODO: Create repayment calculators, use bunk ones temporarily.
/*  const BUNK_ADDRESS_AMORTIZATION =
    "0x0000000000000000000000000000000000000001";
  const BUNK_ADDRESS_BULLET = "0x0000000000000000000000000000000000000002";
  const updateGlobalsRepaymentCalcAmortization = await mapleGlobals.setInterestStructureCalculator(
    ethers.utils.formatBytes32String("AMORTIZATION"),
    BUNK_ADDRESS_AMORTIZATION
  );
  const updateGlobalsRepaymentCalcBullet = await mapleGlobals.setInterestStructureCalculator(
    ethers.utils.formatBytes32String("BULLET"),
    BUNK_ADDRESS_BULLET
  );*/

  const AmortizationRepaymentCalculator = await deploy("AmortizationRepaymentCalculator");
  const BulletRepaymentCalculator = await deploy("BulletRepaymentCalculator");

  await mapleGlobals.setInterestStructureCalculator(
    ethers.utils.formatBytes32String("AMORTIZATION"),
    AmortizationRepaymentCalculator.address
  );
  await mapleGlobals.setInterestStructureCalculator(
    ethers.utils.formatBytes32String("BULLET"),
    BulletRepaymentCalculator.address
  );



  const LVFactory = new ethers.Contract(
    LoanVaultFactoryAddress,
    LoanVaultFactoryABI,
    ethers.provider.getSigner(0)
  );

  const updateFundingLockerFactory = await LVFactory.setFundingLockerFactory(
    FundingLockerFactoryAddress
  );

  const updateCollateralLockerFactory = await LVFactory.setCollateralLockerFactory(
    CollateralLockerFactoryAddress
  );

  await mapleGlobals.setLiquidityPoolFactory(LiquidityPoolFactoryAddress);
  await mapleGlobals.setLoanVaultFactory(LoanVaultFactoryAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
