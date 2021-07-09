// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { TestUtil } from "test/TestUtil.sol";

contract PoolExcessTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpActors();
        setUpBalancerPoolForPools();
        setUpLiquidityPools();
        createLoan();
    }

    function setUpLoan() public {
        // Fund the pool
        mint("USDC", address(leo), 20_000_000 * USD);
        leo.approve(USDC, address(pool1), MAX_UINT);
        leo.approve(USDC, address(pool2), MAX_UINT);
        leo.deposit(address(pool1), 10_000_000 * USD);
        leo.deposit(address(pool2), 10_000_000 * USD);

        // Fund the loan
        pat.fundLoan(address(pool1), address(loan1), address(dlFactory1), 1_000_000 * USD);
        pam.fundLoan(address(pool2), address(loan1), address(dlFactory1), 3_000_000 * USD);
    }

    function test_unwind_loan_reclaim() public {

        setUpLoan();

        // Warp and call unwind()
        hevm.warp(loan1.createdAt() + globals.fundingPeriod() + 1);
        assertTrue(bob.try_unwind(address(loan1)));

        uint256 principalOut_a_pre = pool1.principalOut();
        uint256 principalOut_b_pre = pool2.principalOut();
        uint256 llBalance_a_pre = IERC20(pool1.liquidityAsset()).balanceOf(pool1.liquidityLocker());
        uint256 llBalance_b_pre = IERC20(pool2.liquidityAsset()).balanceOf(pool2.liquidityLocker());

        // Claim unwind() excessReturned
        uint256[7] memory vals_a = pat.claim(address(pool1), address(loan1), address(dlFactory1));
        uint256[7] memory vals_b = pam.claim(address(pool2), address(loan1), address(dlFactory1));

        uint256 principalOut_a_post = pool1.principalOut();
        uint256 principalOut_b_post = pool2.principalOut();
        uint256 llBalance_a_post = IERC20(pool1.liquidityAsset()).balanceOf(pool1.liquidityLocker());
        uint256 llBalance_b_post = IERC20(pool2.liquidityAsset()).balanceOf(pool2.liquidityLocker());

        assertEq(principalOut_a_pre - principalOut_a_post, vals_a[4]);
        assertEq(principalOut_b_pre - principalOut_b_post, vals_b[4]);
        assertEq(llBalance_a_post - llBalance_a_pre, vals_a[4]);
        assertEq(llBalance_b_post - llBalance_b_pre, vals_b[4]);

        // pool1 invested 1mm USD
        // pool2 invested 3mm USD
        withinDiff(principalOut_a_pre - principalOut_a_post, 1_000_000 * USD, 1);
        withinDiff(principalOut_b_pre - principalOut_b_post, 3_000_000 * USD, 1);
    }

}
