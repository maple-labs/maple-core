// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "test/TestUtil.sol";

import "test/user/Custodian.sol";

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

    function test_custody_and_transfer(uint256 stakeAmt, uint256 custodyAmt1, uint256 custodyAmt2) public {
        Custodian custodian1 = new Custodian();  // Custodial contract for StakeLockerFDTs - will start out as liquidity mining but could be broader DeFi eventually
        Custodian custodian2 = new Custodian();  // Custodial contract for StakeLockerFDTs - will start out as liquidity mining but could be broader DeFi eventually

        stakeAmt    = constrictToRange(stakeAmt,    100, bPool.balanceOf(address(sam)), true);  // 100 wei - whole BPT bal (Sid and Sam have the same BPT balance)
        custodyAmt1 = constrictToRange(custodyAmt1,  40, stakeAmt / 2,                  true);  //  40 wei - half of stake
        custodyAmt2 = constrictToRange(custodyAmt2,  40, stakeAmt / 2,                  true);  //  40 wei - half of stake

        // Make StakeLocker public and stake tokens
        pat.openStakeLockerToPublic(address(stakeLocker1));
        sam.approve(address(bPool), address(stakeLocker1), stakeAmt);
        sid.approve(address(bPool), address(stakeLocker1), stakeAmt);
        sam.stake(address(stakeLocker1),                   stakeAmt);
        sid.stake(address(stakeLocker1),                   stakeAmt);

        pat.setStakeLockerLockupPeriod(address(stakeLocker1), 0);

        // Testing failure modes with Sam
        assertTrue(!sam.try_increaseCustodyAllowance(address(stakeLocker1), address(0),              stakeAmt));  // P:INVALID_ADDRESS
        assertTrue(!sam.try_increaseCustodyAllowance(address(stakeLocker1), address(custodian1),            0));  // P:INVALID_AMT
        assertTrue(!sam.try_increaseCustodyAllowance(address(stakeLocker1), address(custodian1), stakeAmt + 1));  // P:INSUF_BALANCE
        assertTrue( sam.try_increaseCustodyAllowance(address(stakeLocker1), address(custodian1),     stakeAmt));  // Sam can custody entire balance

        // Testing state transition and transfers with Sid
        assertEq(stakeLocker1.custodyAllowance(address(sid), address(custodian1)), 0);
        assertEq(stakeLocker1.totalCustodyAllowance(address(sid)),                 0);

        sid.increaseCustodyAllowance(address(stakeLocker1), address(custodian1), custodyAmt1);

        assertEq(stakeLocker1.custodyAllowance(address(sid), address(custodian1)), custodyAmt1);  // Sid gives custody to custodian 1
        assertEq(stakeLocker1.totalCustodyAllowance(address(sid)),                 custodyAmt1);  // Total custody allowance goes up

        sid.increaseCustodyAllowance(address(stakeLocker1), address(custodian2), custodyAmt2);

        assertEq(stakeLocker1.custodyAllowance(address(sid), address(custodian2)),               custodyAmt2);  // Sid gives custody to custodian 2
        assertEq(stakeLocker1.totalCustodyAllowance(address(sid)),                 custodyAmt1 + custodyAmt2);  // Total custody allowance goes up

        uint256 transferableAmt = stakeAmt - custodyAmt1 - custodyAmt2;

        assertEq(stakeLocker1.balanceOf(address(sid)), stakeAmt);
        assertEq(stakeLocker1.balanceOf(address(sue)),        0);

        assertTrue(!sid.try_transfer(address(stakeLocker1), address(sue), transferableAmt + 1));  // Sid cannot transfer more than balance - totalCustodyAllowance
        assertTrue( sid.try_transfer(address(stakeLocker1), address(sue),     transferableAmt));  // Sid can transfer transferableAmt

        assertEq(stakeLocker1.balanceOf(address(sid)), stakeAmt - transferableAmt);
        assertEq(stakeLocker1.balanceOf(address(sue)), transferableAmt);
    }

    function test_custody_and_unstake(uint256 stakeAmt, uint256 custodyAmt) public {
        Custodian custodian = new Custodian();

        uint256 startingBptBal = bPool.balanceOf(address(sam));

        stakeAmt   = constrictToRange(stakeAmt,   1, startingBptBal, true);  // 1 wei - whole BPT bal
        custodyAmt = constrictToRange(custodyAmt, 1, stakeAmt,       true);  // 1 wei - stakeAmt

        // Make StakeLocker public and stake tokens
        pat.openStakeLockerToPublic(address(stakeLocker1));
        sam.approve(address(bPool), address(stakeLocker1), stakeAmt);
        sam.stake(address(stakeLocker1),                   stakeAmt);

        pat.setStakeLockerLockupPeriod(address(stakeLocker1), 0);

        assertEq(stakeLocker1.custodyAllowance(address(sam), address(custodian)), 0);
        assertEq(stakeLocker1.totalCustodyAllowance(address(sam)),                0);

        sam.increaseCustodyAllowance(address(stakeLocker1), address(custodian), custodyAmt);

        assertEq(stakeLocker1.custodyAllowance(address(sam), address(custodian)), custodyAmt);
        assertEq(stakeLocker1.totalCustodyAllowance(address(sam)),                custodyAmt);

        uint256 unstakeableAmt = stakeAmt - custodyAmt;

        assertEq(stakeLocker1.balanceOf(address(sam)), stakeAmt);

        make_unstakeable(sam, stakeLocker1);

        assertTrue(!sam.try_unstake(address(stakeLocker1), unstakeableAmt + 1));
        assertTrue( sam.try_unstake(address(stakeLocker1),     unstakeableAmt));

        assertEq(stakeLocker1.balanceOf(address(sam)),                  custodyAmt);
        assertEq(bPool.balanceOf(address(sam)),       startingBptBal - custodyAmt);
    }

    function test_transferByCustodian(uint256 stakeAmt, uint256 custodyAmt) public {
        Custodian custodian = new Custodian();  // Custodial contract for PoolFDTs - will start out as liquidity mining but could be broader DeFi eventually

        stakeAmt   = constrictToRange(stakeAmt,   1, bPool.balanceOf(address(sam)), true);  // 1 wei - whole BPT bal
        custodyAmt = constrictToRange(custodyAmt, 1, stakeAmt,                      true);  // 1 wei - stakeAmt

        // Make StakeLocker public and stake tokens
        pat.openStakeLockerToPublic(address(stakeLocker1));
        sam.approve(address(bPool), address(stakeLocker1), stakeAmt);
        sam.stake(address(stakeLocker1),                   stakeAmt);

        sam.increaseCustodyAllowance(address(stakeLocker1), address(custodian), custodyAmt);

        assertEq(stakeLocker1.custodyAllowance(address(sam), address(custodian)), custodyAmt);  // Sam gives custody to custodian
        assertEq(stakeLocker1.totalCustodyAllowance(address(sam)),                custodyAmt);  // Total custody allowance goes up

        assertTrue(!custodian.try_transferByCustodian(address(stakeLocker1), address(sam), address(sid),     custodyAmt));  // P:INVALID_RECEIVER
        assertTrue(!custodian.try_transferByCustodian(address(stakeLocker1), address(sam), address(sam),              0));  // P:INVALID_AMT
        assertTrue(!custodian.try_transferByCustodian(address(stakeLocker1), address(sam), address(sam), custodyAmt + 1));  // P:INSUF_ALLOWANCE
        assertTrue( custodian.try_transferByCustodian(address(stakeLocker1), address(sam), address(sam),     custodyAmt));  // Able to transfer custody amount back

        assertEq(stakeLocker1.custodyAllowance(address(sam), address(custodian)), 0);  // Custodian allowance has been reduced
        assertEq(stakeLocker1.totalCustodyAllowance(address(sam)),                0);  // Total custody allowance has been reduced, giving Sam access to funds again
    }
}
