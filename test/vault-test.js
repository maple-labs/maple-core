const { expect, assert } = require('chai')
const { BigNumber } = require('ethers')

const DAIAddress = require('../../contracts/src/contracts/MintableTokenDAI.address.js')
const DAIABI = require('../../contracts/src/contracts/MintableTokenDAI.abi.js')
const USDCAddress = require('../../contracts/src/contracts/MintableTokenUSDC.address.js')
const USDCABI = require('../../contracts/src/contracts/MintableTokenUSDC.abi.js')
const MPLAddress = require('../../contracts/src/contracts/MapleToken.address.js')
const MPLABI = require('../../contracts/src/contracts/MapleToken.abi.js')
const LVFactoryAddress = require('../../contracts/src/contracts/LoanVaultFactory.address.js')
const LVFactoryABI = require('../../contracts/src/contracts/LoanVaultFactory.abi.js')


describe('MapleTreasury.sol', function () {

  let DAI, USDC, MPL;

  before(async () => {
    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0))
    USDC = new ethers.Contract(USDCAddress, USDCABI, ethers.provider.getSigner(0))
    MPL = new ethers.Contract(MPLAddress, MPLABI, ethers.provider.getSigner(0))
    LVFactory = new ethers.Contract(LVFactoryAddress, LVABI, ethers.provider.getSigner(0))
  })

  it('deploy loanVault via loanVaultFactory()', async function () {
    
  })
  
  it('prepare loanVault via prepareLoan()', async function () {
    
  })

  it('fund loanVault via fundLoan()', async function () {
    
  })

})
