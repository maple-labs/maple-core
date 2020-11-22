const { deploy } = require("@maplelabs/hardhat-scripts");

const mintableUSDC = require("../../contracts/localhost/addresses/MintableTokenUSDC.address.js");
const uniswapRouter = require("../../contracts/localhost/addresses/UniswapV2Router02.address.js");

async function main() {

  const mapleToken = await deploy('MapleToken', [
    'MapleToken',
    'MPL',
    mintableUSDC
  ])
  console.log(mapleToken.address)

  // Governor = accounts[0]
  const accounts = await ethers.provider.listAccounts()

  const mapleGlobals = await deploy('MapleGlobals', [
    accounts[0],
    mapleToken.address
  ])
  console.log(mapleGlobals.address)

  const LPStakeLockerFactory = await deploy('LPStakeLockerFactory')
  console.log(LPStakeLockerFactory.address)

  const liquidAssetLockerFactory = await deploy('LiquidAssetLockerFactory')
  console.log(liquidAssetLockerFactory.address)

  const LPFactory = await deploy('LPFactory')
  console.log(LPFactory.address)

  const mapleTreasury = await deploy('MapleTreasury', [
    mapleToken.address,
    mintableUSDC,
    uniswapRouter,
    mapleGlobals.address
  ])
  console.log(mapleTreasury.address)
  const updateGlobals = await mapleGlobals.setMapleTreasury(mapleTreasury.address)
  
  const LVFactory = await deploy('LoanVaultFactory')
  console.log(LVFactory.address)

  const CollateralLockerFactory = await deploy('LoanVaultCollateralLockerFactory', [
    LVFactory.address
  ])
  console.log(CollateralLockerFactory.address)

  const FundingLockerFactory = await deploy('LoanVaultFundingLockerFactory', [
    LVFactory.address
  ])
  console.log(FundingLockerFactory.address)

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
