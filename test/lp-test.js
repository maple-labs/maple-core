const { expect } = require('chai')
const DAIAddress = require('../../contracts/src/contracts/MintableTokenDAI.address.js')
const BPoolABI = require('../../contracts/src/contracts/BPool.abi.js')
const stakeLockerABI = require('../../contracts/src/contracts/LPStakeLocker.abi.js')
const LPABI = require('../../contracts/src/contracts/LP.abi.js')
const USDCAddress = require('../../contracts/src/contracts/MintableTokenUSDC.address.js')
const bcAddress = require('../../contracts/src/contracts/BCreator.address.js')
const bcABI = require('../../contracts/src/contracts/BCreator.abi.js')
const mplAddress = require('../../contracts/src/contracts/MapleToken.address.js')
const mplABI = require('../../contracts/src/contracts/MapleToken.abi.js')
const MPLGlobalsAddress = require('../../contracts/src/contracts/MapleGlobals.address.js')
const LPLockerFactoryABI = require('../../contracts/src/contracts/LPStakeLockerFactory.abi.js')
const LPFactoryABI = require('../../contracts/src/contracts/LPFactory.abi.js')
const LPLockerFactoryAddress = require('../../contracts/src/contracts/LPStakeLockerFactory.address.js')
const LPFactoryAddress = require('../../contracts/src/contracts/LPFactory.address.js')
const liquidLockerABI = require('../../contracts/src/contracts/liquidAssetLocker.abi.js')
const liquidLockerFactoryABI = require('../../contracts/src/contracts/liquidAssetLockerFactory.abi.js')
const liquidLockerFactoryAddress = require('../../contracts/src/contracts/liquidAssetLockerFactory.address.js')

describe('Liquidity Pool and respective lockers', function () {
  let DAILP
  let USDCLP
  before(async () => {
    LPFactory = new ethers.Contract(
      LPFactoryAddress,
      LPFactoryABI,
      ethers.provider.getSigner(0)
    )
    LPLockerFactory = new ethers.Contract(
      LPLockerFactoryAddress,
      LPLockerFactoryABI,
      ethers.provider.getSigner(0)
    )
    const bc = new ethers.Contract(
      bcAddress,
      bcABI,
      ethers.provider.getSigner(0)
    )

    DAIBPoolAddress = await bc.getBPoolAddress(0)
    USDCBPoolAddress = await bc.getBPoolAddress(1)
    await LPFactory.createLiquidityPool(
      DAIAddress,
      DAIBPoolAddress,
      LPLockerFactoryAddress,
      liquidLockerFactoryAddress,
      'Maple DAI LP',
      'LPDAI',
      MPLGlobalsAddress
    )
    await LPFactory.createLiquidityPool(
      USDCAddress,
      USDCBPoolAddress,
      LPLockerFactoryAddress,
      liquidLockerFactoryAddress,
      'Maple USDC LP',
      'LPUSDC',
      MPLGlobalsAddress
    )
    DAILPAddress = await LPFactory.getLiquidityPool(0)
    USDCLPAddress = await LPFactory.getLiquidityPool(1)
    DAILP = new ethers.Contract(
      DAILPAddress,
      LPABI,
      ethers.provider.getSigner(0)
    )
    USDCLP = new ethers.Contract(
      USDCLPAddress,
      LPABI,
      ethers.provider.getSigner(0)
    )
    laLockerFactory = new ethers.Contract(
      liquidLockerFactoryAddress,
      liquidLockerFactoryABI,
      ethers.provider.getSigner(0)
    )
    DAIStakeLockerAddress = await DAILP.stakedAssetLocker()
    USDCStakeLockerAddress = await USDCLP.stakedAssetLocker()
  })
  it('Sets the correct owners for Token Lockers', async function () {
    const DAILockerowner = await LPLockerFactory.getPool(DAIStakeLockerAddress)
    const USDCLockerowner = await LPLockerFactory.getPool(
      USDCStakeLockerAddress
    )
    expect(DAILockerowner).to.equal(DAILPAddress)
    expect(USDCLockerowner).to.equal(USDCLPAddress)
  })
  it('is not finalized', async function () {
    isfinDAI = await DAILP.isFinalized()
    isfinUSDC = await USDCLP.isFinalized()
    expect(isfinDAI).to.equal(false)
    expect(isfinUSDC).to.equal(false)
  })
  it('Can not finalize DAI pool without stake', async function () {
    await expect(DAILP.finalize()).to.be.revertedWith(
      'FDT_LP.makeStakeLocker: NOT_ENOUGH_STAKE'
    )
    isfin = await DAILP.isFinalized()
    expect(isfin.toString()).to.equal('false')
  })
  it('Can deposit stake DAI', async function () {
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(0)
    )
    const DAILocker = new ethers.Contract(
      DAIStakeLockerAddress,
      stakeLockerABI,
      ethers.provider.getSigner(0)
    )
    await DAIBPool.approve(DAIStakeLockerAddress, '100000000000000000000')
    await DAILocker.stake('100000000000000000000')
  })
  it('Can finalize DAI pool with stake', async function () {
    await DAILP.finalize()
    isfin = await DAILP.isFinalized()
    expect(isfin.toString()).to.equal('true')
  })
  it('Can not finalize USDC pool without stake', async function () {
    await expect(USDCLP.finalize()).to.be.revertedWith(
      'FDT_LP.makeStakeLocker: NOT_ENOUGH_STAKE'
    )
    isfin = await USDCLP.isFinalized()
    expect(isfin.toString()).to.equal('false')
  })
  it('Can deposit stake USDC', async function () {
    const USDCBPool = new ethers.Contract(
      USDCBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(0)
    )
    const USDCLocker = new ethers.Contract(
      USDCStakeLockerAddress,
      stakeLockerABI,
      ethers.provider.getSigner(0)
    )
    await USDCBPool.approve(USDCStakeLockerAddress, '100000000000000000000')
    await USDCLocker.stake('100000000000000000000')
  })
  it('Can finalize USDC pool with stake', async function () {
    await USDCLP.finalize()
    isfin = await USDCLP.isFinalized()
    expect(isfin.toString()).to.equal('true')
  })

  //keep these two at bottom or do multiple times
  it('DAI BPT bal of stakedAssetLocker is same as stakedAssetLocker total token supply', async function () {
    DAIStakeLockerAddress = DAILP.stakedAssetLocker()
    const DAILocker = new ethers.Contract(
      DAIStakeLockerAddress,
      stakeLockerABI,
      ethers.provider.getSigner(0)
    )
    const DAIBPool = new ethers.Contract(
      DAIBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(0)
    )
    const totalsup = await DAILocker.totalSupply()
    const BPTbal = await DAIBPool.balanceOf(DAIStakeLockerAddress)
    expect(BPTbal).to.equal(totalsup)
  })

  it('USDC BPT bal of stakedAssetLocker is same as stakedAssetLocker total token supply', async function () {
    USDCStakeLockerAddress = USDCLP.stakedAssetLocker()
    const USDCLocker = new ethers.Contract(
      USDCStakeLockerAddress,
      stakeLockerABI,
      ethers.provider.getSigner(0)
    )
    const USDCBPool = new ethers.Contract(
      USDCBPoolAddress,
      BPoolABI,
      ethers.provider.getSigner(0)
    )
    const totalsup = await USDCLocker.totalSupply()
    const BPTbal = await USDCBPool.balanceOf(USDCStakeLockerAddress)
    expect(BPTbal).to.equal(totalsup)
  })
  it('DAI liquidAssetLocker created, indexed by factory and known to LP?', async function () {
    const DAILocker = await laLockerFactory.getLocker(0)
    const DAILockerLP = await DAILP.liquidAssetLocker()
    expect(DAILocker).to.equal(DAILockerLP)
  })
  it('USDC liquidAssetLocker created, indexed by factory and known to LP?', async function () {
    const USDCLocker = await laLockerFactory.getLocker(1)
    const USDCLockerLP = await USDCLP.liquidAssetLocker()
    expect(USDCLocker).to.equal(USDCLockerLP)
  })
  it('Mapping DAI locker to parent pool', async function () {
    const DAILocker = await DAILP.liquidAssetLocker()
    const DAIPool = await laLockerFactory.getPool(DAILocker)
    expect(DAIPool).to.equal(DAILPAddress)
  })
  it('Mapping USDC locker to parent pool', async function () {
    const USDCLocker = await USDCLP.liquidAssetLocker()
    const USDCPool = await laLockerFactory.getPool(USDCLocker)
    expect(USDCPool).to.equal(USDCLPAddress)
  })
  it('Check DAI LP is recognized by LPFactory.isLPool()', async function () {
    const isPool = await LPFactory.isLPool(DAILPAddress)
    expect(isPool).to.equal(true)
  })
  it('Check USDC LP is recognized by LPFactory.isLPool()', async function () {
    const isPool = await LPFactory.isLPool(USDCLPAddress)
    expect(isPool).to.equal(true)
  })
})
