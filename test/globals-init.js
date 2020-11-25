const { expect, assert } = require("chai");

const globalAddress = require("../../contracts/localhost/addresses/MapleGlobals.address");
const globalABI = require("../../contracts/localhost/abis/MapleGlobals.abi");
const mapleTokenAddress = require("../../contracts/localhost/addresses/MapleToken.address");

describe("Maple Globals init", function () {
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

  it("paymentInterval mapping is initialized properly", async function () {
    // Valid cases.
    const paymentIntervalMonthlyValid = await mapleGlobals.validPaymentIntervalSeconds(2592000);
    const paymentIntervalQuarterlyValid = await mapleGlobals.validPaymentIntervalSeconds(7776000);
    const paymentIntervalSemiAnnuallyValid = await mapleGlobals.validPaymentIntervalSeconds(15552000);
    const paymentIntervalAnnuallyValid = await mapleGlobals.validPaymentIntervalSeconds(31104000);
    expect(paymentIntervalMonthlyValid);
    expect(paymentIntervalQuarterlyValid);
    expect(paymentIntervalSemiAnnuallyValid);
    expect(paymentIntervalAnnuallyValid);
    // Invalid cases.
    const paymentIntervalZeroInvalid = await mapleGlobals.validPaymentIntervalSeconds(0);
    const paymentIntervalMonthlyInvalid = await mapleGlobals.validPaymentIntervalSeconds(2592001);
    expect(!paymentIntervalZeroInvalid);
    expect(!paymentIntervalMonthlyInvalid);
  });

});
