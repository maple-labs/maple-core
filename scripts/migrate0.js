
const { deploy } = require("@maplelabs/hardhat-scripts");
const artpath = '../../contracts/' + network.name + '/';


async function main() {

  const mapleToken = await deploy("MapleToken", [
    "MapleToken",
    "MPL",
    USDCAddress,
  ]);

  // Governor = accounts[0]
  const accounts = await ethers.provider.listAccounts();

  const mapleGlobals = await deploy("MapleGlobals", [
    accounts[0],
    mapleToken.address,
  ]);

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
