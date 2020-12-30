const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");
const artpath = '../../contracts/' + network.name + '/';

const AmortizationRepaymentCalculator = require(artpath + "addresses/AmortizationRepaymentCalculator.address.js");
const BulletRepaymentCalculator = require(artpath + "addresses/BulletRepaymentCalculator.address.js");
const LateFeeNullCalculator = require(artpath + "addresses/LateFeeNullCalculator.address.js");
const PremiumFlatCalculator = require(artpath + "addresses/PremiumFlatCalculator.address.js");



describe("Borrower Journey", function () {

  let loanVaultAddress;

  it("A - Fetch the list of borrowTokens / collateralTokens", async function () {

    const MapleGlobalsAddress = require(artpath + "addresses/MapleGlobals.address");
    const MapleGlobalsABI = require(artpath + "abis/MapleGlobals.abi");

    let MapleGlobals;

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    const List = await MapleGlobals.getValidTokens();

    // These two arrays are related, in order.
    // console.log(
    //   List["_validBorrowTokenSymbols"],
    //   List["_validBorrowTokenAddresses"]
    // )
    
    // These two arrays are related, in order.
    // console.log(
    //   List["_validCollateralTokenSymbols"],
    //   List["_validCollateralTokenAddresses"]
    // )

  });

  it("B - Calculate the total amount owed for supplied params", async function () {

    // NOTE: Import this in your file ... const { BigNumber } = require("ethers");
    // NOTE: Skip to the end of this test to see the two endpoints required to get your values.

    const getNextPaymentAmount = (
      principalOwed, // 500000 = 500,000 DAI
      APR, // 500 = 5%
      repaymentFrequencyDays, // 30 (Monthly), 90 (Quarterly), 180 (Semi-annually), 360 (Annually)
      paymentsRemaining, // (Term / repaymentFrequencyDays) = (90 Days / 30 Days) = 3 Payments Remaining
      interestStructure // 'BULLET' or 'AMORTIZATION'
    ) => {
      if (interestStructure === 'BULLET') {
        let interest = BigNumber.from(principalOwed).mul(APR).mul(repaymentFrequencyDays).div(365).div(10000);
        return paymentsRemaining == 1 ? 
          [interest.add(principalOwed), interest, principalOwed] : [interest, 0, interest];
      }
      else if (interestStructure === 'AMORTIZATION') {
        let interest = BigNumber.from(principalOwed).mul(APR).mul(repaymentFrequencyDays).div(365).div(10000);
        let principal = BigNumber.from(principalOwed).div(paymentsRemaining);
        return [interest.add(principal), interest, principal];
      }
      else {
        throw 'ERROR_INVALID_INTEREST_STRUCTURE';
      }
    }

    const getTotalAmountOwedBullet = (
      principalOwed,
      APR,
      repaymentFrequencyDays,
      paymentsRemaining
    ) => {

      let amountOwed = getNextPaymentAmount(
        principalOwed,
        APR,
        repaymentFrequencyDays,
        paymentsRemaining,
        'BULLET'
      )

      // Recursive implementation, basecases 0 and 1 for _paymentsRemaining.
      if (paymentsRemaining === 0) {
        return 0;
      }
      else if (paymentsRemaining === 1) {
        return amountOwed[0];
      }
      else {
        return amountOwed[0].add(
          getTotalAmountOwedBullet(
            principalOwed,
            APR,
            repaymentFrequencyDays,
            paymentsRemaining - 1,
            'BULLET'
          )
        );
      }

    }

    const getTotalAmountOwedAmortization = (
      principalOwed,
      APR,
      repaymentFrequencyDays,
      paymentsRemaining
    ) => { 

      let amountOwed = getNextPaymentAmount(
        principalOwed,
        APR,
        repaymentFrequencyDays,
        paymentsRemaining,
        'AMORTIZATION'
      )

      // Recursive implementation, basecases 0 and 1 for _paymentsRemaining.
      if (paymentsRemaining === 0) {
        return 0;
      }
      else if (paymentsRemaining === 1) {
        return amountOwed[0];
      }
      else {
        return amountOwed[0].add(
          getTotalAmountOwedAmortization(
            principalOwed - amountOwed[2],
            APR,
            repaymentFrequencyDays,
            paymentsRemaining - 1,
            'AMORTIZATION'
          )
        );
      }

    }

    const getTotalAmountOwed = (
      principalOwed, // a.k.a. "Loan amount", doesn't need to be in wei for info panel
      APR, // 620 = 6.2%
      termLengthDays, // [30,90,180,360,720]
      repaymentFrequencyDays, // [30,90,180,360]
      paymentStructure // 'BULLET' or 'AMORTIZATION' 
    ) => {

      if (termLengthDays % repaymentFrequencyDays != 0) { 
        throw 'ERROR_UNEVEN_TERM_LENGTH_AND_PAYMENT_INTERVAL'
      }

      if (paymentStructure === 'BULLET') {
        return getTotalAmountOwedBullet(
          principalOwed,
          APR,
          repaymentFrequencyDays,
          termLengthDays / repaymentFrequencyDays
        )
      }
      else if (paymentStructure === 'AMORTIZATION') {
        return getTotalAmountOwedAmortization(
          principalOwed,
          APR,
          repaymentFrequencyDays,
          termLengthDays / repaymentFrequencyDays
        )
      }
      else {
        throw 'ERROR_INVALID_INTEREST_STRUCTURE'
      }
      
    }

    const LOAN_AMOUNT = 100000; // 100,000 DAI
    const APR_BIPS = 1250; // 12.50%
    const TERM_DAYS = 180;
    const PAYMENT_INTERVAL_DAYS = 30;

    let exampleBulletTotalOwed = getTotalAmountOwed(
      LOAN_AMOUNT,
      APR_BIPS,
      TERM_DAYS,
      PAYMENT_INTERVAL_DAYS,
      'BULLET'
    )

    let exampleAmortizationTotalOwed = getTotalAmountOwed(
      LOAN_AMOUNT,
      APR_BIPS,
      TERM_DAYS,
      PAYMENT_INTERVAL_DAYS,
      'AMORTIZATION'
    )

    // console.log(
    //   parseInt(exampleBulletTotalOwed["_hex"]),
    //   parseInt(exampleAmortizationTotalOwed["_hex"])
    // )

  });

  it("C - Create a loan through the factory", async function () {

    const LoanVaultFactoryAddress = require(artpath + "addresses/LoanVaultFactory.address");
    const LoanVaultFactoryABI = require(artpath + "abis/LoanVaultFactory.abi");

    let LoanVaultFactory;

    LoanVaultFactory = new ethers.Contract(
      LoanVaultFactoryAddress,
      LoanVaultFactoryABI,
      ethers.provider.getSigner(0)
    );

    const preIncrementorValue = await LoanVaultFactory.loanVaultsCreated();

    // ERC-20 contracts for tokens
    const DAIAddress = require(artpath + "addresses/MintableTokenDAI.address");
    const USDCAddress = require(artpath + "addresses/MintableTokenUSDC.address");
    const WETHAddress = require(artpath + "addresses/WETH9.address");
    const WBTCAddress = require(artpath + "addresses/WBTC.address");
    
    const ERC20ABI = require(artpath + "abis/MintableTokenDAI.abi");

    DAI = new ethers.Contract(DAIAddress, ERC20ABI, ethers.provider.getSigner(0));
    USDC = new ethers.Contract(USDCAddress, ERC20ABI, ethers.provider.getSigner(0));
    WETH = new ethers.Contract(WETHAddress, ERC20ABI, ethers.provider.getSigner(0));
    WBTC = new ethers.Contract(WBTCAddress, ERC20ABI, ethers.provider.getSigner(0));

  
    const REQUESTED_ASSET = DAIAddress;
    const COLLATERAL_ASSET = WETHAddress;
    const INTEREST_STRUCTURE = 'BULLET' // 'BULLET' or 'AMORTIZATION'
    const LATE_FEE_TYPE = 'NULL' // 'NULL' only option
    const PREMIUM_TYPE = 'FLAT' // 'FLAT' only option

    const APR_BIPS = 500; // 5%
    const TERM_DAYS = 90;
    const PAYMENT_INTERVAL_DAYS = 30;
    const MIN_RAISE = BigNumber.from(
      10 // Base 10
    ).pow(
      18 // Decimial precision of REQUEST_ASSET (DAI = 18, USDC = 6)
    ).mul(
      1000 // Amount of loan request (1000 = 1,000 DAI)
    );
    const COLLATERAL_BIPS_RATIO = 5000; // 50%
    const FUNDING_PERIOD_DAYS = 7;

    await LoanVaultFactory.createLoanVault(
      REQUESTED_ASSET,
      COLLATERAL_ASSET,
      [
        APR_BIPS, 
        TERM_DAYS, 
        PAYMENT_INTERVAL_DAYS, 
        MIN_RAISE, 
        COLLATERAL_BIPS_RATIO, 
        FUNDING_PERIOD_DAYS
      ],
      [
	BulletRepaymentCalculator,
	LateFeeNullCalculator,
	PremiumFlatCalculator
      ],
      {gasLimit: 6000000}
    );

    loanVaultAddress = await LoanVaultFactory.getLoanVault(preIncrementorValue);

  });

  it("D - Simulate other users funding the loan", async function () {

    const LoanVaultABI = require(artpath + "abis/LoanVault.abi");
    const ERC20ABI = require(artpath + "abis/MintableTokenDAI.abi");
    const accounts = await ethers.provider.listAccounts();

    LoanVault = new ethers.Contract(
      loanVaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(1)
    );

    const REQUEST_ASSET_ADDRESS = await LoanVault.assetRequested();

    RequestedAsset = new ethers.Contract(
      REQUEST_ASSET_ADDRESS,
      ERC20ABI,
      ethers.provider.getSigner(1)
    )

    const AMOUNT_TO_FUND_LOAN = 1500; // Over-fund loan by 500 DAI

    // Mint tokens to accounts[1]
    await RequestedAsset.mintSpecial(accounts[1], AMOUNT_TO_FUND_LOAN);

    // Approve loan vault
    await RequestedAsset.approve(
      loanVaultAddress,
      BigNumber.from(10).pow(18).mul(AMOUNT_TO_FUND_LOAN)
    )

    // Fund the loan
    await LoanVault.fundLoan(
      BigNumber.from(10).pow(18).mul(AMOUNT_TO_FUND_LOAN), // Funding amount.
      accounts[1], // Mint loan tokens for this adddress.
      {gasLimit: 6000000} 
    )

  });

  it("E - Fetch important LoanVault information", async function () {

    const LoanVaultABI = require(artpath + "abis/LoanVault.abi");
    const ERC20ABI = require(artpath + "abis/MintableTokenDAI.abi");
    
    LoanVault = new ethers.Contract(
      loanVaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );

    const REQUEST_ASSET_ADDRESS = await LoanVault.assetRequested();
    
    RequestedAsset = new ethers.Contract(
      REQUEST_ASSET_ADDRESS,
      ERC20ABI,
      ethers.provider.getSigner(1)
    )

    const DECIMAL_PRECISION_REQUEST_ASSET = await RequestedAsset.decimals();
    const FUNDING_LOCKER_BALANCE = await LoanVault.getFundingLockerBalance();
    const MIN_RAISE = await LoanVault.minRaise();
    
    // Percentage of Target
    // console.log(
    //   parseInt(FUNDING_LOCKER_BALANCE["_hex"]) / parseInt(MIN_RAISE["_hex"]) * 100
    // )

    // Funding Locker Balance
    // console.log(
    //   parseInt(FUNDING_LOCKER_BALANCE["_hex"]) / 10**DECIMAL_PRECISION_REQUEST_ASSET
    // )

    // Min Raise
    // console.log(
    //   parseInt(MIN_RAISE["_hex"]) / 10**DECIMAL_PRECISION_REQUEST_ASSET
    // )

    const TERM_LENGTH = await LoanVault.termDays();

    // Term Length (DAYS)
    // console.log(
    //   parseInt(TERM_LENGTH["_hex"])
    // )

    const FUNDING_PERIOD_SECONDS = await LoanVault.fundingPeriodSeconds();
    const LOAN_CREATED_ON = await LoanVault.loanCreatedTimestamp();
    const LOAN_FUNDING_ENDS = parseInt(LOAN_CREATED_ON["_hex"]) + parseInt(FUNDING_PERIOD_SECONDS["_hex"])

    const SECONDS_REMAINING_FUNDING_PERIOD = LOAN_FUNDING_ENDS - (Date.now() / 1000)

    // Offer Period Remaining (DAYS)
    // console.log(
    //   SECONDS_REMAINING_FUNDING_PERIOD / 86400
    // )

  });

  it("F - Fetch collateral required for drawdown, facilitate approve() calls", async function () {
    
    const LoanVaultABI = require(artpath + "abis/LoanVault.abi");
    const ERC20ABI = require(artpath + "abis/MintableTokenDAI.abi");

    // Determine how to pull `loanVaultAddress` to feed into object below.
    LoanVault = new ethers.Contract(
      loanVaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );

    const REQUESTED_ASSET_ADDRESS = await LoanVault.assetRequested();
    const COLLATERAL_ASSET_ADDRESS = await LoanVault.assetCollateral();
    const BORROWER_ADDRESS = await LoanVault.borrower();
    
    RequestedAsset = new ethers.Contract(
      REQUESTED_ASSET_ADDRESS,
      ERC20ABI,
      ethers.provider.getSigner(0)
    )
    CollateralAsset = new ethers.Contract(
      COLLATERAL_ASSET_ADDRESS,
      ERC20ABI,
      ethers.provider.getSigner(0)
    )

    const REQUESTED_AMOUNT_DECIMALS = await RequestedAsset.decimals();
    const COLLATERAL_AMOUNT_DECIMALS = await CollateralAsset.decimals();


    // User inputs this number.
    const USER_ENTERED_DRAWDOWN_AMOUNT = 10000;

    const COLLATERAL_DRAWDOWN_AMOUNT_BASE = await LoanVault.collateralRequiredForDrawdown(
      BigNumber.from(10).pow(REQUESTED_AMOUNT_DECIMALS).mul(USER_ENTERED_DRAWDOWN_AMOUNT)
    )

    // Output this number to front-end, may need to round to two or three nearest digits.
    const COLLATERAL_REQUIRED = parseInt(COLLATERAL_DRAWDOWN_AMOUNT_BASE["_hex"]) / 10**COLLATERAL_AMOUNT_DECIMALS;

    // Use this for "infinite" approval amount calls.
    await CollateralAsset.approve(
      loanVaultAddress,
      BigNumber.from(10).pow(64)
    )

    // Use this for precise approval amount calls (would need some buffer in case price falls).
    await CollateralAsset.approve(
      loanVaultAddress,
      COLLATERAL_DRAWDOWN_AMOUNT_BASE
    )

    // Confirm user has enough approval to call drawdown() for USER_ENTERED_DRAWDOWN_AMOUNT.
    const USER_APPROVAL_TO_LOAN_VAULT = await CollateralAsset.allowance(
      BORROWER_ADDRESS, // User's address, could pull from different source for front-end.
      loanVaultAddress
    )

    // Note: Front-end wants to check greater than or equal to.
    expect(parseInt(USER_APPROVAL_TO_LOAN_VAULT["_hex"])).to.be.equals(
      parseInt(COLLATERAL_DRAWDOWN_AMOUNT_BASE["_hex"])
    )

  });

  it("H - Allow the borrower to drawdown loan", async function () {
    
    const LoanVaultABI = require(artpath + "abis/LoanVault.abi");
    const ERC20ABI = require(artpath + "abis/MintableTokenDAI.abi");

    // Determine how to pull `loanVaultAddress` to feed into object below.
    LoanVault = new ethers.Contract(
      loanVaultAddress,
      LoanVaultABI,
      ethers.provider.getSigner(0)
    );

    const REQUESTED_ASSET_ADDRESS = await LoanVault.assetRequested();
    
    RequestedAsset = new ethers.Contract(
      REQUESTED_ASSET_ADDRESS,
      ERC20ABI,
      ethers.provider.getSigner(0)
    )

    const REQUESTED_AMOUNT_DECIMALS = await RequestedAsset.decimals();

    
    // User enters amount they want to drawdown.
    const USER_ENTERED_DRAWDOWN_AMOUNT = 1000;

    // Fire this function when user goes to drawdown the USER_INPUT_DRAWDOWN_AMOUNT.
    await LoanVault.drawdown(
      BigNumber.from(10).pow(REQUESTED_AMOUNT_DECIMALS).mul(USER_ENTERED_DRAWDOWN_AMOUNT)
    );

  });

});
