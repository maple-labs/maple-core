const { expect, assert } = require('chai')

const mapleTokenAddress = require('../../contracts/src/contracts/MapleToken.address.js')
const mapleTokenABI = require('../../contracts/src/contracts/MapleToken.address.js')
const governor = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'

describe('Maple', function () {

  let mapleToken;

  before(async () => {
    mapleToken = new ethers.Contract(
      mapleTokenAddress, 
      mapleTokenABI, 
      ethers.provider.getSigner(0)
    )
  })

  it('msg.sender (Governor) has tokens, correct init values for MapleToken', async function () {
    
    // Test whether or not the MapleGovernor (admin) has been minted correct amount of tokens.
    // Initial supply is 10mm
    // Precision is 18
    // Symbol is MPL
    // Name is MapleToken

  })

  it('transfer() / transferFrom() works', async function () {
    
    // Test the basic ERC-20 transfer and transferFrom functions

  })

  it('SafeMathInt.sol / SafeMathUint.sol libraries work', async function () {
    
    // Check the function in each safeMath library for it's particular type, to ensure type conversion works

  })

  it('getBalance() / getApproval() ', async function () {
    
    // Check the basic ERC-20 view functions are exposed

  })

  it('FDT: fundsToken instatiation ', async function () {
    
    // Check the mapleToken has the correct fundsToken address (USDC, or DAI)

  })

  it('FDT: mint fundsToken, updateFunds() ', async function () {
    
    // Mint the fundsToken inside the mapleToken contract, and call updateFunds()
    // Confirm that withdrawableFundsOf() / accumulativeFundsOf() view functions show correct data

  })

  it('FDT: withdrawFunds() ', async function () {
    
    // Withdraw the fundsToken and confirm balanceOf() is correct for appropriate parties
    // Confirm correct internal account with withdrawnFundsOf() view function

  })

})
