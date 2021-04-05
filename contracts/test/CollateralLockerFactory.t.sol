// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

contract CollateralLockerFactoryTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        createCollateralLockerFactory();
        createBorrower();
    }

    function test_newLocker() public {
        CollateralLocker cl  = CollateralLocker(clFactory.newLocker(USDC));

        // Validate the storage of clfactory.
        assertEq(clFactory.owner(address(cl)), address(this), "Invalid owner");
        assertTrue(clFactory.isLocker(address(cl)));

        // Validate the storage of cl.
        assertEq(cl.loan(), address(this), "Incorrect loan address");
        assertEq(address(cl.collateralAsset()), USDC, "Incorrect address of collateral asset");

        // Assert that no one can access collateral locker funds
        mint("USDC", address(cl),  500 * USD);
        assertTrue(!bob.try_pull(address(cl), address(bob), 10));
    }
}
