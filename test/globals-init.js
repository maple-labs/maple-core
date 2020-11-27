const { expect, assert } = require("chai");

const globalAddress = require("../../contracts/localhost/addresses/MapleGlobals.address");
const globalABI = require("../../contracts/localhost/abis/MapleGlobals.abi");
const mapleTokenAddress = require("../../contracts/localhost/addresses/MapleToken.address");
const LPFactoryAddress = require("../../contracts/localhost/addresses/LPFactory.address.js");
const LVFactoryAddress = require("../../contracts/localhost/addresses/LoanVaultFactory.address.js");


describe("MapleGlobals.sol Initialization", function () {
  let mapleGlobals;

  before(async () => {
    mapleGlobals = new ethers.Contract(
      globalAddress,
      globalABI,
      ethers.provider.getSigner(0)
    );
  });

  it("state variables have correct init values", async function () {
    const accounts = await ethers.provider.listAccounts();
    const governorFetch = await mapleGlobals.governor();
    const mapleTokenFetch = await mapleGlobals.mapleToken();
    const establishmentFeeFetch = await mapleGlobals.establishmentFeeBasisPoints();
    const treasuryFeeFetch = await mapleGlobals.treasuryFeeBasisPoints();
    const gracePeriodFetch = await mapleGlobals.gracePeriod();
    const stakeRequiredFetch = await mapleGlobals.stakeAmountRequired();
    const unstakeDelay = await mapleGlobals.unstakeDelay();
    expect(governorFetch).to.equal(accounts[0]);
    expect(mapleTokenFetch).to.equal(mapleTokenAddress);
    expect(establishmentFeeFetch).to.equal(200);
    expect(treasuryFeeFetch).to.equal(20);
    expect(gracePeriodFetch).to.equal(432000);
    expect(stakeRequiredFetch).to.equal(25000);
    expect(unstakeDelay).to.equal(7776000);
  });

   it("factory addresses set properly in globals", async function () {
	const LPFaddress = await mapleGlobals.liquidityPoolFactory();
	const LVFaddress = await mapleGlobals.loanVaultFactory();
	expect(LPFaddress).to.equal(LPFactoryAddress);
	expect(LVFaddress).to.equal(LVFactoryAddress);
   })
});
