const { expect, assert } = require('chai')
const { BigNumber } = require('ethers')

const DAIAddress = require('../../contracts/src/contracts/MintableTokenDAI.address.js')
const DAIABI = require('../../contracts/src/contracts/MintableTokenDAI.abi.js')
const USDCAddress = require('../../contracts/src/contracts/MintableTokenUSDC.address.js')
const USDCABI = require('../../contracts/src/contracts/MintableTokenUSDC.abi.js')
const MPLAddress = require('../../contracts/src/contracts/MapleToken.address.js')
const MPLABI = require('../../contracts/src/contracts/MapleToken.abi.js')
const WETHAddress = require('../../contracts/src/contracts/WETH9.address.js')
const WETHABI = require('../../contracts/src/contracts/WETH9.abi.js')
const WBTCAddress = require('../../contracts/src/contracts/WBTC.address.js')
const WBTCABI = require('../../contracts/src/contracts/WBTC.abi.js')
const LVFactoryAddress = require('../../contracts/src/contracts/LoanVaultFactory.address.js')
const LVFactoryABI = require('../../contracts/src/contracts/LoanVaultFactory.abi.js')
const FLFAddress = require('../../contracts/src/contracts/LoanVaultFundingLockerFactory.address.js')
const FLFABI = require('../../contracts/src/contracts/LoanVaultFundingLockerFactory.abi.js')
const CLFAddress = require('../../contracts/src/contracts/LoanVaultCollateralLockerFactory.address.js')
const CLFABI = require('../../contracts/src/contracts/LoanVaultCollateralLockerFactory.abi.js')
const GlobalsAddress = require('../../contracts/src/contracts/MapleGlobals.address.js')
const GlobalsABI = require('../../contracts/src/contracts/MapleGlobals.abi.js')


describe('MapleTreasury.sol', function () {

  let DAI, USDC, MPL, WETH, WBTC, LoanVaultFactory, FundingLockerFactory, CollateralLockerFactory, Globals;

  before(async () => {
    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0))
    USDC = new ethers.Contract(USDCAddress, USDCABI, ethers.provider.getSigner(0))
    MPL = new ethers.Contract(MPLAddress, MPLABI, ethers.provider.getSigner(0))
    WETH = new ethers.Contract(WETHAddress, WETHABI, ethers.provider.getSigner(0))
    WBTC = new ethers.Contract(WBTCAddress, WBTCABI, ethers.provider.getSigner(0))
    LoanVaultFactory = new ethers.Contract(LVFactoryAddress, LVFactoryABI, ethers.provider.getSigner(0))
    FundingLockerFactory = new ethers.Contract(FLFAddress, FLFABI, ethers.provider.getSigner(0))
    CollateralLockerFactory = new ethers.Contract(CLFAddress, CLFABI, ethers.provider.getSigner(0))
    Globals = new ethers.Contract(GlobalsAddress, GlobalsABI, ethers.provider.getSigner(0))
  })

  it('deploy LoanVault --> createLoanVault()', async function () {
    
     const num = await LoanVaultFactory.createLoanVault(
        DAIAddress,WETHAddress,FLFAddress,CLFAddress,'QFL','QFL',GlobalsAddress
     );

  })
  
  it('prepare LoanVault --> prepareLoan()', async function () {
    
  })

  it('fund LoanVault --> fundLoan()', async function () {
    
  })

  it('claim funding --> endFunding()', async function () {
    
  })

})
