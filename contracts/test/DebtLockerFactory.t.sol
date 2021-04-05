// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

contract DebtLockerFactoryTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        createBorrower();
        setUpFactories();
        setUpCalcs();
        createLoan();
    }

    function test_newLocker() public {
        DebtLocker dl  = DebtLocker(dlFactory.newLocker(address(loan)));
        // Validate the storage of dlfactory.
        assertEq(  dlFactory.owner(address(dl)), address(this));
        assertTrue(dlFactory.isLocker(address(dl)));

        // Validate the storage of dl.
        assertEq(address(dl.loan()),       address(loan), "Incorrect loan address");
        assertEq(dl.pool(),                address(this), "Incorrect owner of the DebtLocker");
        assertEq(address(dl.liquidityAsset()),  USDC,     "Incorrect address of loan asset");
    }
}
