const { expect, assert, should } = require("chai");

const globalAddress = require("../../contracts/localhost/addresses/MapleGlobals.address");
const gloablABI = require("../../contracts/localhost/abis/MapleGlobals.abi");
const mapleTokenAddress = require("../../contracts/localhost/addresses/MapleToken.address");

describe("Maple globals set", function () {

  const BUNK_ADDRESS = "0x0000000000000000000000000000000000000000";

  let mapleGlobals;

  before(async () => {
    mapleGlobals = new ethers.Contract(
      globalAddress,
      gloablABI,
      ethers.provider.getSigner(0)
    );
    accounts = await ethers.provider.listAccounts();
  });

  it("update state variables via setters", async function () {
    await mapleGlobals.setEstablishmentFee(50);
    const establishmentFeeFetch = await mapleGlobals.establishmentFeeBasisPoints();
    expect(establishmentFeeFetch).to.equal(50);

    await mapleGlobals.setTreasurySplit(30);
    const treasuryFeeFetch = await mapleGlobals.treasuryFeeBasisPoints();
    expect(treasuryFeeFetch).to.equal(30);

    await mapleGlobals.setGracePeriod(86400);
    const gracePeriodFetch = await mapleGlobals.gracePeriod();
    expect(gracePeriodFetch).to.equal(86400);

    await mapleGlobals.setStakeRequired(35000);
    const stakeRequiredFetch = await mapleGlobals.stakeAmountRequired();
    expect(stakeRequiredFetch).to.equal(35000);

    await mapleGlobals.setGovernor(accounts[1]);
    const governorFetch = await mapleGlobals.governor();
    expect(governorFetch).to.equal(accounts[1]);
  });

  it("check msg.sender throws revert error", async function () {
    await expect(mapleGlobals.setEstablishmentFee(50)).to.be.revertedWith(
      "msg.sender is not Governor"
    );

    await expect(mapleGlobals.setTreasurySplit(30)).to.be.revertedWith(
      "msg.sender is not Governor"
    );

    await expect(mapleGlobals.setGracePeriod(86400)).to.be.revertedWith(
      "msg.sender is not Governor"
    );

    await expect(mapleGlobals.setStakeRequired(30000)).to.be.revertedWith(
      "msg.sender is not Governor"
    );

    await expect(mapleGlobals.setGovernor(accounts[1])).to.be.revertedWith(
      "msg.sender is not Governor"
    );
    
    await expect(mapleGlobals.setPaymentIntervalValidity(0, true)).to.be.revertedWith(
      "msg.sender is not Governor"
    );
    
    await expect(mapleGlobals.setRepaymentCalculatorValidity(BUNK_ADDRESS, true)).to.be.revertedWith(
      "msg.sender is not Governor"
    );
    
    await expect(mapleGlobals.setPremiumCalculatorValidity(BUNK_ADDRESS, true)).to.be.revertedWith(
      "msg.sender is not Governor"
    );

  });

  it("set governor back", async function () {
    const mapleGlobals2 = new ethers.Contract(
      globalAddress,
      gloablABI,
      ethers.provider.getSigner(1)
    );

    await mapleGlobals2.setGovernor(accounts[0]);
    const governorFetch = await mapleGlobals2.governor();
    expect(governorFetch).to.equal(accounts[0]);
  });
});
