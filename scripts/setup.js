const { expect } = require("chai");
const { BigNumber } = require("ethers");
const artpath = "../../contracts/" + network.name + "/";

const BCreatorABI = require(artpath + "abis/BCreator.abi.js");
const BCreatorAddress = require(artpath + "addresses/BCreator.address.js");

const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");
const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
const WETHAddress = require(artpath + "addresses/WETH9.address.js");
const WBTCAddress = require(artpath + "addresses/WBTC.address.js");

const AmortizationRepaymentCalc = require(artpath +
  "addresses/AmortizationRepaymentCalc.address.js");

const BulletRepaymentCalc = require(artpath +
  "addresses/BulletRepaymentCalc.address.js");

const LateFeeCalc = require(artpath +
  "addresses/LateFeeCalc.address.js");

const PremiumCalc = require(artpath +
  "addresses/PremiumCalc.address.js");

const MapleGlobalsAddress = require(artpath +
  "addresses/MapleGlobals.address.js");
const MapleGlobalsABI = require(artpath + "abis/MapleGlobals.abi.js");
const LoanFactoryAddress = require(artpath +
  "addresses/LoanFactory.address.js");
const LoanFactoryABI = require(artpath + "abis/LoanFactory.abi.js");
const PoolFactoryAddress = require(artpath +
  "addresses/PoolFactory.address");
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

  await mapleGlobals.setLoanAsset(USDCAddress, true);
  await mapleGlobals.setLoanAsset(DAIAddress, true);
  await mapleGlobals.setCollateralAsset(DAIAddress, true);
  await mapleGlobals.setCollateralAsset(USDCAddress, true);
  await mapleGlobals.setCollateralAsset(WETHAddress, true);
  await mapleGlobals.setCollateralAsset(WBTCAddress, true);

  await mapleGlobals.setCalc(AmortizationRepaymentCalc, true);
  await mapleGlobals.setCalc(BulletRepaymentCalc, true);
  await mapleGlobals.setCalc(LateFeeCalc, true);
  await mapleGlobals.setCalc(PremiumCalc, true);

  const LVFactory = new ethers.Contract(
    LoanFactoryAddress,
    LoanFactoryABI,
    ethers.provider.getSigner(0)
  );

  const updateFundingLockerFactory = await LVFactory.setFundingLockerFactory(
    FundingLockerFactoryAddress
  );

  const updateCollateralLockerFactory = await LVFactory.setCollateralLockerFactory(
    CollateralLockerFactoryAddress
  );

  await mapleGlobals.setPoolFactory(PoolFactoryAddress);
  await mapleGlobals.setLoanFactory(LoanFactoryAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
