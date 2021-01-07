const { expect, assert, should } = require("chai");
const artpath = "../../contracts/" + network.name + "/";

const globalAddress = require(artpath + "addresses/MapleGlobals.address");
const gloablABI = require(artpath + "abis/MapleGlobals.abi");
const mplAddress = require(artpath + "addresses/MapleToken.address");

const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address.js");
const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address.js");
const WBTCAddress = require(artpath + "addresses/WBTC.address.js");
const WETHAddress = require(artpath + "addresses/WETH9.address.js");
const OracleABI = require(artpath + "abis/ChainLinkEmulator.abi.js");

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

  xit("update state variables via setters", async function () {
    await mapleGlobals.setGracePeriod(86400);
    const gracePeriodFetch = await mapleGlobals.gracePeriod();
    expect(gracePeriodFetch).to.equal(86400);

    await mapleGlobals.setGracePeriod(432000);
    const gracePeriodRevert = await mapleGlobals.gracePeriod();
    expect(gracePeriodRevert).to.equal(432000);

    await mapleGlobals.setStakeRequired(35000);
    const stakeRequiredFetch = await mapleGlobals.stakeAmountRequired();
    expect(stakeRequiredFetch).to.equal(35000);

    await mapleGlobals.setStakeRequired(0);
    const stakeRequiredRevert = await mapleGlobals.stakeAmountRequired();
    expect(stakeRequiredRevert).to.equal(0);

    await mapleGlobals.setUnstakeDelay(1000);
    const unstakeDelayFetch = await mapleGlobals.unstakeDelay();
    expect(unstakeDelayFetch).to.equal(1000);

    await mapleGlobals.setUnstakeDelay(7776000);
    const unstakeDelayRevert = await mapleGlobals.unstakeDelay();
    expect(unstakeDelayRevert).to.equal(7776000);

    await mapleGlobals.setCalc(BUNK_ADDRESS, true);
    expect(await mapleGlobals.isValidCalc(BUNK_ADDRESS)).to.equal(true);
    await mapleGlobals.setCalc(BUNK_ADDRESS, false);
    expect(await mapleGlobals.isValidCalc(BUNK_ADDRESS)).to.equal(false);

    await mapleGlobals.setGovernor(accounts[1]);
    const governorFetch = await mapleGlobals.governor();
    expect(governorFetch).to.equal(accounts[1]);
  });

  // TODO: fix this
  xit("check msg.sender throws revert error", async function () {
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

    const BUNK_ADDRESS = "0x0000000000000000000000000000000000000003";

    await expect(mapleGlobals.setCalc(BUNK_ADDRESS, true)).to.be.revertedWith(
      "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR"
    );

    await expect(mapleGlobals.setGovernor(accounts[1])).to.be.revertedWith(
      "MapleGlobals::ERR_MSG_SENDER_NOT_GOVERNOR"
    );
  });

  xit("set governor back", async function () {
    const mapleGlobals2 = new ethers.Contract(
      globalAddress,
      gloablABI,
      ethers.provider.getSigner(1)
    );

    await mapleGlobals2.setGovernor(accounts[0], { gasLimit: 6000000 });
    const governorFetch = await mapleGlobals2.governor();
    expect(governorFetch).to.equal(accounts[0]);
  });

  xit("state variables have correct init values (reverted from prior tests)", async function () {
    const accounts = await ethers.provider.listAccounts();
    const governorFetch = await mapleGlobals.governor();
    const mplFetch = await mapleGlobals.mpl();
    const investorFeeFetch = await mapleGlobals.investorFee();
    const treasuryFeeFetch = await mapleGlobals.treasuryFee();
    const gracePeriodFetch = await mapleGlobals.gracePeriod();
    const stakeRequiredFetch = await mapleGlobals.stakeAmountRequired();
    const unstakeDelay = await mapleGlobals.unstakeDelay();
    expect(governorFetch).to.equal(accounts[0]);
    expect(mplFetch).to.equal(mplAddress);
    expect(investorFeeFetch).to.equal(50);
    expect(treasuryFeeFetch).to.equal(50);
    expect(gracePeriodFetch).to.equal(432000);
    expect(stakeRequiredFetch).to.equal(0);
    expect(unstakeDelay).to.equal(7776000);
  });

  it("test priceFeed data not null", async function () {
    const ETH_USD_ORACLE_ADDRESS = await mapleGlobals.assetPriceFeed(
      WETHAddress
    );
    const WBTC_USD_ORACLE_ADDRESS = await mapleGlobals.assetPriceFeed(
      WBTCAddress
    );
    const DAI_USD_ORACLE_ADDRESS = await mapleGlobals.assetPriceFeed(
      DAIAddress
    );
    const USDC_USD_ORACLE_ADDRESS = await mapleGlobals.assetPriceFeed(
      USDCAddress
    );
    ETH_USD = new ethers.Contract(
      ETH_USD_ORACLE_ADDRESS,
      OracleABI,
      ethers.provider.getSigner(0)
    );
    WBTC_USD = new ethers.Contract(
      WBTC_USD_ORACLE_ADDRESS,
      OracleABI,
      ethers.provider.getSigner(0)
    );
    DAI_USD = new ethers.Contract(
      DAI_USD_ORACLE_ADDRESS,
      OracleABI,
      ethers.provider.getSigner(0)
    );
    USDC_USD = new ethers.Contract(
      USDC_USD_ORACLE_ADDRESS,
      OracleABI,
      ethers.provider.getSigner(0)
    );

    const ETH_USD_PRICE = await ETH_USD.price();
    const WBTC_USD_PRICE = await WBTC_USD.price();
    const DAI_USD_PRICE = await DAI_USD.price();
    const USDC_USD_PRICE = await USDC_USD.price();

    expect(parseInt(ETH_USD_PRICE["_hex"])).to.not.equals(0);
    expect(parseInt(WBTC_USD_PRICE["_hex"])).to.not.equals(0);
    expect(parseInt(DAI_USD_PRICE["_hex"])).to.not.equals(0);
    expect(parseInt(USDC_USD_PRICE["_hex"])).to.not.equals(0);

    const ETH_USD_PRICE_GLOBALS = await mapleGlobals.getPrice(WETHAddress);
    const WBTC_USD_PRICE_GLOBALS = await mapleGlobals.getPrice(WBTCAddress);
    const DAI_USD_PRICE_GLOBALS = await mapleGlobals.getPrice(DAIAddress);
    const USDC_USD_PRICE_GLOBALS = await mapleGlobals.getPrice(USDCAddress);

    expect(parseInt(ETH_USD_PRICE_GLOBALS["_hex"])).to.not.equals(0);
    expect(parseInt(WBTC_USD_PRICE_GLOBALS["_hex"])).to.not.equals(0);
    expect(parseInt(DAI_USD_PRICE_GLOBALS["_hex"])).to.not.equals(0);
    expect(parseInt(USDC_USD_PRICE_GLOBALS["_hex"])).to.not.equals(0);
  });
});
