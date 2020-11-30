const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");

const DAIAddress = require("../../contracts/localhost/addresses/MintableTokenDAI.address.js");
const DAIABI = require("../../contracts/localhost/abis/MintableTokenDAI.abi.js");
const USDCAddress = require("../../contracts/localhost/addresses/MintableTokenUSDC.address.js");
const USDCABI = require("../../contracts/localhost/abis/MintableTokenUSDC.abi.js");
const MPLAddress = require("../../contracts/localhost/addresses/MapleToken.address.js");
const MPLABI = require("../../contracts/localhost/abis/MapleToken.abi.js");
const WETHAddress = require("../../contracts/localhost/addresses/WETH9.address.js");
const WETHABI = require("../../contracts/localhost/abis/WETH9.abi.js");
const WBTCAddress = require("../../contracts/localhost/addresses/WBTC.address.js");
const WBTCABI = require("../../contracts/localhost/abis/WBTC.abi.js");
const LVFactoryAddress = require("../../contracts/localhost/addresses/LoanVaultFactory.address.js");
const LVFactoryABI = require("../../contracts/localhost/abis/LoanVaultFactory.abi.js");
const FLFAddress = require("../../contracts/localhost/addresses/LoanVaultFundingLockerFactory.address.js");
const FLFABI = require("../../contracts/localhost/abis/LoanVaultFundingLockerFactory.abi.js");
const CLFAddress = require("../../contracts/localhost/addresses/CollateralLockerFactory.address.js");
const CLFABI = require("../../contracts/localhost/abis/CollateralLockerFactory.abi.js");
const LALFAddress = require("../../contracts/localhost/addresses/LiquidityLockerFactory.address.js");
const LALFABI = require("../../contracts/localhost/abis/LiquidityLockerFactory.abi.js");
const GlobalsAddress = require("../../contracts/localhost/addresses/MapleGlobals.address.js");
const GlobalsABI = require("../../contracts/localhost/abis/MapleGlobals.abi.js");
const LoanVaultABI = require("../../contracts/localhost/abis/LoanVault.abi.js");
const LoanVaultFundingLockerFactoryAbi = require("../../contracts/localhost/abis/LoanVaultFundingLockerFactory.abi.js");

describe("fundLoan() in LoanVault.sol", function () {

  const BUNK_ADDRESS = "0x0000000000000000000000000000000000000020";

  let DAI,
    USDC,
    MPL,
    WETH,
    WBTC,
    LoanVaultFactory,
    FundingLockerFactory,
    CollateralLockerFactory,
    Globals,
    accounts;

  before(async () => {
    accounts = await ethers.provider.listAccounts();
    DAI = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(0));
    DAI_EXT_1 = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(1));
    DAI_EXT_2 = new ethers.Contract(DAIAddress, DAIABI, ethers.provider.getSigner(2));
    USDC = new ethers.Contract(
      USDCAddress,
      USDCABI,
      ethers.provider.getSigner(0)
    );
    MPL = new ethers.Contract(MPLAddress, MPLABI, ethers.provider.getSigner(0));
    WETH = new ethers.Contract(
      WETHAddress,
      WETHABI,
      ethers.provider.getSigner(0)
    );
    WBTC = new ethers.Contract(
      WBTCAddress,
      WBTCABI,
      ethers.provider.getSigner(0)
    );
    LoanVaultFactory = new ethers.Contract(
      LVFactoryAddress,
      LVFactoryABI,
      ethers.provider.getSigner(0)
    );
    FundingLockerFactory = new ethers.Contract(
      FLFAddress,
      FLFABI,
      ethers.provider.getSigner(0)
    );
    Globals = new ethers.Contract(
      GlobalsAddress,
      GlobalsABI,
      ethers.provider.getSigner(0)
    );
  });

  let vaultAddress;

  it("createLoanVault() with signer(0)", async function () {

    
    // Grab preIncrementor to get LoanVaultID
    // Note: consider networkVersion=1 interactions w.r.t. async flow
    const preIncrementorValue = await LoanVaultFactory.loanVaultsCreated();

    // 5% APR, 90 Day Term, 30 Day Interval, 1000 DAI, 
    await LoanVaultFactory.createLoanVault(
      DAIAddress,
      WETHAddress,
      [5000, 90, 30, 1000000000000, 0, 7], 
      ethers.utils.formatBytes32String('BULLET')
    )
    
    vaultAddress = await LoanVaultFactory.getLoanVault(preIncrementorValue);

  });

  it("approve() loanVault to assetRequested with signer(1)", async function () {

    await DAI_EXT_1.approve(
      vaultAddress,
      BigNumber.from(10).pow(18).mul(5)
    )

    const allowance = await DAI_EXT_1.allowance(
      accounts[1],
      vaultAddress
    )

    expect(
      allowance["_hex"]
    ).to.equals(
      BigNumber.from(10).pow(18).mul(5).toHexString()
    )

  });

  it("confirm balance fail fundLoan() with signer(1)", async function () {

    // Unapprove vault and transfer out any DAI from accounts[1]
    await DAI_EXT_1.approve(vaultAddress, 0)
    const transferOutAmount = await DAI.balanceOf(accounts[1]);
    await DAI_EXT_1.transfer(BUNK_ADDRESS, BigNumber.from(transferOutAmount["_hex"]).toString());

    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(1)
    );

    // Attempt to fund with 100 DAI
    await expect(
      LoanVault.fundLoan(
        BigNumber.from(10).pow(18).mul(100),
        accounts[1]
      )
    ).to.be.revertedWith("ERC20: transfer amount exceeds balance")

    // Mint 100 DAI and attempt to fund
    await DAI.mintSpecial(accounts[1], 100)

    await expect(
      LoanVault.fundLoan(
        BigNumber.from(10).pow(18).mul(100),
        accounts[1]
      )
    ).to.be.revertedWith("ERC20: transfer amount exceeds allowance")

  });

  it("fundLoan() with signer(1)", async function () {

    // Mint 100 DAI and attempt to fund
    await DAI.mintSpecial(accounts[1], 100)

    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(1)
    );
    
    // Approve loanVault for 100 DAI
    await DAI_EXT_1.approve(
      vaultAddress, 
      BigNumber.from(10).pow(18).mul(100)
    )

    // Attempt to fund with 100 DAI
    await LoanVault.fundLoan(
      BigNumber.from(10).pow(18).mul(100),
      accounts[1]
    )

  });

  it("confirm loanTokens minted for signer(1)", async function () {

    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(1)
    );

    // Confirm new LoanToken balance is 100(10**18)
    const tokenBalance = await LoanVault.balanceOf(accounts[1])
    
    expect(
      tokenBalance["_hex"]
    ).to.equals(
      BigNumber.from(10).pow(18).mul(100).toHexString()
    )

  });

  it("confirm fundingLocker has funding", async function () {

    LoanVault = new ethers.Contract(
      vaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(1)
    );
    
    const fundingLockerAddress = await LoanVault.fundingLocker();

    const fundingLockerBalance = await DAI.balanceOf(fundingLockerAddress);
    
    expect(
      fundingLockerBalance["_hex"]
    ).to.equals(
      BigNumber.from(10).pow(18).mul(100).toHexString()
    )

  });

});
