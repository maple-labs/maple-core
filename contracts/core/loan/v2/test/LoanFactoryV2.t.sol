// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "test/TestUtil.sol";

contract LoanFactoryV2Test is TestUtil {

    using SafeMath for uint256;


    function setUp() public {
        setUpGlobals();
        setUpCalcs();
        setUpTokens();
        createBorrower();
        setUpFactories();
    }

    function test_createLoan_successfully() public {
        uint256[5] memory specs = [10, 10, 2, 10_000_000 * USD, 30];

        // Verify the loan gets created successfully.
        assertTrue(bob.try_createLoan(address(loanFactoryV2), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(loanFactoryV2.loansCreated(), 1, "Incorrect loan instantiation");  // Should be incremented by 1.
        ILoan loanV2 = ILoan(loanFactoryV2.loans(0));                                 // Initial value of loansCreated.
        assertTrue(loanFactoryV2.isLoan(address(loanV2)));                            // Should be considered as a loan.

        // Verify the storage of loan contract
        assertEq(loanV2.borrower(),                  address(bob), "Incorrect borrower");
        assertEq(address(loanV2.liquidityAsset()),   USDC, "Incorrect loan asset");
        assertEq(address(loanV2.collateralAsset()),  WETH, "Incorrect collateral asset");
        assertEq(loanV2.flFactory(),                 address(flFactory), "Incorrect FLF");
        assertEq(loanV2.clFactory(),                 address(clFactory), "Incorrect CLF");
        assertEq(loanV2.createdAt(),                 block.timestamp, "Incorrect created at timestamp");
        assertEq(loanV2.apr(),                       specs[0], "Incorrect APR");
        assertEq(loanV2.termDays(),                  specs[1], "Incorrect term days");
        assertEq(loanV2.paymentsRemaining(),         specs[1].div(specs[2]), "Incorrect payments remaining");
        assertEq(loanV2.paymentIntervalSeconds(),    specs[2].mul(1 days), "Incorrect payment interval in seconds");
        assertEq(loanV2.requestAmount(),             specs[3], "Incorrect request amount value");
        assertEq(loanV2.collateralRatio(),           specs[4], "Incorrect collateral ratio");
        assertEq(loanV2.fundingPeriod(),             globals.fundingPeriod(), "Incorrect funding period in seconds");
        assertEq(loanV2.defaultGracePeriod(),        globals.defaultGracePeriod(), "Incorrect default grace period in seconds");
        assertEq(loanV2.repaymentCalc(),             calcs[0], "Incorrect repayment calculator");
        assertEq(loanV2.lateFeeCalc(),               calcs[1], "Incorrect late fee calculator");
        assertEq(loanV2.premiumCalc(),               calcs[2], "Incorrect premium calculator");
        assertEq(loanV2.superFactory(),              address(loanFactoryV2), "Incorrect super factory address");
    }

}