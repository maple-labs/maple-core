const { expect, assert, should } = require('chai')

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

  it('update state variables via setters', async function () {
      
    await mapleGlobals.setEstablishmentFee(50)
    const establishmentFeeFetch = await mapleGlobals.establishmentFeeBasisPoints()
    expect(establishmentFeeFetch).to.equal(50)

    await mapleGlobals.setTreasurySplit(30)
    const treasuryFeeFetch = await mapleGlobals.treasuryFeeBasisPoints()
    expect(treasuryFeeFetch).to.equal(30)
    
    await mapleGlobals.setGracePeriod(86400)
    const gracePeriodFetch = await mapleGlobals.gracePeriod()
    expect(gracePeriodFetch).to.equal(86400)

    await mapleGlobals.setStakeRequired(35000)
    const stakeRequiredFetch = await mapleGlobals.stakeAmountRequired()
    expect(stakeRequiredFetch).to.equal(35000)

    await mapleGlobals.setGovernor('0x70997970C51812dc3A010C7d01b50e0d17dc79C8')
    const governorFetch = await mapleGlobals.governor()
    expect(governorFetch).to.equal('0x70997970C51812dc3A010C7d01b50e0d17dc79C8')

  })

  it('check msg.sender throws revert error', async function () {
      
    await expect(
        mapleGlobals.setEstablishmentFee(50)
    ).to.be.revertedWith("msg.sender is not Governor");

    await expect(
        mapleGlobals.setTreasurySplit(30)
    ).to.be.revertedWith("msg.sender is not Governor");
    
    await expect(
        mapleGlobals.setGracePeriod(86400)
    ).to.be.revertedWith("msg.sender is not Governor");
    
    await expect(
        mapleGlobals.setStakeRequired(30000)
    ).to.be.revertedWith("msg.sender is not Governor");
    
    await expect(
        mapleGlobals.setGovernor('0x70997970C51812dc3A010C7d01b50e0d17dc79C8')
    ).to.be.revertedWith("msg.sender is not Governor");
    
  })


})
