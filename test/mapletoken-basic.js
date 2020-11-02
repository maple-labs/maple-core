const { expect, assert } = require('chai')

const mapleTokenAddress = require('../../contracts/src/contracts/MapleToken.address.js')
const mapleTokenABI = require('../../contracts/src/contracts/MapleToken.abi.js')
const fundTokenAddress = require('../../contracts/src/contracts/MintableTokenUSDC.address.js')
const fundTokenABI = require('../../contracts/src/contracts/MintableTokenUSDC.abi.js')
const governor = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'

describe('Maple', function () {

  let mapleToken, mapleTokenExternal;
  let fundToken, fundTokenExternal;

  before(async () => {
    mapleToken = new ethers.Contract(
      mapleTokenAddress, 
      mapleTokenABI, 
      ethers.provider.getSigner(0)
    )
    mapleTokenExternal = new ethers.Contract(
      mapleTokenAddress, 
      mapleTokenABI, 
      ethers.provider.getSigner(1)
    )
    fundToken = new ethers.Contract(
      fundTokenAddress,
      fundTokenABI,
      ethers.provider.getSigner(0)
    )
    fundTokenExternal = new ethers.Contract(
      fundTokenAddress,
      fundTokenABI,
      ethers.provider.getSigner(1)
    )
  })

  it('msg.sender (Governor) has first minted 10mm tokens, and supply is 10mm', async function () {
    
    const decimals = await mapleToken.decimals()
    const balanceOfGovernor = await mapleToken.balanceOf(governor)
    const supply = await mapleToken.totalSupply()

    expect(balanceOfGovernor / 10**decimals).to.equal(10000000)
    expect(supply._hex / 10**decimals).to.equal(10000000)

  })

  it('correct initialization of variables', async function () {
    
    const decimals = await mapleToken.decimals()
    const name = await mapleToken.name()
    const symbol = await mapleToken.symbol()

    expect(decimals).to.equal(18)
    expect(name).to.equal('MapleToken')
    expect(symbol).to.equal('MPL')

  })

  it('transfer() functionality', async function () {
    
    // Transfer 100 (10**decimals) tokens to another account from Governor, check balances.

    const accounts = await ethers.provider.listAccounts()
    const decimals = await mapleToken.decimals()
    const amountToTransfer = BigInt(100 * 10**decimals)

    expect(await mapleToken.transfer(accounts[1], amountToTransfer))

    const balanceOfGovernor = await mapleToken.balanceOf(governor)
    const balanceOfReceiver = await mapleToken.balanceOf(accounts[1])

    expect(balanceOfGovernor / 10**decimals).to.equal(10000000 - 100)
    expect(balanceOfReceiver / 10**decimals).to.equal(100)

  })

  it('transferFrom() functionality', async function () {
    
    // Approve 100 (10**18) tokens to another account from Governor.
    // Have another account call the transferFrom() function, check balances.

    const accounts = await ethers.provider.listAccounts()
    const decimals = await mapleToken.decimals()
    const amountToApproveTransfer = BigInt(100 * 10**decimals)

    expect(await mapleToken.approve(accounts[1], amountToApproveTransfer))

    const approvalAmount = await mapleToken.allowance(governor, accounts[1])

    expect(approvalAmount / 10**decimals).to.equal(100)

    // Reverts when calling via mapleToken, not when calling mapleTokenExternal (see: before hook lines 14-25)
    await expect(
      mapleToken.transferFrom(accounts[2], accounts[1], amountToApproveTransfer)
    ).to.be.revertedWith("transfer amount exceeds balance")

    expect(await mapleTokenExternal.transferFrom(governor, accounts[1], amountToApproveTransfer))
    
    const balanceOfGovernor = await mapleToken.balanceOf(governor)
    const balanceOfReceiver = await mapleToken.balanceOf(accounts[1])

    // Balance difference should be 200, given governor transferred 100 tokens in last test.
    expect(balanceOfGovernor / 10**decimals).to.equal(10000000 - 200)
    // Receiver should have 200, given receiver obtained 100 tokens in last test.
    expect(balanceOfReceiver / 10**decimals).to.equal(200)

  })

  it('FDT: fundsToken instatiation ', async function () {
    
    // Check the mapleToken has the correct fundsToken address (USDC, or DAI)
    const fetchFundTokenAddress = await mapleToken.fundsToken()
    expect(fetchFundTokenAddress).to.equal(fundTokenAddress)

  })

  it('FDT: mint fundsToken, updateFunds() ', async function () {
    
    // Mint the fundsToken inside the mapleToken contract, and call updateFunds()
    // Confirm that withdrawableFundsOf() / accumulativeFundsOf() view functions show correct data

    const fundTokenDecimals = await fundToken.decimals()
    const amountToMint = BigInt(100)

    // Please note that mintSpecial() takes in whole number (i.e. 100) and mints (100 * 10**decimals), thus handles conversion.
    expect(await fundToken.mintSpecial(mapleTokenAddress, amountToMint))

    const fundTokenBalance = await fundToken.balanceOf(mapleTokenAddress)
    
    expect(fundTokenBalance / 10**fundTokenDecimals).to.equal(100)
    expect(await mapleToken.updateFundsReceived())

    const accounts = await ethers.provider.listAccounts()
    const withdrawableFundsOfGovernor = await mapleToken.withdrawableFundsOf(governor)
    const accumulativeFundsOfGovernor = await mapleToken.accumulativeFundsOf(governor)
    const withdrawableFundsOfAccountOne = await mapleToken.withdrawableFundsOf(accounts[1])
    const accumulativeFundsOfAccountOne = await mapleToken.accumulativeFundsOf(accounts[1])

    expect(BigInt(withdrawableFundsOfGovernor)).to.equal(BigInt(accumulativeFundsOfGovernor))
    expect(BigInt(withdrawableFundsOfAccountOne)).to.equal(BigInt(accumulativeFundsOfAccountOne))
    expect(BigInt(withdrawableFundsOfGovernor)).to.equal(BigInt(99997999))
    expect(BigInt(withdrawableFundsOfAccountOne)).to.equal(BigInt(1999))

  })

  it('FDT: withdrawFunds() ', async function () {
    
    // Withdraw the fundsToken and confirm withdrawnFundsOf() is correct for appropriate parties
    // Confirm other internal accounting with withdrawableFundsOf() and accumulativeFundsOf() view function

    const accounts = await ethers.provider.listAccounts()
    const fundTokenDecimals = await fundToken.decimals()

    expect(await mapleToken.withdrawFunds())

    const withdrawnFundsOfGovernor = await mapleToken.withdrawnFundsOf(governor)
    const withdrawableFundsOfGovernor = await mapleToken.withdrawableFundsOf(governor)
    const accumulativeFundsOfGovernor = await mapleToken.accumulativeFundsOf(governor)
    
    expect(BigInt(withdrawnFundsOfGovernor)).to.equal(BigInt(99997999))
    expect(BigInt(accumulativeFundsOfGovernor)).to.equal(BigInt(99997999))
    expect(withdrawableFundsOfGovernor).to.equal(0)

    expect(await mapleTokenExternal.withdrawFunds())

    const withdrawnFundsOfAccountOne = await mapleToken.withdrawnFundsOf(accounts[1])
    const withdrawableFundsOfAccountOne = await mapleToken.withdrawableFundsOf(accounts[1])
    const accumulativeFundsOfAccountOne = await mapleToken.accumulativeFundsOf(accounts[1])

    expect(BigInt(withdrawnFundsOfAccountOne)).to.equal(BigInt(1999))
    expect(BigInt(accumulativeFundsOfAccountOne)).to.equal(BigInt(1999))
    expect(withdrawableFundsOfAccountOne).to.equal(0)

  })

})
