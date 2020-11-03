const { expect } = require('chai')
const daiaddy = require('../../contracts/src/contracts/MintableTokenDAI.address.js')
const bpoolabi = require('../../contracts/src/contracts/BPool.abi.js')
const stakelockerabi = require('../../contracts/src/contracts/LPStakeLocker.abi.js')
const lpabi = require('../../contracts/src/contracts/LP.abi.js')
const usdcaddy = require('../../contracts/src/contracts/MintableTokenUSDC.address.js')
const bcaddy = require('../../contracts/src/contracts/BCreator.address.js')
const bcabi = require('../../contracts/src/contracts/BCreator.abi.js')
const mpladdy = require('../../contracts/src/contracts/MapleToken.address.js')
const mplabi = require('../../contracts/src/contracts/MapleToken.abi.js')
const mplglobalsaddy = require('../../contracts/src/contracts/MapleGlobals.address.js')
const lplockerfactoryabi = require('../../contracts/src/contracts/LPStakeLockerFactory.abi.js')
const lpfactoryabi = require('../../contracts/src/contracts/LPFactory.abi.js')
const lplockerfactoryaddy = require('../../contracts/src/contracts/LPStakeLockerFactory.address.js')
const lpfactoryaddy = require('../../contracts/src/contracts/LPFactory.address.js')

describe('Liquidity Pool and respective lockers', function () {
  let dailp
  let usdclp
  before(async () => {
    lpfactory = new ethers.Contract(
      lpfactoryaddy,
      lpfactoryabi,
      ethers.provider.getSigner(0)
    )
    lplockerfactory = new ethers.Contract(
      lplockerfactoryaddy,
      lplockerfactoryabi,
      ethers.provider.getSigner(0)
    )
    const bc = new ethers.Contract(bcaddy, bcabi, ethers.provider.getSigner(0))

    daibpooladdy = await bc.getBPoolAddress(0)
    usdcbpooladdy = await bc.getBPoolAddress(1)
    await lpfactory.createLiquidityPool(
      daiaddy,
      daibpooladdy,
      lplockerfactoryaddy,
      'Maple DAI LP',
      'LPDAI',
      mplglobalsaddy
    )
    await lpfactory.createLiquidityPool(
      usdcaddy,
      usdcbpooladdy,
      lplockerfactoryaddy,
      'Maple USDC LP',
      'LPUSDC',
      mplglobalsaddy
    )
    dailpaddy = await lpfactory.getLiquidityPool(0)
    usdclpaddy = await lpfactory.getLiquidityPool(1)
    dailp = new ethers.Contract(dailpaddy, lpabi, ethers.provider.getSigner(0))
    usdclp = new ethers.Contract(
      usdclpaddy,
      lpabi,
      ethers.provider.getSigner(0)
    )
  })
  it('Check locker owners', async function () {
    const dailplocker = await lplockerfactory.getLocker(0)
    const usdclplocker = await lplockerfactory.getLocker(1)
    const dailockerowner = await lplockerfactory.getPool(dailplocker)
    const usdclockerowner = await lplockerfactory.getPool(usdclplocker)
    expect(dailockerowner).to.equal(dailpaddy)
    expect(usdclockerowner).to.equal(usdclpaddy)
  })
  it('is not finalized', async function () {
    isfindai = await dailp.isFinalized()
    isfinusdc = await usdclp.isFinalized()
    expect(isfindai).to.equal(false)
    expect(isfinusdc).to.equal(false)
  })
  it('Can not finalize DAI pool without stake', async function () {
    await expect(dailp.finalize()).to.be.revertedWith(
      'FDT_LP.makeStakeLocker: NOT_ENOUGH_STAKE'
    )
    isfin = await dailp.isFinalized()
    expect(isfin.toString()).to.equal('false')
  })
  it('Can deposit stake DAI', async function () {
    const daibpool = new ethers.Contract(
      daibpooladdy,
      bpoolabi,
      ethers.provider.getSigner(0)
    )
    const dailockeraddy = await lplockerfactory.getLocker(0)
    const dailocker = new ethers.Contract(
      dailockeraddy,
      stakelockerabi,
      ethers.provider.getSigner(0)
    )
    await daibpool.approve(dailockeraddy, '100000000000000000000')
    await dailocker.stake('100000000000000000000')
  })
  it('Can finalize DAI pool with stake', async function () {
    await dailp.finalize()
    isfin = await dailp.isFinalized()
    expect(isfin.toString()).to.equal('true')
  })
  it('Can not finalize USDC pool without stake', async function () {
    await expect(usdclp.finalize()).to.be.revertedWith(
      'FDT_LP.makeStakeLocker: NOT_ENOUGH_STAKE'
    )
    isfin = await usdclp.isFinalized()
    expect(isfin.toString()).to.equal('false')
  })
  it('Can deposit stake USDC', async function () {
    const usdcbpool = new ethers.Contract(
      usdcbpooladdy,
      bpoolabi,
      ethers.provider.getSigner(0)
    )
    const usdclockeraddy = await lplockerfactory.getLocker(1)
    const usdclocker = new ethers.Contract(
      usdclockeraddy,
      stakelockerabi,
      ethers.provider.getSigner(0)
    )
    await usdcbpool.approve(usdclockeraddy, '100000000000000000000')
    await usdclocker.stake('100000000000000000000')
  })
  it('Can finalize USDC pool with stake', async function () {
    await usdclp.finalize()
    isfin = await usdclp.isFinalized()
    expect(isfin.toString()).to.equal('true')
  })

  //keep these two at bottom or do multiple times
  it('DAI BPT bal of stakedAssetLocker is same as stakedassetlocker total token supply', async function () {
    dailockeraddy = dailp.stakedAssetLocker()
    const dailocker = new ethers.Contract(
      dailockeraddy,
      stakelockerabi,
      ethers.provider.getSigner(0)
    )
    const daibpool = new ethers.Contract(
      daibpooladdy,
      bpoolabi,
      ethers.provider.getSigner(0)
    )
    const totalsup = await dailocker.totalSupply()
    const BPTbal = await daibpool.balanceOf(dailockeraddy)
    expect(BPTbal).to.equal(totalsup)
  })

  it('USDC BPT bal of stakedAssetLocker is same as stakedassetlocker total token supply', async function () {
    usdclockeraddy = usdclp.stakedAssetLocker()
    const usdclocker = new ethers.Contract(
      usdclockeraddy,
      stakelockerabi,
      ethers.provider.getSigner(0)
    )
    const usdcbpool = new ethers.Contract(
      usdcbpooladdy,
      bpoolabi,
      ethers.provider.getSigner(0)
    )
    const totalsup = await usdclocker.totalSupply()
    const BPTbal = await usdcbpool.balanceOf(usdclockeraddy)
    expect(BPTbal).to.equal(totalsup)
  })
})
