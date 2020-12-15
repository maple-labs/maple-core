
const { deploy } = require("@maplelabs/hardhat-scripts");
const artpath = '../../contracts/' + network.name + '/';
const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");


async function main() {

  const mapleToken = await deploy("MapleToken", [
    "MapleToken",
    "MPL",
    USDCAddress,
  ]);

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
