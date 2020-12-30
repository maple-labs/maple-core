const { expect, assert, should } = require("chai");
const artpath = "../../contracts/" + network.name + "/";

const globalAddress = require(artpath + "addresses/MapleGlobals.address");
const gloablABI = require(artpath + "abis/MapleGlobals.abi");
const mapleTokenAddress = require(artpath + "addresses/MapleToken.address");

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

    await mapleGlobals.setStakeRequired(0);
    const stakeRequiredRevert = await mapleGlobals.stakeAmountRequired();
    expect(stakeRequiredRevert).to.equal(0);

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

    const BUNK_ADDRESS = "0x0000000000000000000000000000000000000003";

    await expect(mapleGlobals.addCalculator(BUNK_ADDRESS)).to.be.revertedWith(
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

    await mapleGlobals2.setGovernor(accounts[0], { gasLimit: 6000000 });
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
    expect(stakeRequiredFetch).to.equal(0);
    expect(unstakeDelay).to.equal(7776000);
  });

  it("test priceFeed data not null", async function () {
    const ETH_USD_ORACLE_ADDRESS = await mapleGlobals.tokenPriceFeed(
      WETHAddress
    );
    const WBTC_USD_ORACLE_ADDRESS = await mapleGlobals.tokenPriceFeed(
      WBTCAddress
    );
    const DAI_USD_ORACLE_ADDRESS = await mapleGlobals.tokenPriceFeed(
      DAIAddress
    );
    const USDC_USD_ORACLE_ADDRESS = await mapleGlobals.tokenPriceFeed(
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
