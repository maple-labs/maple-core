// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { TestUtil } from "../../../../test/TestUtil.sol";

import { IDebtLocker } from "../interfaces/IDebtLocker.sol";

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
        IDebtLocker dl  = IDebtLocker(dlFactory1.newLocker(address(loan1)));
        // Validate the storage of dlfactory.
        assertEq(  dlFactory1.owner(address(dl)), address(this));
        assertTrue(dlFactory1.isLocker(address(dl)));

        // Validate the storage of dl.
        assertEq(address(dl.loan()), address(loan1),  "Incorrect loan address");
        assertEq(dl.pool(), address(this),            "Incorrect owner of the DebtLocker");
        assertEq(address(dl.liquidityAsset()),  USDC, "Incorrect address of loan asset");
    }

}
