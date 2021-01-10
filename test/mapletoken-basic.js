const { expect, assert } = require("chai");
const BigNumber = require("bignumber.js");
const artpath = "../../contracts/" + network.name + "/";

const mplAddress = require(artpath + "addresses/MapleToken.address.js");
const mplABI = require(artpath + "abis/MapleToken.abi.js");
const fundTokenAddress = require(artpath +
  "addresses/MintableTokenUSDC.address.js");
const fundTokenABI = require(artpath + "abis/MintableTokenUSDC.abi.js");

describe.skip("Maple Token", function () {
  let mpl, mplExternal;
  let fundToken, fundTokenExternal;
  let governor;
  before(async () => {
    const accounts = await ethers.provider.listAccounts();
    governor = accounts[0];
    mpl = new ethers.Contract(
      mplAddress,
      mplABI,
      ethers.provider.getSigner(0)
    );
    mplExternal = new ethers.Contract(
      mplAddress,
      mplABI,
      ethers.provider.getSigner(1)
    );
    fundToken = new ethers.Contract(
      fundTokenAddress,
      fundTokenABI,
      ethers.provider.getSigner(0)
    );
    fundTokenExternal = new ethers.Contract(
      fundTokenAddress,
      fundTokenABI,
      ethers.provider.getSigner(1)
    );
  });

  xit("msg.sender (Governor) has first minted 10mm tokens, and supply is 10mm", async function () {
    const decimals = await mpl.decimals();
    const balanceOfGovernor = await mpl.balanceOf(governor);
    const supply = await mpl.totalSupply();

    expect(balanceOfGovernor / 10 ** decimals).to.equal(9900000);
    expect(supply._hex / 10 ** decimals).to.equal(10000000);
  });

  xit("correct initialization of variables", async function () {
    const decimals = await mpl.decimals();
    const name = await mpl.name();
    const symbol = await mpl.symbol();

    expect(decimals).to.equal(18);
    expect(name).to.equal("MapleToken");
    expect(symbol).to.equal("MPL");
  });

  xit("transfer() functionality", async function () {
    // Transfer 100 (10**decimals) tokens to another account from Governor, check balances.

    const accounts = await ethers.provider.listAccounts();
    const decimals = await mpl.decimals();
    const amountToTransfer = BigInt(100 * 10 ** decimals);
    const initBalanceOfGovernor = BigInt(await mpl.balanceOf(governor));
    expect(await mpl.transfer(accounts[1], amountToTransfer.toString()));

    const balanceOfGovernor = BigInt(await mpl.balanceOf(governor));
    const balanceOfReceiver = BigInt(await mpl.balanceOf(accounts[1]));

    expect(balanceOfGovernor).to.equal(
      initBalanceOfGovernor - amountToTransfer
    );
    expect(balanceOfReceiver).to.equal(amountToTransfer);
  });

  xit("transferFrom() functionality", async function () {
    // Approve 100 (10**18) tokens to another account from Governor.
    // Have another account call the transferFrom() function, check balances.

    const accounts = await ethers.provider.listAccounts();
    const decimals = await mpl.decimals();
    const amountToApproveTransfer = BigInt(100 * 10 ** decimals);
    const initBalanceOfGovernor = BigInt(await mpl.balanceOf(governor));
    const initBalanceOfReceiver = BigInt(
      await mpl.balanceOf(accounts[1])
    );
    expect(await mpl.approve(accounts[1], amountToApproveTransfer));

    const approvalAmount = BigInt(
      await mpl.allowance(governor, accounts[1])
    );

    expect(approvalAmount).to.equal(amountToApproveTransfer);

    // Reverts when calling via mpl, not when calling mplExternal (see: before hook lines 14-25)
    await expect(
      mpl.transferFrom(accounts[2], accounts[1], amountToApproveTransfer)
    ).to.be.revertedWith("transfer amount exceeds balance");

    expect(
      await mplExternal.transferFrom(
        governor,
        accounts[1],
        amountToApproveTransfer
      )
    );

    const balanceOfGovernor = BigInt(await mpl.balanceOf(governor));
    const balanceOfReceiver = BigInt(await mpl.balanceOf(accounts[1]));

    // Balance difference should be -amountToApproveTransfer from start of test.
    expect(balanceOfGovernor).to.equal(
      initBalanceOfGovernor - amountToApproveTransfer
    );
    // Receiver should have +amountToApproveTransfer, given receiver obtained 100 tokens in last test.
    expect(balanceOfReceiver).to.equal(
      initBalanceOfReceiver + amountToApproveTransfer
    );
  });

  xit("FDT: fundsToken instatiation ", async function () {
    // Check the mpl has the correct fundsToken address (USDC, or DAI)
    const fetchFundTokenAddress = await mpl.fundsToken();
    expect(fetchFundTokenAddress).to.equal(fundTokenAddress);
  });

  xit("FDT: mint fundsToken, updateFunds() ", async function () {
    // Mint the fundsToken inside the mpl contract, and call updateFunds()
    // Confirm that withdrawableFundsOf() / accumulativeFundsOf() view functions show correct data

    const fundTokenDecimals = await fundToken.decimals();
    const amountToMint = BigInt(100);

    // Please note that mintSpecial() takes in whole number (i.e. 100) and mints (100 * 10**decimals), thus handles conversion.
    expect(await fundToken.mintSpecial(mplAddress, amountToMint));

    const fundTokenBalance = await fundToken.balanceOf(mplAddress);

    expect(fundTokenBalance / 10 ** fundTokenDecimals).to.equal(100);
    expect(await mpl.updateFundsReceived());

    const accounts = await ethers.provider.listAccounts();
    const withdrawableFundsOfGovernor = await mpl.withdrawableFundsOf(
      governor
    );
    const accumulativeFundsOfGovernor = await mpl.accumulativeFundsOf(
      governor
    );
    const withdrawableFundsOfAccountOne = await mpl.withdrawableFundsOf(
      accounts[1]
    );
    const accumulativeFundsOfAccountOne = await mpl.accumulativeFundsOf(
      accounts[1]
    );

    const mplSupply = await mpl.totalSupply();
    const mplDecimals = await mpl.decimals();
    const pointsMultiplier = 2 ** 128;
    const pointsPerShare = pointsMultiplier * mplSupply;
    const mplBalanceGovernor = await mpl.balanceOf(governor);
    const mplBalanceAccountOne = await mpl.accumulativeFundsOf(
      accounts[1]
    );

    const expectedWithdrawGovernor =
      (pointsPerShare * mplBalanceGovernor) /
      pointsMultiplier /
      10 ** mplDecimals;
    const expectedWithdrawAccountOne =
      (pointsPerShare * mplBalanceAccountOne) /
      pointsMultiplier /
      10 ** mplDecimals;

    expect(withdrawableFundsOfGovernor).to.equal(accumulativeFundsOfGovernor);
    expect(withdrawableFundsOfAccountOne).to.equal(
      accumulativeFundsOfAccountOne
    );
    expect(withdrawableFundsOfGovernor).to.equal(98997999);
    expect(withdrawableFundsOfAccountOne).to.equal(1999);
  });

  xit("FDT: withdrawFunds() ", async function () {
    // Withdraw the fundsToken and confirm withdrawnFundsOf() is correct for appropriate parties
    // Confirm other internal accounting with withdrawableFundsOf() and accumulativeFundsOf() view function

    const accounts = await ethers.provider.listAccounts();
    const fundTokenDecimals = await fundToken.decimals();

    expect(await mpl.withdrawFunds());

    const withdrawnFundsOfGovernor = await mpl.withdrawnFundsOf(
      governor
    );
    const withdrawableFundsOfGovernor = await mpl.withdrawableFundsOf(
      governor
    );
    const accumulativeFundsOfGovernor = await mpl.accumulativeFundsOf(
      governor
    );
    expect(withdrawnFundsOfGovernor).to.equal(98997999);
    expect(accumulativeFundsOfGovernor).to.equal(98997999);
    expect(withdrawableFundsOfGovernor).to.equal(0);

    expect(await mplExternal.withdrawFunds());

    const withdrawnFundsOfAccountOne = await mpl.withdrawnFundsOf(
      accounts[1]
    );
    const withdrawableFundsOfAccountOne = await mpl.withdrawableFundsOf(
      accounts[1]
    );
    const accumulativeFundsOfAccountOne = await mpl.accumulativeFundsOf(
      accounts[1]
    );
    expect(withdrawnFundsOfAccountOne).to.equal(1999);
    expect(accumulativeFundsOfAccountOne).to.equal(1999);
    expect(withdrawableFundsOfAccountOne).to.equal(0);
  });
});
