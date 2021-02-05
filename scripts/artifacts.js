require("dotenv").config();
const path = require("path");
/*

By declaring these contants here it's
easier to add more contracts and to
change the names of contracts.

This enables us to abstractly import
artifacts from the scripts to use statically
defined addresses and abis for
mainnet or other networks.

*/

const CORE = {
  Loan: "Loan",
  Pool: "Pool",

  // Factories
  CollateralLockerFactory: "CollateralLockerFactory",
  LiquidityLockerFactory: "LiquidityLockerFactory",
  FundingLockerFactory: "FundingLockerFactory",
  StakeLockerFactory: "StakeLockerFactory",
  DebtLockerFactory: "DebtLockerFactory",
  PoolFactory: "PoolFactory",
  LoanFactory: "LoanFactory",

  // External Library
  CalcBPool: "CalcBPool",

  // Lockers
  LiquidityLocker: "LiquidityLocker",
  CollateralLocker: "CollateralLocker",
  StakeLocker: "StakeLocker",
  DebtLocker: "DebtLocker",

  // Dao
  MapleTreasury: "MapleTreasury",
  MapleGlobals: "MapleGlobals",
  MapleToken: "MapleToken",

  // calculators
  BulletRepaymentCalc: "BulletRepaymentCalc",
  PremiumCalc: "PremiumCalc",
  LateFeeCalc: "LateFeeCalc",

  // dummy
  MockPriceFeedUSDC: 'MockPriceFeedUSDC',
  MockPriceFeedWETH: 'MockPriceFeedWETH',
  MockPriceFeedWBTC: 'MockPriceFeedWBTC',
};

const DEPS = {
  WETH: "WETH9",
  WBTC: "WBTC",
  DAI: "MintableTokenDAI",
  USDC: "MintableTokenUSDC",
  BFactory: "BFactory",
  UniswapV2Router02: "UniswapV2Router02",
  ChainLinkFactory: "ChainLinkEmulatorFactory",
};

/*

  A helper function that imports the 
  artifacts from a local folder

*/

function getArtifacts(contract) {
  const network = process.env.NETWORK || "localhost";

  if (!contract) {
    throw new Error(`ARTIFACT NOT FOUND IN LOCAL FOLDER: ${contract}`);
  }

  if (!network) {
    console.log("WARNING: NETWORK isn't set in env variables");
  }

  const contractsDir = path.join(__dirname, "../../contracts");

  return {
    abi: require(`${contractsDir}/${network}/abis/${contract}.abi.js`),
    address: require(`${contractsDir}/${network}/addresses/${contract}.address.js`),
  };
}

module.exports = { CORE, DEPS, getArtifacts };
