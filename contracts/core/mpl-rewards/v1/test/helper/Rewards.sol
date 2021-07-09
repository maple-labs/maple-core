// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { TestUtil } from "../../../../../test/TestUtil.sol";
import { Custodian } from "../../../../../test/user/Custodian.sol";
import { IStakeToken } from "./IStakeToken.sol";

contract CustodialTestHelper is TestUtil {

    function setupFarmingEcosystem() internal {
        setUpGlobals();
        setUpTokens();
        setUpOracles();
        setUpFactories();
        setUpCalcs();
        setUpActors();
        createBalancerPool(100_000 * USD, 10_000 * USD);
        transferBptsToPoolDelegatesAndStakers();
        setUpLiquidityPool();
        setUpMplRewardsFactory();
    }

    function custody_and_transfer(uint256 amt, uint256 custodyAmt1, uint256 custodyAmt2, bool isPfdtStakeAsset, IStakeToken stakeToken) public {
        Custodian custodian1 = new Custodian();  // Custodial contract for FDTs - will start out as liquidity mining but could be broader DeFi eventually
        Custodian custodian2 = new Custodian();  // Custodial contract for FDTs - will start out as liquidity mining but could be broader DeFi eventually

        if (isPfdtStakeAsset) {
            amt         = constrictToRange(amt,         100, 1E9,     true);  // $100 - $1b
            custodyAmt1 = constrictToRange(custodyAmt1,  40, amt / 2, true);  // $40 - half of deposit
            custodyAmt2 = constrictToRange(custodyAmt2,  40, amt / 2, true);  // $40 - half of deposit

            mintFundsAndDepositIntoPool(fay, pool1, amt * USD, amt * USD);
            mintFundsAndDepositIntoPool(fez, pool1, amt * USD, amt * USD);

            pat.setLockupPeriod(address(pool1), 0);

            // Convert all amounts to WAD, USD not needed for the rest of the test
            amt         *= WAD;
            custodyAmt1 *= WAD;
            custodyAmt2 *= WAD;
        } else {
            // Transfer BPTs to the Farmers i.e Fay and Fez. Although both can use interchangeably but to make code consistent chose to use Fay and Fez. 
            sam.transfer(address(bPool), address(fay), bPool.balanceOf(address(sam)));
            sid.transfer(address(bPool), address(fez), bPool.balanceOf(address(sid)));

            amt         = constrictToRange(amt,         100, bPool.balanceOf(address(fay)), true);  // 100 wei - whole BPT bal (fay and fez have the same BPT balance)
            custodyAmt1 = constrictToRange(custodyAmt1,  40, amt / 2,                       true);  //  40 wei - half of stake
            custodyAmt2 = constrictToRange(custodyAmt2,  40, amt / 2,                       true);  //  40 wei - half of stake

            // Make StakeLocker public and stake tokens
            pat.openStakeLockerToPublic(address(stakeLocker1));

            fay.approve(address(bPool), pool1.stakeLocker(), amt);
            fez.approve(address(bPool), pool1.stakeLocker(), amt);
            fay.stakeTo(                pool1.stakeLocker(), amt);
            fez.stakeTo(                pool1.stakeLocker(), amt);

            pat.setStakeLockerLockupPeriod(address(stakeLocker1), 0);
        }

        // Testing failure modes with Fay
        assertTrue(!fay.try_increaseCustodyAllowance(address(0),              amt));  // P/SL:INVALID_ADDRESS
        assertTrue(!fay.try_increaseCustodyAllowance(address(custodian1),       0));  // P/SL:INVALID_AMT
        assertTrue(!fay.try_increaseCustodyAllowance(address(custodian1), amt + 1));  // P/SL:INSUF_BALANCE
        assertTrue( fay.try_increaseCustodyAllowance(address(custodian1),     amt));  // Fay can custody entire balance

        // Testing state transition and transfers with Fez
        assertEq(stakeToken.custodyAllowance(address(fez), address(custodian1)), 0);
        assertEq(stakeToken.totalCustodyAllowance(address(fez)),                 0);

        fez.increaseCustodyAllowance(address(custodian1), custodyAmt1);

        assertEq(stakeToken.custodyAllowance(address(fez), address(custodian1)), custodyAmt1);  // Fez gives custody to custodian 1
        assertEq(stakeToken.totalCustodyAllowance(address(fez)),                 custodyAmt1);  // Total custody allowance goes up

        fez.increaseCustodyAllowance(address(custodian2), custodyAmt2);

        assertEq(stakeToken.custodyAllowance(address(fez), address(custodian2)),               custodyAmt2);  // Fez gives custody to custodian 2
        assertEq(stakeToken.totalCustodyAllowance(address(fez)),                 custodyAmt1 + custodyAmt2);  // Total custody allowance goes up

        uint256 transferableAmt = amt - custodyAmt1 - custodyAmt2;

        assertEq(stakeToken.balanceOf(address(fez)), amt);
        assertEq(stakeToken.balanceOf(address(fox)),   0);

        assertTrue(!fez.try_transfer(address(stakeToken), address(fox), transferableAmt + 1));  // Fez cannot transfer more than balance - totalCustodyAllowance
        assertTrue( fez.try_transfer(address(stakeToken), address(fox),     transferableAmt));  // Fez can transfer transferableAmt

        assertEq(stakeToken.balanceOf(address(fez)), amt - transferableAmt);
        assertEq(stakeToken.balanceOf(address(fox)),       transferableAmt);
    }

    function custody_and_withdraw(uint256 amt, uint256 custodyAmt, bool isPfdtStakeAsset, IStakeToken stakeToken) public {
        Custodian custodian = new Custodian();

        if (isPfdtStakeAsset) {
            amt        = constrictToRange(amt,        1, 1E9, true);  // $1 - $1b
            custodyAmt = constrictToRange(custodyAmt, 1, amt, true);  // $1 - amt

            mintFundsAndDepositIntoPool(fez, pool1, amt * USD, amt * USD);
            pat.setLockupPeriod(address(pool1), 0);

            amt        *= WAD;
            custodyAmt *= WAD;
        } else {
            // Transfer BPTs to the Farmers i.e Fay and Fez. Although both can use interchangeably but to make code consistent chose to use Fay and Fez. 
            sam.transfer(address(bPool), address(fez), bPool.balanceOf(address(sam)));

            amt        = constrictToRange(amt,        1, bPool.balanceOf(address(fez)), true);  // 1 wei - whole BPT bal
            custodyAmt = constrictToRange(custodyAmt, 1, amt,                           true);  // 1 wei - amt

            // Make StakeLocker public and stake tokens
            pat.openStakeLockerToPublic(   address(stakeLocker1));
            fez.approve(address(bPool),    address(stakeLocker1), amt);
            fez.stakeTo(                   address(stakeLocker1), amt);
            pat.setStakeLockerLockupPeriod(address(stakeLocker1),   0);
        }

        assertEq(stakeToken.custodyAllowance(address(fez), address(custodian)), 0);
        assertEq(stakeToken.totalCustodyAllowance(address(fez)),                0);

        fez.increaseCustodyAllowance(address(custodian), custodyAmt);

        assertEq(stakeToken.custodyAllowance(address(fez), address(custodian)), custodyAmt);
        assertEq(stakeToken.totalCustodyAllowance(address(fez)),                custodyAmt);

        uint256 withdrawAmt = amt - custodyAmt;

        assertEq(stakeToken.balanceOf(address(fez)), amt);

        if (isPfdtStakeAsset) {
            make_withdrawable(fez, pool1);

            assertTrue(!fez.try_withdraw(address(stakeToken), toUsd(withdrawAmt) + 1));
            assertTrue( fez.try_withdraw(address(stakeToken), toUsd(withdrawAmt)));

            assertEq(usdc.balanceOf(address(fez)), toUsd(withdrawAmt));

        } else {
            make_unstakeable(Staker(address(fez)), stakeLocker1);

            assertTrue(!fez.try_unstake(address(stakeToken), withdrawAmt + 1));
            assertTrue( fez.try_unstake(address(stakeToken), withdrawAmt));
        }

        assertEq(stakeToken.balanceOf(address(fez)), custodyAmt);
    }

    function fdt_transferByCustodian(uint256 amt, uint256 custodyAmt, bool isPfdtStakeAsset, IStakeToken stakeToken) public {
        Custodian custodian = new Custodian();  // Custodial contract for FDTs - will start out as liquidity mining but could be broader DeFi eventually

        if (isPfdtStakeAsset) {
            amt        = constrictToRange(amt,        1, 1E9, true);  // $1 - $1b
            custodyAmt = constrictToRange(custodyAmt, 1, amt, true);  // $1 - deposit

            mintFundsAndDepositIntoPool(fay, pool1, amt * USD, amt * USD);

            amt        *= WAD;
            custodyAmt *= WAD;
        } else {
            // Transfer BPTs to the Farmers i.e Fay and Fez. Although both can use interchangeably but to make it code consistent chosses to use Fay anf Fez. 
            sam.transfer(address(bPool), address(fay), bPool.balanceOf(address(sam)));

            amt        = constrictToRange(amt,        1, bPool.balanceOf(address(fay)), true);  // 1 wei - whole BPT bal
            custodyAmt = constrictToRange(custodyAmt, 1, amt,                           true);  // 1 wei - amt

            // Make StakeLocker public and stake tokens
            pat.openStakeLockerToPublic(address(stakeLocker1));
            fay.approve(address(bPool), address(stakeLocker1), amt);
            fay.stakeTo(                address(stakeLocker1), amt);
        }

        fay.increaseCustodyAllowance(address(custodian), custodyAmt);

        assertEq(stakeToken.custodyAllowance(address(fay), address(custodian)), custodyAmt);  // Fay gives custody to custodian
        assertEq(stakeToken.totalCustodyAllowance(address(fay)),                custodyAmt);  // Total custody allowance goes up

        assertTrue(!custodian.try_transferByCustodian(address(stakeToken), address(fay), address(fox),     custodyAmt));  // P/SL:INVALID_RECEIVER
        assertTrue(!custodian.try_transferByCustodian(address(stakeToken), address(fay), address(fay),              0));  // P/SL:INVALID_AMT
        assertTrue(!custodian.try_transferByCustodian(address(stakeToken), address(fay), address(fay), custodyAmt + 1));  // P/SL:INSUF_ALLOWANCE
        assertTrue( custodian.try_transferByCustodian(address(stakeToken), address(fay), address(fay),     custodyAmt));  // Able to transfer custody amount back

        assertEq(stakeToken.custodyAllowance(address(fay), address(custodian)), 0);  // Custodian allowance has been reduced
        assertEq(stakeToken.totalCustodyAllowance(address(fay)),                0);  // Total custody allowance has been reduced, giving Fay access to funds again
    }

    /****************************/
    /*** LP functions testing ***/
    /****************************/
    function stake_test(bool isPfdtStakeToken, uint256 amt, uint256 stakeAmt, IStakeToken stakeToken) public {
        uint256 start = block.timestamp;

        if (isPfdtStakeToken) {
            mintFundsAndDepositIntoPool(fay, pool1, amt * USD, amt * USD);
        } else {
            setUpForStakeLocker(amt, sam, fay);
        }

        checkDepositOrStakeDate(isPfdtStakeToken, start, stakeToken, fay);

        amt *= WAD;

        assertEq(stakeToken.balanceOf(address(fay)), amt);
        assertEq(mplRewards.balanceOf(address(fay)),   0);
        assertEq(mplRewards.totalSupply(),             0);

        hevm.warp(start + 1 days);  // Warp to ensure no effect on depositDates

        assertTrue(!fay.try_stake(stakeAmt * WAD));  // Can't stake before approval

        fay.increaseCustodyAllowance(address(mplRewards), stakeAmt * WAD);

        assertTrue(!fay.try_stake(0));               // Can't stake zero
        assertTrue( fay.try_stake(stakeAmt * WAD));  // Can stake after approval

        assertEq(stakeToken.balanceOf(address(fay)),            amt);  // PoolFDT balance doesn't change
        assertEq(mplRewards.balanceOf(address(fay)), stakeAmt * WAD);
        assertEq(mplRewards.totalSupply(),           stakeAmt * WAD);

        checkDepositOrStakeDate(isPfdtStakeToken, start, stakeToken, fay);
    }

    function withdraw_test(bool isPfdtStakeToken, uint256 amt, uint256 stakeAmt, IStakeToken stakeToken) public {
        uint256 start = block.timestamp;

        if (isPfdtStakeToken) {
            mintFundsAndDepositIntoPool(fay, pool1, amt * USD, amt * USD);
            assertEq(stakeToken.balanceOf(address(fay)), amt * WAD);
        } else {
            setUpForStakeLocker(amt, sam, fay);
        }

        amt      *= WAD;
        stakeAmt *= WAD;

        fay.increaseCustodyAllowance(address(mplRewards), stakeAmt);
        fay.stake(stakeAmt);

        hevm.warp(start + 1 days);  // Warp to ensure no effect on depositDates

        checkDepositOrStakeDate(isPfdtStakeToken, start, stakeToken, fay);

        assertEq(stakeToken.balanceOf(address(fay)),      amt);  // FDT balance doesn't change
        assertEq(mplRewards.balanceOf(address(fay)), stakeAmt);
        assertEq(mplRewards.totalSupply(),           stakeAmt);

        uint256 currentCustodyAllowance = stakeToken.totalCustodyAllowance(address(fay));

        assertTrue(!fay.try_withdraw(0));         // Can't withdraw zero
        assertTrue( fay.try_withdraw(stakeAmt));  // Can withdraw

        assertEq(stakeToken.totalCustodyAllowance(address(fay)), currentCustodyAllowance - stakeAmt);

        checkDepositOrStakeDate(isPfdtStakeToken, start, stakeToken, fay);

        assertEq(stakeToken.balanceOf(address(fay)), amt);
        assertEq(mplRewards.balanceOf(address(fay)),   0);
        assertEq(mplRewards.totalSupply(),             0);
    }

    /************************/
    /** Internal Functions **/
    /************************/

    function setUpForStakeLocker(uint256 amt, Staker staker, Farmer farmer) internal {
        staker.transfer(address(bPool), address(farmer), bPool.balanceOf(address(staker)));

        if (!stakeLocker1.openToPublic()) {
            pat.openStakeLockerToPublic(address(stakeLocker1));
        }

        farmer.approve(address(bPool), address(stakeLocker1), amt * WAD);
        farmer.stakeTo(                address(stakeLocker1), amt * WAD);
    }

    function checkDepositOrStakeDate(bool isPfdtStakeToken, uint256 date, IStakeToken stakeToken, Farmer farmer) internal {
        if (isPfdtStakeToken) {
            assertEq(stakeToken.depositDate(address(farmer)),     date);  // Has not changed
            assertEq(stakeToken.depositDate(address(mplRewards)),    0);  // Has not changed
        } else {
            assertEq(stakeToken.stakeDate(address(farmer)),     date);  // Has not changed
            assertEq(stakeToken.stakeDate(address(mplRewards)),    0);  // Has not changed
        }
    }

}
