const { expect, assert } = require("chai");
const artpath = '../../contracts/' + network.name + '/';


const globalAddress = require(artpath + "addresses/MapleGlobals.address");
const globalABI = require(artpath + "abis/MapleGlobals.abi");
const mapleTokenAddress = require(artpath + "addresses/MapleToken.address");
const LPFactoryAddress = require(artpath + "addresses/LiquidityPoolFactory.address.js");
const LVFactoryAddress = require(artpath + "addresses/LoanVaultFactory.address.js");


describe("MapleGlobals.sol Initialization", function () {
  let mapleGlobals;

  before(async () => {
    mapleGlobals = new ethers.Contract(
      globalAddress,
      globalABI,
      ethers.provider.getSigner(0)
    );
  });

  xit("state variables have correct init values", async function () {
    const accounts = await ethers.provider.listAccounts();
    const governorFetch = await mapleGlobals.governor();
    const mapleTokenFetch = await mapleGlobals.mapleToken();
    const establishmentFeeFetch = await mapleGlobals.investorFee();
    const treasuryFeeFetch = await mapleGlobals.treasuryFee();
    const gracePeriodFetch = await mapleGlobals.gracePeriod();
    const stakeRequiredFetch = await mapleGlobals.stakeAmountRequired();
    const unstakeDelay = await mapleGlobals.unstakeDelay();
    expect(governorFetch).to.equal(accounts[0]);
    expect(mapleTokenFetch).to.equal(mapleTokenAddress);
    expect(establishmentFeeFetch).to.equal(200);
    expect(treasuryFeeFetch).to.equal(20);
    expect(gracePeriodFetch).to.equal(432000);
    expect(stakeRequiredFetch).to.equal(0);
    expect(unstakeDelay).to.equal(7776000);
  });

   it("factory addresses set properly in globals", async function () {
	const LPFaddress = await mapleGlobals.liquidityPoolFactory();
	const LVFaddress = await mapleGlobals.loanVaultFactory();
	expect(LPFaddress).to.equal(LPFactoryAddress);
	expect(LVFaddress).to.equal(LVFactoryAddress);
   })
});
