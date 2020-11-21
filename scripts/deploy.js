const { deploy } = require("@maplelabs/hardhat-scripts");

const mintableUSDC = require("../../contracts/localhost/addresses/MintableTokenUSDC.address");
const uniswapRouter = require("../../contracts/localhost/addresses/UniswapV2Router02.address");

const governor = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";

async function main() {
  const mapleToken = await deploy("MapleToken", [
    "MapleToken",
    "MPL",
    mintableUSDC,
  ]);

  const mapleGlobals = await deploy("MapleGlobals", [
    governor,
    mapleToken.address,
  ]);

  await deploy("LPStakeLockerFactory");
  await deploy("LiquidAssetLockerFactory");
  await deploy("LPFactory");

  const mapleTreasury = await deploy("MapleTreasury", [
    mapleToken.address,
    mintableUSDC,
    uniswapRouter,
    mapleGlobals.address,
  ]);

  await mapleGlobals.setMapleTreasury(mapleTreasury.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
