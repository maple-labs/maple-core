// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./helper/Rewards.sol";

contract StakeLockerCustodialTest is CustodialTestHelper {

    using SafeMath for uint256;

    function setUp() public {
        setupFarmingEcosystem();
        setUpMplRewards(address(stakeLocker1));
        createFarmers();
        addBPoolInTokenSlots();

    }

    function test_custody_and_transfer(uint256 stakeAmt, uint256 custodyAmt1, uint256 custodyAmt2) public {
        custody_and_transfer(stakeAmt, custodyAmt1, custodyAmt2, false, IStakeToken(address(stakeLocker1)));
    }

    function test_custody_and_unstake(uint256 stakeAmt, uint256 custodyAmt) public {
        custody_and_withdraw(stakeAmt, custodyAmt, false, IStakeToken(address(stakeLocker1)));
    }

    function test_transferByCustodian(uint256 stakeAmt, uint256 custodyAmt) public {
        fdt_transferByCustodian(stakeAmt, custodyAmt, false, IStakeToken(address(stakeLocker1)));
    }

    function test_stake() public {
        mint("BPT", address(sam), 1000 * WAD);
        stake_test(false, 1000, 100, IStakeToken(address(stakeLocker1)));
    }

    function test_withdraw() public {
        mint("BPT", address(sam), 1000 * WAD);
        withdraw_test(false, 1000, 100, IStakeToken(address(stakeLocker1)));
    }

    function test_rewards_single_epoch() public {
        uint256 totalRewardsInWad = 25_000 * WAD;
        uint256 rewardsDuration = 30 days;

        Farmer[] memory farmers = new Farmer[](2);
        farmers[0] = fay;
        farmers[1] = fez;

        Staker[] memory stakers = new Staker[](2);
        stakers[0] = sam;
        stakers[1] = sid;

        prepareStakers(stakers, farmers, mplRewards, 100);

        farmers[0].stake(10 * WAD);

        uint256 start = startRewards(mpl, mplRewards, gov, totalRewardsInWad, rewardsDuration);

        assertEq(mplRewards.rewardRate(), uint256(totalRewardsInWad) / rewardsDuration);
        assertEq(mpl.balanceOf(address(mplRewards)), totalRewardsInWad);

        rewards_single_epoch_test(start, farmers, mplRewards);
    }

    function test_stake_rewards_multi_epoch() public {
        rewards_multi_epoch_test(false, 100, IStakeToken(address(stakeLocker1)));
    }
}
