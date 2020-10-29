const { expect, assert } = require('chai')

const globalAddress = require('../../contracts/src/contracts/MapleGlobals.address.js')
const gloablABI = require('../../contracts/src/contracts/MapleGlobals.abi.js')
const mapleTokenAddress = require('../../contracts/src/contracts/MapleToken.address.js')
const governor = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'

describe('Maple', function () {

  let mapleGlobals;

  before(async () => {
    mapleGlobals = new ethers.Contract(
      globalAddress, 
      gloablABI, 
      ethers.provider.getSigner(0)
    )
  })

  it('state variables have correct init values', async function () {
    const accounts = await ethers.provider.listAccounts()
    const governorFetch = await mapleGlobals.governor()
    const mapleTokenFetch = await mapleGlobals.mapleToken()
    const establishmentFeeFetch = await mapleGlobals.establishmentFeeBasisPoints()
    const treasuryFeeFetch = await mapleGlobals.treasuryFeeBasisPoints()
    const gracePeriodFetch = await mapleGlobals.gracePeriod()
    expect(governorFetch).to.equal(governor)
    expect(mapleTokenFetch).to.equal(mapleTokenAddress)
    expect(establishmentFeeFetch).to.equal(200)
    expect(treasuryFeeFetch).to.equal(20)
    expect(gracePeriodFetch).to.equal(432000)
  })

})
