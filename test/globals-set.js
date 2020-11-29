const { expect, assert, should } = require("chai");

const globalAddress = require("../../contracts/localhost/addresses/MapleGlobals.address");
const gloablABI = require("../../contracts/localhost/abis/MapleGlobals.abi");
const mapleTokenAddress = require("../../contracts/localhost/addresses/MapleToken.address");

describe("MapleGlobals.sol Interactions", function () {
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
    
    await mapleGlobals.setEstablishmentFee(200);
    const establishmentFeeRevert = await mapleGlobals.establishmentFeeBasisPoints();
    expect(establishmentFeeRevert).to.equal(200);

    await mapleGlobals.setTreasurySplit(30);
    const treasuryFeeFetch = await mapleGlobals.treasuryFeeBasisPoints();
    expect(treasuryFeeFetch).to.equal(30);

    await mapleGlobals.setTreasurySplit(20);
    const treasuryFeeRevert = await mapleGlobals.treasuryFeeBasisPoints();
    expect(treasuryFeeRevert).to.equal(20);

    await mapleGlobals.setGracePeriod(86400);
    const gracePeriodFetch = await mapleGlobals.gracePeriod();
    expect(gracePeriodFetch).to.equal(86400);

    await mapleGlobals.setGracePeriod(432000);
    const gracePeriodRevert = await mapleGlobals.gracePeriod();
    expect(gracePeriodRevert).to.equal(432000);

    await mapleGlobals.setStakeRequired(35000);
    const stakeRequiredFetch = await mapleGlobals.stakeAmountRequired();
    expect(stakeRequiredFetch).to.equal(35000);

    await mapleGlobals.setStakeRequired(25000);
    const stakeRequiredRevert = await mapleGlobals.stakeAmountRequired();
    expect(stakeRequiredRevert).to.equal(25000);

    await mapleGlobals.setUnstakeDelay(1000);
    const unstakeDelayFetch = await mapleGlobals.unstakeDelay();
    expect(unstakeDelayFetch).to.equal(1000);

    await mapleGlobals.setUnstakeDelay(7776000);
    const unstakeDelayRevert = await mapleGlobals.unstakeDelay();
    expect(unstakeDelayRevert).to.equal(7776000);

    await mapleGlobals.setGovernor(accounts[1]);
    const governorFetch = await mapleGlobals.governor();
    expect(governorFetch).to.equal(accounts[1]);
  });

  it("check msg.sender throws revert error", async function () {
    await expect(mapleGlobals.setEstablishmentFee(50)).to.be.revertedWith(
      "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR"
    );

    await expect(mapleGlobals.setTreasurySplit(30)).to.be.revertedWith(
      "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR"
    );

    await expect(mapleGlobals.setGracePeriod(86400)).to.be.revertedWith(
      "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR"
    );

    await expect(mapleGlobals.setStakeRequired(30000)).to.be.revertedWith(
      "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR"
    );

    await expect(mapleGlobals.setUnstakeDelay(86400)).to.be.revertedWith(
      "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR"
    );

    const BUNK_ADDRESS_AMORTIZATION = "0x0000000000000000000000000000000000000003";

    await expect(mapleGlobals.setInterestStructureCalculator(
      ethers.utils.formatBytes32String('AMORTIZATION'),
      BUNK_ADDRESS_AMORTIZATION
    )).to.be.revertedWith(
      "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR"
    );

    await expect(mapleGlobals.setGovernor(accounts[1])).to.be.revertedWith(
      "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR"
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

  it("state variables have correct init values (reverted from prior tests)", async function () {
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
  
});
