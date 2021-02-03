const { ethers } = require("hardhat");
const { deploy } = require("@maplelabs/hardhat-scripts");
const { CORE, DEPS, getArtifacts } = require("./artifacts");

async function main() {
  const accounts = await ethers.provider.listAccounts();

  // Get artifacts for Dependencies
  const USDC = getArtifacts(DEPS.USDC);
  const WETH = getArtifacts(DEPS.WETH);
  const WBTC = getArtifacts(DEPS.WBTC);
  const BFactory = getArtifacts(DEPS.BFactory);
  const UniswapV2Router02 = getArtifacts(DEPS.UniswapV2Router02);

  // Get artifacts for Maple Core
  const MapleToken = getArtifacts(CORE.MapleToken);

  const mapleGlobals = await deploy(CORE.MapleGlobals, [
    accounts[0],
    MapleToken.address,
    BFactory.address,
  ]);

  const calcBPool = await deploy(CORE.CalcBPool);

  await deploy(CORE.DebtLockerFactory);
  await deploy(CORE.StakeLockerFactory);
  await deploy(CORE.LiquidityLockerFactory);
  await deploy(CORE.PoolFactory, [mapleGlobals.address], { libraries: { CalcBPool: calcBPool.address} });

  await deploy(CORE.MapleTreasury, [
    MapleToken.address,
    USDC.address,
    UniswapV2Router02.address,
    mapleGlobals.address,
  ]);

  await deploy(CORE.LateFeeCalc, [0]); // 0% FEE if Late Payment
  await deploy(CORE.PremiumCalc, [200]); // 2% FEE on Principal
  await deploy(CORE.BulletRepaymentCalc);
  await deploy(CORE.FundingLockerFactory);
  await deploy(CORE.CollateralLockerFactory);
  await deploy(CORE.LoanFactory, [mapleGlobals.address]);
  
  console.log(CORE.LateFeeCalc);
  console.log(CORE.MapleDummyPriceFeed);

  // Price Feed deployments
  const priceFeedUSDC = await deploy(CORE.MapleDummyPriceFeedUSDC, [ 1 * 10**8, USDC.address])
  const priceFeedWETH = await deploy(CORE.MapleDummyPriceFeedWETH, [ 1630 * 10**8, WETH.address])
  const priceFeedWBTC = await deploy(CORE.MapleDummyPriceFeedWBTC, [ 37100 * 10**8, WBTC.address])


  await mapleGlobals.setPriceOracle(USDC.address, priceFeedUSDC.address);
  await mapleGlobals.setPriceOracle(WETH.address, priceFeedWETH.address);
  await mapleGlobals.setPriceOracle(WBTC.address, priceFeedWBTC.address);

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
