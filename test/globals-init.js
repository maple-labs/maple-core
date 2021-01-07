const { expect, assert } = require("chai");
const artpath = "../../contracts/" + network.name + "/";

const globalAddress = require(artpath + "addresses/MapleGlobals.address");
const globalABI = require(artpath + "abis/MapleGlobals.abi");
const mplAddress = require(artpath + "addresses/MapleToken.address");
const LPFactoryAddress = require(artpath +
  "addresses/PoolFactory.address.js");
const LVFactoryAddress = require(artpath +
  "addresses/LoanFactory.address.js");

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
    const mplFetch = await mapleGlobals.mpl();
    const establishmentFeeFetch = await mapleGlobals.investorFee();
    const treasuryFeeFetch = await mapleGlobals.treasuryFee();
    const gracePeriodFetch = await mapleGlobals.gracePeriod();
    const stakeRequiredFetch = await mapleGlobals.stakeAmountRequired();
    const unstakeDelay = await mapleGlobals.unstakeDelay();
    expect(governorFetch).to.equal(accounts[0]);
    expect(mplFetch).to.equal(mplAddress);
    expect(establishmentFeeFetch).to.equal(200);
    expect(treasuryFeeFetch).to.equal(20);
    expect(gracePeriodFetch).to.equal(432000);
    expect(stakeRequiredFetch).to.equal(0);
    expect(unstakeDelay).to.equal(7776000);
  });

  it("factory addresses set properly in globals", async function () {
    const LPFaddress = await mapleGlobals.poolFactory();
    const LVFaddress = await mapleGlobals.loanFactory();
    expect(LPFaddress).to.equal(LPFactoryAddress);
    expect(LVFaddress).to.equal(LVFactoryAddress);
  });
});
