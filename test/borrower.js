const { expect, assert } = require("chai");
const { BigNumber } = require("ethers");

describe("Borrower Journey", function () {

  it("A - Fetch the list of borrowTokens / collateralTokens", async function () {

    const MapleGlobalsAddress = require("../../contracts/localhost/addresses/MapleGlobals.address");
    const MapleGlobalsABI = require("../../contracts/localhost/abis/MapleGlobals.abi");

    let MapleGlobals;

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    const List = await MapleGlobals.getValidTokens();

    // These two arrays are related, in order.
    console.log(
      List["_validBorrowTokenSymbols"],
      List["_validBorrowTokenAddresses"]
    )
    
    // These two arrays are related, in order.
    console.log(
      List["_validCollateralTokenSymbols"],
      List["_validCollateralTokenAddresses"]
    )

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

    // NOTE: Wei is not needed for these calculations, for borrower information panels.

    // 100000 = 100,000 DAI
    // 500 = 5% APR
    // 180 = 180 Day Term
    // 30 = 30 Day Payment Frequency
    // 'BULLET' = Interest Structure
    let exampleBulletTotalOwed = getTotalAmountOwed(
      100000,
      500,
      180,
      30,
      'BULLET'
    )

    // 1500000 = 1,500,000 USDC
    // 1250 = 12.5% APR
    // 360 = 360 Day Term
    // 90 = 90 Day Payment Frequency
    // 'AMORTIZATION' = Interest Structure
    let exampleAmortizationTotalOwed = getTotalAmountOwed(
      1500000,
      1250,
      360,
      90,
      'AMORTIZATION'
    )

    console.log(
      parseInt(exampleBulletTotalOwed["_hex"]),
      parseInt(exampleAmortizationTotalOwed["_hex"])
    )

  });

});
