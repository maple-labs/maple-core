// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Custodian.sol";

contract StakeLockerCustodialTest is TestUtil {

    using SafeMath for uint256;

    function setUp() public {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpActors();
        createBalancerPool();
        transferBptsToPoolDelegateAndStakers();
        setUpLiquidityPool();
    }

    function test_custody_and_unstake(uint256 stakeAmt, uint256 custodyAmt) public {
        Custodian custodian = new Custodian();

        stakeAmt = constrictToRange(stakeAmt, 1 * WAD, bPool.balanceOf(address(sam)), true);
        custodyAmt = constrictToRange(custodyAmt, 1, stakeAmt / 2, true);

        // Make StakeLocker public and stake tokens
        pat.openStakeLockerToPublic(address(stakeLocker));
        sam.approve(address(bPool), address(stakeLocker), stakeAmt);
        sam.stake(address(stakeLocker), stakeAmt);

        pat.setStakeLockerLockupPeriod(address(stakeLocker), 0);

        assertEq(stakeLocker.custodyAllowance(address(sam), address(custodian)), 0);
        assertEq(stakeLocker.totalCustodyAllowance(address(sam)),                0);

        sam.increaseCustodyAllowance(address(stakeLocker), address(custodian), custodyAmt);

        assertEq(stakeLocker.custodyAllowance(address(sam), address(custodian)), custodyAmt, "Sam gives custody to custodian");
        assertEq(stakeLocker.totalCustodyAllowance(address(sam)), custodyAmt, "Total custody allowance goes up");

        uint256 unstakableAmt = stakeAmt - custodyAmt;

        assertEq(stakeLocker.balanceOf(address(sam)), stakeAmt);

        make_unstakable(sam, stakeLocker);
        assertTrue(!sam.try_unstake(address(stakeLocker), unstakableAmt + 1), "Sam cannot unstake more than balance - totalCustodyAllowance");

        assertTrue(sam.try_unstake(address(stakeLocker), unstakableAmt), "Sam can unstake unstakableAmt");
        assertEq(stakeLocker.balanceOf(address(sam)), custodyAmt);
    }
}
