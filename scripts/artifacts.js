require("dotenv").config();
/*

By declaring these contants here it's
easier to add more contracts and to
change the names of contracts.

This enables us abstract the import of 
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
  const version = process.env.VERSION || "current";

  if (!contract) {
    throw new Error(`ARTIFACT NOT FOUND IN LOCAL FOLDER: ${contract}`);
  }

  if (!network || !version) {
    throw new Error("NETWORK and VERSION must be set to env");
  }

  return {
    abi: require(`../../contracts/${network}/abis/${contract}.abi.js`),
    address: require(`../../contracts/${network}/addresses/${contract}.address.js`),
  };
}

module.exports = { CORE, DEPS, getArtifacts };
