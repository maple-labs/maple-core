const { expect } = require('chai')
const daiaddy = require('../../contracts/src/contracts/MintableTokenDAI.address.js')
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
//const bpooladdy = require('../../contracts/src/contracts/BPool.address.js')

describe('Liquidity Pool and locker', function () {
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
    const usdclplocker = await lplockerfactory.getLocker(1)
    await lpfactory.createLiquidityPool(
      usdcaddy,
      usdcbpooladdy,
      lplockerfactoryaddy,
      'Maple USDC LP',
      'LPUSDC',
      mplglobalsaddy
    )
    dailp = await lpfactory.getLiquidityPool(0)
    usdclp = await lpfactory.getLiquidityPool(1)
    console.log('DAI Liquidity Pool', dailp)
    console.log('USDC Liquidity Pool', usdclp)
    //await lplockerfactory.newLocker(daibpooladdy)
    //await lplockerfactory.newLocker(usdcbpooladdy)
  })
  it('Check locker owners', async function () {
    const dailplocker = await lplockerfactory.getLocker(0)
    const usdclplocker = await lplockerfactory.getLocker(1)
    console.log('DAI locker', dailplocker)
    console.log('USDC Locker', usdclplocker)
    const dailockerowner = await lplockerfactory.getOwner(dailplocker)
    const usdclockerowner = await lplockerfactory.getOwner(usdclplocker)
    expect(dailockerowner).to.equal(dailp)
    expect(usdclockerowner).to.equal(usdclp)
  })
  /*it('LP Locker factory getter', async function () {
    await lplockerfactory.newLocker(daibpooladdy)
    await lplockerfactory.newLocker(usdcbpooladdy)
    const dailplocker = await lplockerfactory.getLocker(0)
    const usdclplocker = await lplockerfactory.getLocker(1)
    console.log('DAI locker', dailplocker)
    console.log('USDC Locker', usdclplocker)
  })*/
})
