// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { TestUtil } from "test/TestUtil.sol";

contract LoanFactoryTest is TestUtil {

    using SafeMath for uint256;


    function setUp() public {
        setUpGlobals();
        setUpCalcs();
        setUpTokens();
        createBorrower();
        setUpFactories();
    }

    function test_setGlobals() public {
        Governor fakeGov = new Governor();

        MapleGlobals globals2 = fakeGov.createGlobals(address(mpl));  // Create upgraded MapleGlobals

        assertEq(address(loanFactory.globals()), address(globals));

        assertTrue(!fakeGov.try_setGlobals(address(loanFactory), address(globals2)));  // Non-governor cannot set new globals

        globals2 = gov.createGlobals(address(mpl));      // Create upgraded MapleGlobals

        assertTrue(gov.try_setGlobals(address(loanFactory), address(globals2)));       // Governor can set new globals
        assertEq(address(loanFactory.globals()), address(globals2));                   // Globals is updated
    }

    function test_createLoan_invalid_locker_factories() public {
        gov.setValidSubFactory(address(loanFactory), address(flFactory), false);
        gov.setValidSubFactory(address(loanFactory), address(clFactory), false);
        gov.setValidLoanFactory(address(loanFactory),                    false);

        uint256[5] memory specs = [10, 10, 2, 10_000_000 * USD, 30];

        assertTrue(!bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(loanFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Add flFactory in valid list
        gov.setValidLoanFactory(address(loanFactory), true);
        gov.setValidSubFactory(address(loanFactory), address(flFactory), true);

        // Still fails as clFactory isn't a valid factory.
        assertTrue(!bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(loanFactory.loansCreated(), 0, "Colluded state");  // Should be 0.
        gov.setValidSubFactory(address(loanFactory), address(clFactory), true);  // Add clFactory in the valid list.

        // Should successfully created
        assertTrue(bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(loanFactory.loansCreated(), 1, "Incorrect loan instantiation");  // Should be incremented by 1.
    }

    function test_createLoan_invalid_calc_types() public {
        uint256[5] memory specs = [10, 10, 2, 10_000_000 * USD, 30];

        assertTrue(!bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, [calcs[1], calcs[1], calcs[2]]));
        assertEq(loanFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Incorrect type for second calculator contract.
        assertTrue(!bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, [calcs[0], calcs[2], calcs[2]]));
        assertEq(loanFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Incorrect type for third calculator contract.
        assertTrue(!bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, [calcs[0], calcs[1], calcs[0]]));
        assertEq(loanFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Should successfully created
        assertTrue(bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(loanFactory.loansCreated(), 1, "Incorrect loan instantiation");  // Should be incremented by 1.
    }

    function test_createLoan_invalid_assets_and_specs() public {
        uint256[5] memory specs = [10, 10, 2, 10_000_000 * USD, 30];

        gov.setLiquidityAsset(USDC,  false);
        gov.setCollateralAsset(WETH, false);

        assertTrue(!bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(loanFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        gov.setLiquidityAsset(USDC, true);  // Allow loan asset
        // Still fails as collateral asset is not a valid collateral asset
        assertTrue(!bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(loanFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        gov.setCollateralAsset(WETH, true);  // Set collateral asset.
        // Still fails as loan asset can't be 0x0
        assertTrue(!bob.try_createLoan(address(loanFactory), address(0), WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(loanFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Fails because of error - ERR_PAYMENT_INTERVAL_DAYS_EQUALS_ZERO
        assertTrue(!bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), [10, 10, 0, 10_000_000 * USD, 30], calcs));
        assertEq(loanFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Fails because of error - ERR_INVALID_TERM_AND_PAYMENT_INTERVAL_DIVISION
        assertTrue(!bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), [10, 19, 2, 10_000_000 * USD, 30], calcs));
        assertEq(loanFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Fails because of error - ERR_REQUEST_AMT_EQUALS_ZERO
        assertTrue(!bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), [uint256(10), 10, 2, uint256(0), 30], calcs));
        assertEq(loanFactory.loansCreated(), 0, "Colluded state");  // Should be 0.

        // Should successfully created
        assertTrue(bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(loanFactory.loansCreated(), 1, "Incorrect loan instantiation");  // Should be incremented by 1.
    }

    function test_createLoan_paused() public {
        uint256[5] memory specs = [10, 10, 2, 10_000_000 * USD, 30];

        // Pause LoanFactory and attempt createLoan()
        assertTrue(      gov.try_pause(address(loanFactory)));
        assertTrue(!bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(   loanFactory.loansCreated(), 0);

        // Unpause LoanFactory and createLoan()
        assertTrue(     gov.try_unpause(address(loanFactory)));
        assertTrue(bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(  loanFactory.loansCreated(), 1);

        // Pause protocol and attempt createLoan()
        assertTrue(      emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(   loanFactory.loansCreated(), 1);

        // Unpause protocol and createLoan()
        assertTrue(     emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(  loanFactory.loansCreated(), 2);
    }

    function test_createLoan_successfully() public {
        uint256[5] memory specs = [10, 10, 2, 10_000_000 * USD, 30];

        // Verify the loan gets created successfully.
        assertTrue(bob.try_createLoan(address(loanFactory), USDC, WETH, address(flFactory), address(clFactory), specs, calcs));
        assertEq(loanFactory.loansCreated(), 1, "Incorrect loan instantiation");  // Should be incremented by 1.
        ILoan loan = ILoan(loanFactory.loans(0));                                 // Initial value of loansCreated.
        assertTrue(loanFactory.isLoan(address(loan)));                            // Should be considered as a loan.

        // Verify the storage of loan contract
        assertEq(loan.borrower(),                  address(bob), "Incorrect borrower");
        assertEq(address(loan.liquidityAsset()),   USDC, "Incorrect loan asset");
        assertEq(address(loan.collateralAsset()),  WETH, "Incorrect collateral asset");
        assertEq(loan.flFactory(),                 address(flFactory), "Incorrect FLF");
        assertEq(loan.clFactory(),                 address(clFactory), "Incorrect CLF");
        assertEq(loan.createdAt(),                 block.timestamp, "Incorrect created at timestamp");
        assertEq(loan.apr(),                       specs[0], "Incorrect APR");
        assertEq(loan.termDays(),                  specs[1], "Incorrect term days");
        assertEq(loan.paymentsRemaining(),         specs[1].div(specs[2]), "Incorrect payments remaining");
        assertEq(loan.paymentIntervalSeconds(),    specs[2].mul(1 days), "Incorrect payment interval in seconds");
        assertEq(loan.requestAmount(),             specs[3], "Incorrect request amount value");
        assertEq(loan.collateralRatio(),           specs[4], "Incorrect collateral ratio");
        assertEq(loan.fundingPeriod(),             globals.fundingPeriod(), "Incorrect funding period in seconds");
        assertEq(loan.defaultGracePeriod(),        globals.defaultGracePeriod(), "Incorrect default grace period in seconds");
        assertEq(loan.repaymentCalc(),             calcs[0], "Incorrect repayment calculator");
        assertEq(loan.lateFeeCalc(),               calcs[1], "Incorrect late fee calculator");
        assertEq(loan.premiumCalc(),               calcs[2], "Incorrect premium calculator");
        assertEq(loan.superFactory(),              address(loanFactory), "Incorrect super factory address");
    }
}
