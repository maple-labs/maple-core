const { expect } = require('chai')
const { BigNumber } = require("ethers");
const artpath = '../../contracts/' + network.name + '/';

const BCreatorABI = require(artpath + 'abis/BCreator.abi.js')
const BCreatorAddress = require(artpath + 'addresses/BCreator.address.js')

const USDCAddress = require(artpath + 'addresses/MintableTokenUSDC.address.js')

const MapleGlobalsAddress = require(artpath + 'addresses/MapleGlobals.address.js')
const MapleGlobalsABI = require(artpath + 'abis/MapleGlobals.abi.js')

async function main() {
  
  // Fetch the official Maple balancer pool address.
  BCreator = new ethers.Contract(BCreatorAddress, BCreatorABI, ethers.provider.getSigner(0))
  MapleBPoolAddress = await BCreator.getBPoolAddress(0)

  Globals = new ethers.Contract(
    MapleGlobalsAddress, 
    MapleGlobalsABI, 
    ethers.provider.getSigner(0)
  )

  await Globals.setMapleBPool(MapleBPoolAddress);
  await Globals.setMapleBPoolAssetPair(USDCAddress);

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
