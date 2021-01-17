/*
  This script sets default global values
*/
const { ethers } = require("hardhat");
const { getArtifacts, CORE, DEPS } = require("./artifacts");

async function main() {
  // Get Dependency artifacts
  const DAI = getArtifacts(DEPS.DAI);
  const USDC = getArtifacts(DEPS.USDC);
  const WBTC = getArtifacts(DEPS.WBTC);
  const WETH = getArtifacts(DEPS.WETH);
  const ChainLinkFactory = getArtifacts(DEPS.ChainLinkFactory);

  // Get Maple Core artifacts
  const LateFeeCalc = getArtifacts(CORE.LateFeeCalc);
  const PremiumCalc = getArtifacts(CORE.PremiumCalc);
  const BulletRepaymentCalc = getArtifacts(CORE.BulletRepaymentCalc);

  const MapleGlobals = getArtifacts(CORE.MapleGlobals);
  const MapleTreasury = getArtifacts(CORE.MapleTreasury);

  const LoanFactory = getArtifacts(CORE.LoanFactory);
  const PoolFactory = getArtifacts(CORE.PoolFactory);

  const StakeLockerFactory = getArtifacts(CORE.StakeLockerFactory);
  const FundingLockerFactory = getArtifacts(CORE.FundingLockerFactory);
  const LiquidityLockerFactory = getArtifacts(CORE.LiquidityLockerFactory);
  const CollateralLockerFactory = getArtifacts(CORE.CollateralLockerFactory);

  const signer = ethers.provider.getSigner(0);

  const chainLinkFactory = new ethers.Contract(
    ChainLinkFactory.address,
    ChainLinkFactory.abi,
    signer
  );

  const mapleGlobals = new ethers.Contract(
    MapleGlobals.address,
    MapleGlobals.abi,
    signer
  );

  await mapleGlobals.setMapleTreasury(MapleTreasury.address);

  // Update the MapleGlobals pool delegate whitelist.
  const accounts = await ethers.provider.listAccounts();

  await mapleGlobals.setPoolDelegateWhitelist(accounts[0], true);
  await mapleGlobals.setPoolDelegateWhitelist(accounts[1], true);

  const PAIR_ONE = "ETH / USD";
  const PAIR_TWO = "BTC / USD";
  const PAIR_THREE = "DAI / USD";

  const ETH_USD_ORACLE_ADDRESS = chainLinkFactory.getOracle(PAIR_ONE);
  const BTC_USD_ORACLE_ADDRESS = chainLinkFactory.getOracle(PAIR_TWO);
  const DAI_USD_ORACLE_ADDRESS = chainLinkFactory.getOracle(PAIR_THREE);

  await mapleGlobals.setLoanAsset(DAI.address, true);
  await mapleGlobals.setLoanAsset(USDC.address, true);

  await mapleGlobals.setCollateralAsset(DAI.address, true);
  await mapleGlobals.setCollateralAsset(USDC.address, true);
  await mapleGlobals.setCollateralAsset(WETH.address, true);
  await mapleGlobals.setCollateralAsset(WBTC.address, true);

  await mapleGlobals.assignPriceFeed(USDC.address, DAI_USD_ORACLE_ADDRESS);
  await mapleGlobals.assignPriceFeed(DAI.address, DAI_USD_ORACLE_ADDRESS);
  await mapleGlobals.assignPriceFeed(WBTC.address, BTC_USD_ORACLE_ADDRESS);
  await mapleGlobals.assignPriceFeed(WETH.address, ETH_USD_ORACLE_ADDRESS);

  await mapleGlobals.setMapleTreasury(MapleTreasury.address);

  await mapleGlobals.setCalc(BulletRepaymentCalc.address, true);
  await mapleGlobals.setCalc(LateFeeCalc.address, true);
  await mapleGlobals.setCalc(PremiumCalc.address, true);

  await mapleGlobals.setValidPoolFactory(PoolFactory.address, true);
  await mapleGlobals.setValidLoanFactory(LoanFactory.address, true);

  await mapleGlobals.setValidSubFactory(
    PoolFactory.address,
    StakeLockerFactory.address,
    true
  );
  await mapleGlobals.setValidSubFactory(
    PoolFactory.address,
    LiquidityLockerFactory.address,
    true
  );
  await mapleGlobals.setValidSubFactory(
    LoanFactory.address,
    CollateralLockerFactory.address,
    true
  );
  await mapleGlobals.setValidSubFactory(
    LoanFactory.address,
    FundingLockerFactory.address,
    true
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
