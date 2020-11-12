const { expect, assert } = require('chai')

const mintableDAIAddress = require('../../contracts/src/contracts/MintableTokenDAI.address.js')
const mintableDAIABI = require('../../contracts/src/contracts/MintableTokenDAI.abi.js')
const treasuryAddress = require('../../contracts/src/contracts/MapleTreasury.address.js')
const treasuryABI = require('../../contracts/src/contracts/MapleTreasury.abi.js')
const fundsTokenAddress = require('../../contracts/src/contracts/MintableTokenUSDC.address.js')
const fundsTokenABI = require('../../contracts/src/contracts/MintableTokenUSDC.abi.js')
const mapleTokenAddress = require('../../contracts/src/contracts/MapleToken.address.js')
const mapleTokenABI = require('../../contracts/src/contracts/MapleToken.abi.js')

describe('Maple Globals init', function () {

  let mintableDAI, fundsToken, mapleTreasury, mapleToken;

  before(async () => {
    mintableDAI = new ethers.Contract(
      mintableDAIAddress, 
      mintableDAIABI, 
      ethers.provider.getSigner(0)
    )
    fundsToken = new ethers.Contract(
      fundsTokenAddress, 
      fundsTokenABI, 
      ethers.provider.getSigner(0)
    )
    mapleTreasury = new ethers.Contract(
      treasuryAddress, 
      treasuryABI, 
      ethers.provider.getSigner(0)
    )
    mapleTreasury = new ethers.Contract(
      mapleTokenAddress, 
      mapleTokenABI, 
      ethers.provider.getSigner(0)
    )
  })

  it('mint DAI and fundsToken (USDC) within MapleTreasury', async function () {
    
    // mintSpecial() takes in whole number (i.e. 100) and mints (100 * 10**decimals)
    expect(await mintableDAI.mintSpecial(treasuryAddress, 100))
    expect(await fundsToken.mintSpecial(treasuryAddress, 100))

  })

  it('pass through USDC to MapleToken', async function () {
    
    // mintSpecial() takes in whole number (i.e. 100) and mints (100 * 10**decimals)
    expect(await mintableDAI.mintSpecial(treasuryAddress, 100))
    expect(await fundsToken.mintSpecial(treasuryAddress, 100))

  })

})
