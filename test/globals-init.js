const { expect, assert } = require("chai");

const globalAddress = require("../../contracts/localhost/addresses/MapleGlobals.address");
const globalABI = require("../../contracts/localhost/abis/MapleGlobals.abi");
const mapleTokenAddress = require("../../contracts/localhost/addresses/MapleToken.address");

const governor = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";

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
    expect(governorFetch).to.equal(governor);
    expect(mapleTokenFetch).to.equal(mapleTokenAddress);
    expect(establishmentFeeFetch).to.equal(200);
    expect(treasuryFeeFetch).to.equal(20);
    expect(gracePeriodFetch).to.equal(432000);
    expect(stakeRequiredFetch).to.equal(25000);
  });
});
