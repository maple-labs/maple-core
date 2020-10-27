const { expect } = require('chai')

const bcaddy = require('../../contracts/src/contracts/BCreator.address.js')
const bcabi = require('../../contracts/src/contracts/BCreator.abi.js')
const mpladdy = require('../../contracts/src/contracts/MapleToken.address.js')
const mplabi = require('../../contracts/src/contracts/MapleToken.abi.js')
//const bpooladdy = require('../../contracts/src/contracts/BPool.address.js')

describe('Maple', function () {
  let bpooladdy
  let bpooladdy2
  before(async () => {
    //const Bc =  await ethers.getContractFactory('BCreator')

    const bc = new ethers.Contract(bcaddy, bcabi, ethers.provider.getSigner(0))
    //const bc = Bc.attach(bcaddy)

    bpooladdy = await bc.getBPoolAddress(0)
    bpooladdy2 = await bc.getBPoolAddress(1)
    console.log('BPOOLADDY DAI', bpooladdy, ' bpooladdy2 USDC', bpooladdy2)
    mpl = new ethers.Contract(mpladdy, mplabi, ethers.provider.getSigner(0))
  })

  it('Check balance maple token', async function () {
    const accounts = await ethers.provider.listAccounts()
    const bal = await mpl.balanceOf(accounts[0])
    console.log('mpl bal', bal.toString())
  })
  it('set allowances to dai balancer pool', async function () {
    const accounts = await ethers.provider.listAccounts()
    const allowmpl = await mpl.allowance(accounts[0], bpooladdy)
    console.log('allowance mpl', allowmpl.toString())
    await mpl.approve(bpooladdy, '50000000000000000000000')
    const allowmpl2 = await mpl.allowance(accounts[0], bpooladdy)
    console.log('allowance2 mpl', allowmpl2.toString())
  })
  it('set allowances to usdc balancer pool', async function () {
    const accounts = await ethers.provider.listAccounts()
    const allowmpl = await mpl.allowance(accounts[0], bpooladdy2)
    console.log('allowance mpl', allowmpl.toString())
    await mpl.approve(bpooladdy2, '50000000000000000000000')
    const allowmpl2 = await mpl.allowance(accounts[0], bpooladdy2)
    console.log('allowance2 mpl', allowmpl2.toString())
  })
  it('give some coins to friends', async function () {
    const accounts = await ethers.provider.listAccounts()
    expect(await mpl.transfer(accounts[1], '20000000000000000000000'))
    const bal = await mpl.balanceOf(accounts[1])
    console.log('MPL bal account 1', bal.toString())
    const mpla2 = await mpl.connect(ethers.provider.getSigner(1))
    await mpla2.approve(bpooladdy, '20000000000000000000000')
    const allowmpl2 = await mpla2.allowance(accounts[1], bpooladdy)
    console.log('allowance bpool mpl acct 1', allowmpl2.toString())
  })
})
