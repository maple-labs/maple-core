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
  })
  it('Check locker owners', async function () {
    const dailplocker = await lplockerfactory.getLocker(0)
    const usdclplocker = await lplockerfactory.getLocker(1)
    const dailockerowner = await lplockerfactory.getPool(dailplocker)
    const usdclockerowner = await lplockerfactory.getPool(usdclplocker)
    expect(dailockerowner).to.equal(dailpaddy)
    expect(usdclockerowner).to.equal(usdclpaddy)
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
    await daibpool.approve(dailplocker, '100000000000000000000')
    await dailocker.stake('100000000000000000000')
  })
  it('Can deposit stake USDC', async function () {})
  it('Can not finalize pool without stake', async function () {})
  it('Can finalize DAI pool with stake', async function () {
    dailp = new ethers.Contract(dailpaddy, lpabi, ethers.provider.getSigner(0))
    await dailp.finalize()
    isfin = await dailp.isFinalized()
    expect(isfin.toString()).to.equal('true')
  })
  it('', async function () {})
})
