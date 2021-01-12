const { deploy } = require("@maplelabs/hardhat-scripts");
const artpath = "../../contracts/" + network.name + "/";

const DAIAddress              = require(artpath + "addresses/MintableTokenDAI.address.js");
const USDCAddress             = require(artpath + "addresses/MintableTokenUSDC.address.js");
const WETHAddress             = require(artpath + "addresses/WETH9.address.js");
const WBTCAddress             = require(artpath + "addresses/WBTC.address.js");
const uniswapRouter           = require(artpath + "addresses/UniswapV2Router02.address.js");
const ChainLinkFactoryAddress = require(artpath + "addresses/ChainLinkEmulatorFactory.address.js");
const ChainLinkFactoryABI     = require(artpath + "abis/ChainLinkEmulatorFactory.abi.js");
const MapleTokenAddress       = require(artpath + "addresses/MapleToken.address.js");
const ChainLinkEmulatorABI    = require(artpath + "abis/ChainLinkEmulator.abi.js");
const BFactoryAddress         = require(artpath + "addresses/BFactory.address.js");

async function main() {
  /*  const mpl = await deploy("MapleToken", [
    "MapleToken",
    "MPL",
    USDCAddress,
  ]);*/

  // Governor = accounts[0]
  const accounts = await ethers.provider.listAccounts();

  const mapleGlobals = await deploy("MapleGlobals", [
    accounts[0],
    MapleTokenAddress,
    BFactoryAddress
  ]);

  const StakeLockerFactory = await deploy("StakeLockerFactory");

  const LiquidityLockerFactory = await deploy("LiquidityLockerFactory");

  const DebtLockerFactory = await deploy("DebtLockerFactory");

  const PoolFactory = await deploy("PoolFactory", [
    mapleGlobals.address,
    StakeLockerFactory.address,
    LiquidityLockerFactory.address,
  ]);

  const mapleTreasury = await deploy("MapleTreasury", [
    MapleTokenAddress,
    USDCAddress,
    uniswapRouter,
    mapleGlobals.address,
  ]);
  
  const BulletRepaymentCalc = await deploy("BulletRepaymentCalc");

  const LateFeeCalc = await deploy("LateFeeCalc", [0]); // 0% FEE if Late Payment

  const PremiumCalc = await deploy("PremiumCalc", [200]); // 2% FEE on Principal

  const CollateralLockerFactory = await deploy("CollateralLockerFactory");

  const FundingLockerFactory = await deploy("FundingLockerFactory");

  const LVFactory = await deploy("LoanFactory", [
    mapleGlobals.address,
    FundingLockerFactory.address,
    CollateralLockerFactory.address,
  ]);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
