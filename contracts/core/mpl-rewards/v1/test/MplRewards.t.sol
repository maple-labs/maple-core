// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/ds-test/contracts/test.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "core/custodial-ownership-token/v1/ERC2258.sol";

import "../MplRewards.sol";

import "./accounts/MplRewardsOwner.sol";
import "./accounts/MplRewardsStaker.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract SomeERC2258 is ERC2258 {
    constructor(string memory name, string memory symbol) ERC2258(name, symbol) public { }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MplRewardsTest is DSTest {

    Hevm hevm;

    uint256 constant WAD = 10 ** 18;

    constructor() public {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
    }

    function test_transferOwnership() external {
        MplRewardsOwner account1   = new MplRewardsOwner();
        MplRewardsOwner account2   = new MplRewardsOwner();
        MplRewards rewardsContract = new MplRewards(address(0), address(1), address(account1));
        
        assertEq(rewardsContract.owner(), address(account1));

        assertTrue(!account2.try_mplRewards_transferOwnership(address(rewardsContract), address(account2)));
        assertTrue( account1.try_mplRewards_transferOwnership(address(rewardsContract), address(account2)));

        assertEq(rewardsContract.owner(), address(account2));
        
        assertTrue(!account1.try_mplRewards_transferOwnership(address(rewardsContract), address(account1)));
        assertTrue( account2.try_mplRewards_transferOwnership(address(rewardsContract), address(account1)));

        assertEq(rewardsContract.owner(), address(account1));
    }

    function test_notifyRewardAmount() external {
        uint256 totalRewards = 25_000 * WAD;

        MplRewardsOwner owner      = new MplRewardsOwner();
        MplRewardsOwner notOwner   = new MplRewardsOwner();
        SomeERC2258 rewardsToken   = new SomeERC2258("RWT", "RWT");
        MplRewards rewardsContract = new MplRewards(address(rewardsToken), address(0), address(owner));

        assertEq(rewardsContract.periodFinish(),         0);
        assertEq(rewardsContract.rewardRate(),           0);
        assertEq(rewardsContract.rewardsDuration(),      7 days);
        assertEq(rewardsContract.lastUpdateTime(),       0);
        assertEq(rewardsContract.rewardPerTokenStored(), 0);

        rewardsToken.mint(address(rewardsContract), totalRewards);

        assertTrue(!notOwner.try_mplRewards_notifyRewardAmount(address(rewardsContract), totalRewards));
        assertTrue(    owner.try_mplRewards_notifyRewardAmount(address(rewardsContract), totalRewards));

        assertEq(rewardsContract.rewardRate(),     totalRewards / 7 days);
        assertEq(rewardsContract.lastUpdateTime(), block.timestamp);
        assertEq(rewardsContract.periodFinish(),   block.timestamp + 7 days);
    }

    function test_updatePeriodFinish() external {
        MplRewardsOwner owner      = new MplRewardsOwner();
        MplRewardsOwner notOwner   = new MplRewardsOwner();
        MplRewards rewardsContract = new MplRewards(address(0), address(1), address(owner));

        assertTrue(!notOwner.try_mplRewards_updatePeriodFinish(address(rewardsContract), block.timestamp + 30 days));
        assertTrue(    owner.try_mplRewards_updatePeriodFinish(address(rewardsContract), block.timestamp + 30 days));
    }

    function test_recoverERC20() external {
        MplRewardsOwner owner      = new MplRewardsOwner();
        MplRewardsOwner notOwner   = new MplRewardsOwner();
        SomeERC2258 someToken      = new SomeERC2258("SMT", "SMT");
        MplRewards rewardsContract = new MplRewards(address(0), address(1), address(owner));

        someToken.mint(address(rewardsContract), 1);

        assertEq(someToken.balanceOf(address(rewardsContract)), 1);
        assertEq(rewardsContract.totalSupply(),                 0);

        assertTrue(!notOwner.try_mplRewards_recoverERC20(address(rewardsContract), address(someToken), 1));
        assertTrue(    owner.try_mplRewards_recoverERC20(address(rewardsContract), address(someToken), 1));

        assertEq(someToken.balanceOf(address(rewardsContract)), 0);
        assertEq(rewardsContract.totalSupply(),                 0);
    }

    function test_setRewardsDuration() external {
        MplRewardsOwner owner      = new MplRewardsOwner();
        MplRewardsOwner notOwner   = new MplRewardsOwner();
        SomeERC2258 rewardsToken   = new SomeERC2258("RWT", "RWT");
        MplRewards rewardsContract = new MplRewards(address(rewardsToken), address(0), address(owner));

        rewardsToken.mint(address(rewardsContract), 1);

        owner.mplRewards_notifyRewardAmount(rewardsContract, 1);        
        assertEq(rewardsContract.periodFinish(),    block.timestamp + 7 days);
        assertEq(rewardsContract.rewardsDuration(), 7 days);

        assertTrue(!notOwner.try_mplRewards_setRewardsDuration(address(rewardsContract), 30 days));
        assertTrue(!   owner.try_mplRewards_setRewardsDuration(address(rewardsContract), 30 days));

        hevm.warp(rewardsContract.periodFinish());

        assertTrue(!owner.try_mplRewards_setRewardsDuration(address(rewardsContract), 30 days));

        hevm.warp(rewardsContract.periodFinish() + 1);

        assertTrue(!notOwner.try_mplRewards_setRewardsDuration(address(rewardsContract), 30 days));
        assertTrue(    owner.try_mplRewards_setRewardsDuration(address(rewardsContract), 30 days));

        assertEq(rewardsContract.rewardsDuration(), 30 days);
    }

    function test_setPaused() external {
        MplRewardsOwner owner      = new MplRewardsOwner();
        MplRewardsOwner notOwner   = new MplRewardsOwner();
        MplRewardsStaker staker    = new MplRewardsStaker();
        SomeERC2258 rewardToken    = new SomeERC2258("RWT", "RWT");
        SomeERC2258 stakingToken   = new SomeERC2258("SKT", "SKT");
        MplRewards rewardsContract = new MplRewards(address(rewardToken), address(stakingToken), address(owner));

        assertTrue(!rewardsContract.paused());

        assertTrue(!notOwner.try_mplRewards_setPaused(address(rewardsContract), true));
        assertTrue(    owner.try_mplRewards_setPaused(address(rewardsContract), true));

        assertTrue(rewardsContract.paused());

        assertTrue(!notOwner.try_mplRewards_setPaused(address(rewardsContract), false));
        assertTrue(    owner.try_mplRewards_setPaused(address(rewardsContract), false));

        assertTrue(!rewardsContract.paused());

        stakingToken.mint(address(staker), 2);

        staker.erc2258_increaseCustodyAllowance(stakingToken, address(rewardsContract), 2);
        assertTrue(staker.try_mplRewards_stake(address(rewardsContract), 2));
        assertTrue(staker.try_mplRewards_withdraw(address(rewardsContract), 1));

        owner.mplRewards_setPaused(rewardsContract, true);

        staker.erc2258_increaseCustodyAllowance(stakingToken, address(rewardsContract), 1);
        assertTrue(!staker.try_mplRewards_stake(address(rewardsContract), 1));
        assertTrue(!staker.try_mplRewards_withdraw(address(rewardsContract), 1));
    }

    function test_periodFinishes() external {
        MplRewardsOwner owner      = new MplRewardsOwner();
        SomeERC2258 rewardToken    = new SomeERC2258("RWT", "RWT");
        SomeERC2258 stakingToken   = new SomeERC2258("SKT", "SKT");
        MplRewards rewardsContract = new MplRewards(address(rewardToken), address(stakingToken), address(owner));
        MplRewardsStaker staker    = new MplRewardsStaker();

        uint256 totalRewardsInWad = 25_000 * WAD;
        uint256 rewardsDuration   = 30 days;

        stakingToken.mint(address(staker), 100 * WAD);
        staker.erc2258_increaseCustodyAllowance(stakingToken, address(rewardsContract), 100 * WAD);
        staker.mplRewards_stake(rewardsContract, 100 * WAD);

        rewardToken.mint(address(rewardsContract), totalRewardsInWad);

        owner.mplRewards_setRewardsDuration(rewardsContract, rewardsDuration);
        owner.mplRewards_notifyRewardAmount(rewardsContract, totalRewardsInWad);

        uint256 start = block.timestamp;

        assertEq(rewardsContract.rewardRate(),                    totalRewardsInWad / rewardsDuration);
        assertEq(rewardToken.balanceOf(address(rewardsContract)), totalRewardsInWad);
        assertEq(rewardsContract.periodFinish(),                  start + rewardsDuration);

        /*** Staker time = 0 post-stake ***/
        assertEq(rewardsContract.totalSupply(),                           100 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                  0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(staker)), 0);
        assertEq(rewardsContract.earned(address(staker)),                 0);
        assertEq(rewardsContract.rewards(address(staker)),                0);
        assertEq(rewardToken.balanceOf(address(staker)),                  0);

        // Warp to the end of the period
        hevm.warp(rewardsContract.periodFinish());

        /*** Staker time = 30 days post-stake ***/
        assertEq(rewardsContract.totalSupply(),                           100 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                  0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(staker)), 0);
        assertEq(rewardsContract.earned(address(staker)),                 rewardsContract.rewardRate() * rewardsDuration);
        assertEq(rewardsContract.rewards(address(staker)),                0);
        assertEq(rewardToken.balanceOf(address(staker)),                  0);

        // Warp past the end of the period
        hevm.warp(rewardsContract.periodFinish() + 1 days);

        /*** Staker time = 31 days post-stake, no change expected ***/
        assertEq(rewardsContract.totalSupply(),                           100 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                  0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(staker)), 0);
        assertEq(rewardsContract.earned(address(staker)),                 rewardsContract.rewardRate() * rewardsDuration);
        assertEq(rewardsContract.rewards(address(staker)),                0);
        assertEq(rewardToken.balanceOf(address(staker)),                  0);
    }

    function test_flashWithdraw() external {
        MplRewardsOwner owner      = new MplRewardsOwner();
        SomeERC2258 rewardToken    = new SomeERC2258("RWT", "RWT");
        SomeERC2258 stakingToken   = new SomeERC2258("SKT", "SKT");
        MplRewards rewardsContract = new MplRewards(address(rewardToken), address(stakingToken), address(owner));
        MplRewardsStaker staker    = new MplRewardsStaker();

        uint256 totalRewardsInWad = 25_000 * WAD;
        uint256 rewardsDuration   = 30 days;

        stakingToken.mint(address(staker), 100 * WAD);
        staker.erc2258_increaseCustodyAllowance(stakingToken, address(rewardsContract), 100 * WAD);
        staker.mplRewards_stake(rewardsContract, 100 * WAD);

        rewardToken.mint(address(rewardsContract), totalRewardsInWad);

        owner.mplRewards_setRewardsDuration(rewardsContract, rewardsDuration);
        owner.mplRewards_notifyRewardAmount(rewardsContract, totalRewardsInWad);

        uint256 start = block.timestamp;

        assertEq(rewardsContract.rewardRate(),                    totalRewardsInWad / rewardsDuration);
        assertEq(rewardToken.balanceOf(address(rewardsContract)), totalRewardsInWad);
        assertEq(rewardsContract.periodFinish(),                  start + rewardsDuration);

        /*** Staker time = 0 ***/
        assertEq(rewardsContract.totalSupply(),                           100 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                  0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(staker)), 0);
        assertEq(rewardsContract.earned(address(staker)),                 0);
        assertEq(rewardsContract.rewards(address(staker)),                0);
        assertEq(rewardToken.balanceOf(address(staker)),                  0);

        // Warp to the middle of the period
        hevm.warp(start + (rewardsDuration / 2));

        uint256 rpt_midway = (rewardsContract.rewardRate() * (rewardsDuration / 2)) / 100;

        /*** Staker time = 15 days ***/
        assertEq(rewardsContract.totalSupply(),                           100 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                  0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(staker)), 0);
        assertEq(rewardsContract.earned(address(staker)),                 rpt_midway * 100);
        assertEq(rewardsContract.rewards(address(staker)),                0);
        assertEq(rewardToken.balanceOf(address(staker)),                  0);

        staker.mplRewards_withdraw(rewardsContract, 100 * WAD);

        staker.erc2258_increaseCustodyAllowance(stakingToken, address(rewardsContract), 100 * WAD);
        staker.mplRewards_stake(rewardsContract, 100 * WAD);

        // Warp to the end of the period
        hevm.warp(rewardsContract.periodFinish());

        /*** Staker time = 30 days ***/
        assertEq(rewardsContract.totalSupply(),                           100 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                  rpt_midway);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(staker)), rpt_midway);
        assertEq(rewardsContract.earned(address(staker)),                 rewardsContract.rewardRate() * rewardsDuration);
        assertEq(rewardsContract.rewards(address(staker)),                rpt_midway * 100);
        assertEq(rewardToken.balanceOf(address(staker)),                  0);
    }

    function test_flashExit() external {
        MplRewardsOwner owner      = new MplRewardsOwner();
        SomeERC2258 rewardToken    = new SomeERC2258("RWT", "RWT");
        SomeERC2258 stakingToken   = new SomeERC2258("SKT", "SKT");
        MplRewards rewardsContract = new MplRewards(address(rewardToken), address(stakingToken), address(owner));
        MplRewardsStaker staker    = new MplRewardsStaker();

        uint256 totalRewardsInWad = 25_000 * WAD;
        uint256 rewardsDuration   = 30 days;

        stakingToken.mint(address(staker), 100 * WAD);
        staker.erc2258_increaseCustodyAllowance(stakingToken, address(rewardsContract), 100 * WAD);
        staker.mplRewards_stake(rewardsContract, 100 * WAD);

        rewardToken.mint(address(rewardsContract), totalRewardsInWad);

        owner.mplRewards_setRewardsDuration(rewardsContract, rewardsDuration);
        owner.mplRewards_notifyRewardAmount(rewardsContract, totalRewardsInWad);

        uint256 start = block.timestamp;

        assertEq(rewardsContract.rewardRate(),                    totalRewardsInWad / rewardsDuration);
        assertEq(rewardToken.balanceOf(address(rewardsContract)), totalRewardsInWad);
        assertEq(rewardsContract.periodFinish(),                  start + rewardsDuration);

        /*** Staker time = 0 ***/
        assertEq(rewardsContract.totalSupply(),                           100 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                  0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(staker)), 0);
        assertEq(rewardsContract.earned(address(staker)),                 0);
        assertEq(rewardsContract.rewards(address(staker)),                0);
        assertEq(rewardToken.balanceOf(address(staker)),                  0);

        // Warp to the middle of the period
        hevm.warp(start + (rewardsDuration / 2));

        uint256 rpt_midway = (rewardsContract.rewardRate() * (rewardsDuration / 2)) / 100;

        /*** Staker time = 15 days ***/
        assertEq(rewardsContract.totalSupply(),                           100 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                  0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(staker)), 0);
        assertEq(rewardsContract.earned(address(staker)),                 rpt_midway * 100);
        assertEq(rewardsContract.rewards(address(staker)),                0);
        assertEq(rewardToken.balanceOf(address(staker)),                  0);

        staker.mplRewards_exit(rewardsContract);

        staker.erc2258_increaseCustodyAllowance(stakingToken, address(rewardsContract), 100 * WAD);
        staker.mplRewards_stake(rewardsContract, 100 * WAD);

        // Warp to the end of the period
        hevm.warp(rewardsContract.periodFinish());

        /*** Staker time = 30 days ***/
        assertEq(rewardsContract.totalSupply(),                           100 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                  rpt_midway);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(staker)), rpt_midway);
        assertEq(rewardsContract.earned(address(staker)),                 rewardsContract.rewardRate() * rewardsDuration - rpt_midway * 100);
        assertEq(rewardsContract.rewards(address(staker)),                0);
        assertEq(rewardToken.balanceOf(address(staker)),                  rpt_midway * 100);
    }

    function test_rewardsSingleEpoch() external {
        MplRewardsOwner owner      = new MplRewardsOwner();
        SomeERC2258 rewardToken    = new SomeERC2258("RWT", "RWT");
        SomeERC2258 stakingToken   = new SomeERC2258("SKT", "SKT");
        MplRewards rewardsContract = new MplRewards(address(rewardToken), address(stakingToken), address(owner));

        uint256 totalRewardsInWad = 25_000 * WAD;
        uint256 rewardsDuration   = 30 days;

        MplRewardsStaker[] memory stakers = new MplRewardsStaker[](2);
        stakers[0]                        = new MplRewardsStaker();
        stakers[1]                        = new MplRewardsStaker();

        for (uint256 i; i < stakers.length; ++i) {
            stakingToken.mint(address(stakers[i]), 100 * WAD);
            stakers[i].erc2258_increaseCustodyAllowance(stakingToken, address(rewardsContract), 100 * WAD);
        }

        stakers[0].mplRewards_stake(rewardsContract, 10 * WAD);

        rewardToken.mint(address(rewardsContract), totalRewardsInWad);

        owner.mplRewards_setRewardsDuration(rewardsContract, rewardsDuration);
        owner.mplRewards_notifyRewardAmount(rewardsContract, totalRewardsInWad);

        uint256 start = block.timestamp;

        assertEq(rewardsContract.rewardRate(),                    totalRewardsInWad / rewardsDuration);
        assertEq(rewardToken.balanceOf(address(rewardsContract)), totalRewardsInWad);
        assertEq(rewardsContract.periodFinish(),                  start + rewardsDuration);

        /*** Staker-0 time = 0 post-stake ***/
        assertEq(rewardsContract.totalSupply(),                               10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), 0);
        assertEq(rewardsContract.earned(address(stakers[0])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  0);

        // getReward has no effect at time = 0
        stakers[0].mplRewards_getReward(rewardsContract);

        /*** Staker-0 time = (0 days) post-claim ***/
        assertEq(rewardsContract.totalSupply(),                               10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), 0);
        assertEq(rewardsContract.earned(address(stakers[0])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  0);

        // Warp to time = (1 days) (dTime = 1 days)
        hevm.warp(start + 1 days);

        // Reward per token (RPT) that was used before Staker-1 entered the pool (accrued over dTime = 1 days)
        uint256 dTime1_rpt = (rewardsContract.rewardRate() * 1 days) / 10;

        /*** Staker-0 time = (1 days) pre-claim ***/
        assertEq(rewardsContract.totalSupply(),                               10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), 0);
        assertEq(rewardsContract.earned(address(stakers[0])),                 dTime1_rpt * 10);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  0);

        // Get reward at time = (1 days)
        stakers[0].mplRewards_getReward(rewardsContract);

        /*** Staker-0 time = (1 days) post-claim ***/
        assertEq(rewardsContract.totalSupply(),                               10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(stakers[0])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  dTime1_rpt * 10);

        // Staker-1 stakes 10 FDTs, giving him 50% stake in the pool rewards going forward
        stakers[1].mplRewards_stake(rewardsContract, 10 * WAD);

        /*** Staker-1 time = (1 days) post-stake ***/
        assertEq(rewardsContract.totalSupply(),                               2 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[1])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(stakers[1])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[1])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[1])),                  0);

        // Warp to time = (2 days) (dTime = 1 days)
        hevm.warp(start + 2 days);

        // Reward per token (RPT) that was used after Staker-1 entered the pool (accrued over dTime = 1 days, on second day), smaller since supply increased
        uint256 dTime2_rpt = (rewardsContract.rewardRate() * 1 days) / (2 * 10);

        /*** Staker-0 time = (2 days) pre-claim ***/
        assertEq(rewardsContract.totalSupply(),                               2 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(stakers[0])),                 dTime2_rpt * 10);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  dTime1_rpt * 10);

        /*** Staker-1 time = (2 days) pre-claim ***/
        assertEq(rewardsContract.totalSupply(),                               2 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[1])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(stakers[1])),                 dTime2_rpt * 10);
        assertEq(rewardsContract.rewards(address(stakers[1])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[1])),                  0);

        // Staker-1 stakes another 2 * 10 FDTs, giving him 75% stake in the pool rewards going forward
        stakers[1].mplRewards_stake(rewardsContract, 2 * 10 * WAD);

        /*** Staker-1 time = (2 days) post-stake ***/
        assertEq(rewardsContract.totalSupply(),                               4 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[1])), dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.earned(address(stakers[1])),                 dTime2_rpt * 10);
        assertEq(rewardsContract.rewards(address(stakers[1])),                dTime2_rpt * 10);
        assertEq(rewardToken.balanceOf(address(stakers[1])),                  0);

        // Warp to time = (2 days + 1 hours) (dTime = 1 hours)
        hevm.warp(start + 2 days + 1 hours);

        // Reward per token (RPT) that was used after Staker-1 staked more into the pool (accrued over dTime = 1 hours)
        uint256 dTime3_rpt = (rewardsContract.rewardRate() * 1 hours) / (4 * 10);

        /*** Staker-0 time = (2 days + 1 hours) pre-claim ***/
        assertEq(rewardsContract.totalSupply(),                               4 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(stakers[0])),                 (dTime2_rpt + dTime3_rpt) * 10);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  dTime1_rpt * 10);

        /*** Staker-1 time = (2 days + 1 hours) pre-claim ***/
        assertEq(rewardsContract.totalSupply(),                               4 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[1])), dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.earned(address(stakers[1])),                 dTime2_rpt * 10 + dTime3_rpt * 30);
        assertEq(rewardsContract.rewards(address(stakers[1])),                dTime2_rpt * 10);
        assertEq(rewardToken.balanceOf(address(stakers[1])),                  0);

        // Get reward at time = (2 days + 1 hours)
        stakers[1].mplRewards_getReward(rewardsContract);

        /*** Staker-1 time = (2 days + 1 hours) post-claim ***/
        assertEq(rewardsContract.totalSupply(),                               4 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[1])), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.earned(address(stakers[1])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[1])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[1])),                  dTime2_rpt * 10 + dTime3_rpt * 30);
        
        // Try double claim
        stakers[1].mplRewards_getReward(rewardsContract);

        /*** Staker-1 time = (2 days + 1 hours) post-claim (ASSERT NOTHING CHANGES) ***/
        assertEq(rewardsContract.totalSupply(),                               4 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[1])), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.earned(address(stakers[1])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[1])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[1])),                  dTime2_rpt * 10 + dTime3_rpt * 30);

        // Staker-0 withdraws 5 * WAD at time = (2 days + 1 hours)
        stakers[0].mplRewards_withdraw(rewardsContract, 5 * WAD);

        /*** Staker-0 time = (2 days + 1 hours) pre-claim ***/
        assertEq(rewardsContract.totalSupply(),                               35 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.earned(address(stakers[0])),                 (dTime2_rpt + dTime3_rpt) * 10);
        assertEq(rewardsContract.rewards(address(stakers[0])),                (dTime2_rpt + dTime3_rpt) * 10);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  dTime1_rpt * 10);

        // Warp to time = (3 days + 1 hours) (dTime = 1 days)
        hevm.warp(start + 3 days + 1 hours);

        // Reward per token (RPT) that was used after Staker-0 withdrew from the pool (accrued over dTime = 1 days)
        uint256 dTime4_rpt = (rewardsContract.rewardRate() * 1 days) / 35;

        /*** Staker-0 time = (3 days + 1 hours) pre-exit ***/
        assertEq(rewardsContract.totalSupply(),                               35 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.earned(address(stakers[0])),                 (dTime2_rpt + dTime3_rpt) * 10 + dTime4_rpt * 5);
        assertEq(rewardsContract.rewards(address(stakers[0])),                (dTime2_rpt + dTime3_rpt) * 10);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  dTime1_rpt * 10);

        /*** Staker-1 time = (2 days + 1 hours) pre-exit ***/
        assertEq(rewardsContract.totalSupply(),                               35 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[1])), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.earned(address(stakers[1])),                 dTime4_rpt * 30);
        assertEq(rewardsContract.rewards(address(stakers[1])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[1])),                  dTime2_rpt * 10 + dTime3_rpt * 30);

        // Staker-0 exits at time = (3 days + 1 hours)
        stakers[0].mplRewards_exit(rewardsContract);

        // Staker-1 exits at time = (3 days + 1 hours)
        stakers[1].mplRewards_exit(rewardsContract);

        /*** Staker-0 time = (3 days + 1 hours) post-exit ***/
        assertEq(rewardsContract.totalSupply(), 0);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt);
        assertEq(rewardsContract.earned(address(stakers[0])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  ((dTime1_rpt + dTime2_rpt + dTime3_rpt) * 10 ether + dTime4_rpt * 5 ether) / WAD);

        /*** Staker-1 time = (2 days + 1 hours) post-exit ***/
        assertEq(rewardsContract.totalSupply(),                               0);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[1])), dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt);
        assertEq(rewardsContract.earned(address(stakers[1])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[1])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[1])),                  (dTime2_rpt * 10 ether + (dTime3_rpt + dTime4_rpt) * 30 ether) / WAD);
    }

    function test_rewardsMultiEpoch() external {
        MplRewardsOwner owner      = new MplRewardsOwner();
        SomeERC2258 rewardToken    = new SomeERC2258("RWT", "RWT");
        SomeERC2258 stakingToken   = new SomeERC2258("SKT", "SKT");
        MplRewards rewardsContract = new MplRewards(address(rewardToken), address(stakingToken), address(owner));

        uint256 totalRewardsInWad = 25_000 * WAD;
        uint256 rewardsDuration   = 30 days;

        MplRewardsStaker[] memory stakers = new MplRewardsStaker[](2);
        stakers[0]                        = new MplRewardsStaker();
        stakers[1]                        = new MplRewardsStaker();

        for (uint256 i; i < stakers.length; ++i) {
            stakingToken.mint(address(stakers[i]), 100 * WAD);
            stakers[i].erc2258_increaseCustodyAllowance(stakingToken, address(rewardsContract), 100 * WAD);
        }

        stakers[0].mplRewards_stake(rewardsContract, 10 * WAD);
        stakers[1].mplRewards_stake(rewardsContract, 30 * WAD);

        rewardToken.mint(address(rewardsContract), totalRewardsInWad);

        owner.mplRewards_setRewardsDuration(rewardsContract, rewardsDuration);
        owner.mplRewards_notifyRewardAmount(rewardsContract, totalRewardsInWad);
        
        uint256 start = block.timestamp;

        assertEq(rewardsContract.rewardRate(),                    totalRewardsInWad / rewardsDuration);
        assertEq(rewardToken.balanceOf(address(rewardsContract)), totalRewardsInWad);
        assertEq(rewardsContract.periodFinish(),                  start + rewardsDuration);

        // Warp to the end of the epoch
        hevm.warp(rewardsContract.periodFinish());

        /********************/
        /*** EPOCH 1 ENDS ***/
        /********************/

        // Reward per token (RPT) for all of epoch 1
        uint256 dTime1_rpt = (rewardsContract.rewardRate() * rewardsDuration) / 40;

        /*** Staker-0 time = (30 days) pre-claim ***/
        assertEq(rewardsContract.totalSupply(),                               40 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), 0);
        assertEq(rewardsContract.earned(address(stakers[0])),                 dTime1_rpt * 10);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  0);

        /*** Staker-1 time = (30 days) pre-claim ***/
        assertEq(rewardsContract.totalSupply(),                               40 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[1])), 0);
        assertEq(rewardsContract.earned(address(stakers[1])),                 dTime1_rpt * 30);
        assertEq(rewardsContract.rewards(address(stakers[1])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[1])),                  0);

        // Staker-0 claims all rewards for epoch 1
        stakers[0].mplRewards_getReward(rewardsContract);

        /*** Staker-0 time = (30 days) post-claim ***/
        assertEq(rewardsContract.totalSupply(),                               40 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(stakers[0])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  dTime1_rpt * 10);

        assertEq(rewardsContract.lastUpdateTime(),           start + rewardsDuration);
        assertEq(rewardsContract.lastTimeRewardApplicable(), start + rewardsDuration);

        // Warp another day after the epoch is finished
        hevm.warp(rewardsContract.periodFinish() + 1 days);

        assertEq(rewardsContract.lastUpdateTime(),           start + rewardsDuration);
        assertEq(rewardsContract.lastTimeRewardApplicable(), start + rewardsDuration);

        /*** Staker-0 time = (31 days) pre-claim (ASSERT NOTHING CHANGES DUE TO EPOCH BEING OVER) ***/
        assertEq(rewardsContract.totalSupply(),                               40 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(stakers[0])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  dTime1_rpt * 10);

        // Staker-0 claims rewards, but epoch 1 is finished
        stakers[0].mplRewards_getReward(rewardsContract);
        
        /*** Staker-0 time = (31 days) post-claim (ASSERT NOTHING CHANGES DUE TO EPOCH BEING OVER) ***/
        assertEq(rewardsContract.totalSupply(),                               40 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(stakers[0])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  dTime1_rpt * 10);

        /**********************/
        /*** EPOCH 2 STARTS ***/
        /**********************/

        // Staker-1's claimable rewards are still in the contract
        assertEq(rewardToken.balanceOf(address(rewardsContract)), (25_000 * WAD) - (dTime1_rpt * 10));

        totalRewardsInWad = 40_000 * WAD;
        rewardsDuration   = 15 days;

        rewardToken.mint(address(rewardsContract), totalRewardsInWad);

        owner.mplRewards_setRewardsDuration(rewardsContract, rewardsDuration);
        owner.mplRewards_notifyRewardAmount(rewardsContract, totalRewardsInWad);

        assertEq(rewardsContract.rewardRate(), totalRewardsInWad / rewardsDuration);

        // Warp to 1 day into the second epoch
        hevm.warp(block.timestamp + 1 days);

        // Reward per token (RPT) for one day of epoch 2 (uses the new rewardRate)
        uint256 dTime2_rpt = (rewardsContract.rewardRate() * 1 days) / 40;

        /*** Staker-0 time = (1 days into epoch 2) pre-exit ***/
        assertEq(rewardsContract.totalSupply(),                               40 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(stakers[0])),                 dTime2_rpt * 10);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  dTime1_rpt * 10);

        /*** Staker-1 time = (1 days into epoch 2) pre-exit ***/
        assertEq(rewardsContract.totalSupply(),                               40 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[1])), 0);
        assertEq(rewardsContract.earned(address(stakers[1])),                 (dTime1_rpt + dTime2_rpt) * 30);
        assertEq(rewardsContract.rewards(address(stakers[1])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[1])),                  0);

        // Staker-0 and Staker-1 exit at time = (1 days into epoch 2)
        stakers[0].mplRewards_exit(rewardsContract);
        stakers[1].mplRewards_exit(rewardsContract);
        
        /*** Staker-0 time = (1 days into epoch 2) post-exit ***/
        assertEq(rewardsContract.totalSupply(),                               0);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[0])), dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.earned(address(stakers[0])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[0])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[0])),                  (dTime1_rpt + dTime2_rpt) * 10);
        
        /*** Staker-1 time = (1 days into epoch 2) post-exit ***/
        assertEq(rewardsContract.totalSupply(),                               0);
        assertEq(rewardsContract.rewardPerTokenStored(),                      dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(stakers[1])), dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.earned(address(stakers[1])),                 0);
        assertEq(rewardsContract.rewards(address(stakers[1])),                0);
        assertEq(rewardToken.balanceOf(address(stakers[1])),                  (dTime1_rpt + dTime2_rpt) * 30);
    }

}
