pragma solidity >=0.6.11;

import "./TestUtil.sol";

import "../MapleToken.sol";
import "../StakingRewards.sol";

contract Staker {

    StakingRewards public stakingRewards;
    IERC20         public liquidityAsset;

    constructor(StakingRewards _stakingRewards, IERC20 _liquidityAsset) public {
        stakingRewards = _stakingRewards;
        liquidityAsset = _liquidityAsset;
    }

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    function approve(address who, uint256 amt) public {
        liquidityAsset.approve(who, amt);
    }

    function stake(uint256 amt) public {
        stakingRewards.stake(amt);
    }

    function withdraw(uint256 amt) public {
        stakingRewards.withdraw(amt);
    }

    function getReward() public {
        stakingRewards.getReward();
    }

    function exit() public {
        stakingRewards.exit();
    }

    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    function try_stake(uint256 amt) external returns (bool ok) {
        string memory sig = "stake(uint256)";
        (ok,) = address(stakingRewards).call(abi.encodeWithSignature(sig, amt));
    }

    function try_withdraw(uint256 amt) external returns (bool ok) {
        string memory sig = "withdraw(uint256)";
        (ok,) = address(stakingRewards).call(abi.encodeWithSignature(sig, amt));
    }
}

contract StakingRewardsTest is TestUtil {
    address me;

    StakingRewards stakingRewards;
    MapleToken                mpl;
    IERC20         liquidityAsset;  // TODO: Change this name to FDT-related

    Staker ali;
    Staker bob;
    Staker che;

    uint256 constant REWARDS_TOLERANCE = uint256(1 ether) / 1 days;

    function setUp() public {

        me = address(this);

        mpl = new MapleToken("MapleToken", "MPL", USDC);  // TODO: Move all admin functionality to the governor

        liquidityAsset = IERC20(DAI);  // TODO: Change this to Pool FDT (using DAI because of WAD precision)

        stakingRewards = new StakingRewards(address(this), address(mpl), DAI);

        ali = new Staker(stakingRewards, liquidityAsset);
        bob = new Staker(stakingRewards, liquidityAsset);
        che = new Staker(stakingRewards, liquidityAsset);

        mint("DAI", address(ali), 1000 ether);
        mint("DAI", address(bob), 1000 ether);
        mint("DAI", address(che), 1000 ether);
    }

    function test_stake() public {
        assertEq(liquidityAsset.balanceOf(address(ali)), 1000 ether);
        assertEq(stakingRewards.balanceOf(address(ali)),                 0);
        assertEq(stakingRewards.totalSupply(),                           0);

        assertTrue(!ali.try_stake(100 ether));  // Can't stake before approval

        ali.approve(address(stakingRewards), 100 ether);

        assertTrue(!ali.try_stake(0));          // Can't stake zero
        assertTrue( ali.try_stake(100 ether));  // Can stake after approval

        assertEq(liquidityAsset.balanceOf(address(ali)), 900 ether);
        assertEq(stakingRewards.balanceOf(address(ali)),        100 ether);
        assertEq(stakingRewards.totalSupply(),                  100 ether);
    }

    function test_withdraw() public {
        ali.approve(address(stakingRewards), 100 ether);
        ali.stake(100 ether);

        assertEq(liquidityAsset.balanceOf(address(ali)), 900 ether);
        assertEq(stakingRewards.balanceOf(address(ali)),        100 ether);
        assertEq(stakingRewards.totalSupply(),                  100 ether);

        assertTrue(!ali.try_withdraw(0));          // Can't withdraw zero
        assertTrue( ali.try_withdraw(100 ether));  // Can withdraw 

        assertEq(liquidityAsset.balanceOf(address(ali)), 1000 ether);
        assertEq(stakingRewards.balanceOf(address(ali)),                 0);
        assertEq(stakingRewards.totalSupply(),                           0);
    }

    function test_notify_reward_amount() public {
        assertEq(stakingRewards.periodFinish(),              0);
        assertEq(stakingRewards.rewardRate(),                0);
        assertEq(stakingRewards.rewardsDuration(),      7 days);  // Pre set value
        assertEq(stakingRewards.lastUpdateTime(),            0);  
        assertEq(stakingRewards.rewardPerTokenStored(),      0); 

        mpl.transfer(address(stakingRewards), 60_000 ether); // 60k MPL per week => 3.12m MPL per year

        stakingRewards.notifyRewardAmount(60_000 ether);

        assertEq(stakingRewards.rewardRate(),     uint256(60_000 ether) / 7 days);
        assertEq(stakingRewards.lastUpdateTime(),                block.timestamp);
        assertEq(stakingRewards.periodFinish(),         block.timestamp + 7 days);
    }

    function assertRewardsAccounting(
        address user,
        uint256 totalSupply,
        uint256 rewardPerTokenStored, 
        uint256 userRewardPerTokenPaid, 
        uint256 earned, 
        uint256 rewards, 
        uint256 rewardTokenBal
    ) 
        public 
    {
        assertEq(stakingRewards.totalSupply(),                totalSupply);
        assertEq(stakingRewards.rewardPerTokenStored(),       rewardPerTokenStored);
        assertEq(stakingRewards.userRewardPerTokenPaid(user), userRewardPerTokenPaid);
        assertEq(stakingRewards.earned(user),                 earned);
        assertEq(stakingRewards.rewards(user),                rewards);
        assertEq(mpl.balanceOf(user),                         rewardTokenBal);
    }

    function test_rewards_single_epoch() public {
        ali.approve(address(stakingRewards), 100 ether);
        bob.approve(address(stakingRewards), 100 ether);
        ali.stake(10 ether);

        mpl.transfer(address(stakingRewards), 60_000 ether);  // 60k MPL per week => 3.12m MPL per year

        stakingRewards.notifyRewardAmount(60_000 ether);

        uint256 rewardRate = stakingRewards.rewardRate();
        uint256 start      = block.timestamp;

        /*** Ali time = 0 post-stake ***/
        assertRewardsAccounting({
            user:                   address(ali),  // User accounting for
            totalSupply:            10 ether,      // Ali's stake
            rewardPerTokenStored:   0,             // Starting state
            userRewardPerTokenPaid: 0,             // Starting state
            earned:                 0,             // Starting state
            rewards:                0,             // Starting state
            rewardTokenBal:         0              // Starting state
        });

        ali.getReward();  // Get reward at time = 0

        /*** Ali time = (0 days) post-claim ***/
        assertRewardsAccounting({
            user:                   address(ali),  // User accounting for
            totalSupply:            10 ether,      // Ali's stake
            rewardPerTokenStored:   0,             // Starting state (getReward has no effect at time = 0)
            userRewardPerTokenPaid: 0,             // Starting state (getReward has no effect at time = 0)
            earned:                 0,             // Starting state (getReward has no effect at time = 0)
            rewards:                0,             // Starting state (getReward has no effect at time = 0)
            rewardTokenBal:         0              // Starting state (getReward has no effect at time = 0)
        });

        hevm.warp(start + 1 days);  // Warp to time = (1 days) (dTime = 1 days)

        uint256 dTime_1_rpt = rewardRate * 1 days * WAD / 10 ether;  // Reward per token (RPT) that was used before bob entered the pool (accrued over dTime = 1 days)

        /*** Ali time = (1 days) pre-claim ***/
        assertRewardsAccounting({
            user:                   address(ali),                  // User accounting for
            totalSupply:            10 ether,                      // Ali's stake
            rewardPerTokenStored:   0,                             // Not updated yet
            userRewardPerTokenPaid: 0,                             // Not updated yet
            earned:                 dTime_1_rpt * 10 ether / WAD,  // Time-based calculation
            rewards:                0,                             // Not updated yet
            rewardTokenBal:         0                              // Nothing claimed
        });

        ali.getReward();  // Get reward at time = (1 days) 

        /*** Ali time = (1 days) post-claim ***/
        assertRewardsAccounting({
            user:                   address(ali),                 // User accounting for
            totalSupply:            10 ether,                     // Ali's stake
            rewardPerTokenStored:   dTime_1_rpt,                  // Updated on updateReward
            userRewardPerTokenPaid: dTime_1_rpt,                  // Updated on updateReward for 100% ownership in pool after 1hr
            earned:                 0,                            // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                            // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         dTime_1_rpt * 10 ether / WAD  // Updated on getReward, user has claimed rewards (equal to original earned() amt at this timestamp))
        });

        bob.stake(10 ether); // Bob stakes 10 ether, giving him 50% stake in the pool rewards going forward

        /*** Bob time = (1 days) post-stake ***/
        assertRewardsAccounting({
            user:                   address(bob),  // User accounting for
            totalSupply:            20 ether,      // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt,   // Updated on updateReward (value is halved due to totalSupply)
            userRewardPerTokenPaid: dTime_1_rpt,   // Updated on updateReward, prevents bob from claiming past rewards
            earned:                 0,             // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,             // Not updated yet
            rewardTokenBal:         0              // Not updated yet
        });

        hevm.warp(start + 2 days);  // Warp to time = (2 days) (dTime = 1 days)

        uint256 dTime_2_rpt = rewardRate * 1 days * WAD / 20 ether;  // Reward per token (RPT) that was used after  bob entered the pool (accrued over dTime = 1 days, on second day)

        /*** Ali time = (2 days) pre-claim ***/
        assertRewardsAccounting({
            user:                   address(ali),                  // User accounting for
            totalSupply:            20 ether,                      // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt,                   // Not updated yet
            userRewardPerTokenPaid: dTime_1_rpt,                   // Used so Ali can't do multiple claims
            earned:                 dTime_2_rpt * 10 ether / WAD,  // Ali has not claimed any rewards that have accrued during day 2
            rewards:                0,                             // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         dTime_1_rpt * 10 ether / WAD   // From previous claim
        });

        /*** Bob time = (2 days) pre-claim ***/
        assertRewardsAccounting({
            user:                   address(bob),                  // User accounting for
            totalSupply:            20 ether,                      // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt,                   // Not updated yet
            userRewardPerTokenPaid: dTime_1_rpt,                   // Used so Bob can't do claims on past rewards
            earned:                 dTime_2_rpt * 10 ether / WAD,  // Bob has not claimed any rewards that have accrued during day 2
            rewards:                0,                             // Not updated yet
            rewardTokenBal:         0                              // Not updated yet
        });

        bob.stake(20 ether); // Bob stakes another 20 ether, giving him 75% stake in the pool rewards going forward

        /*** Bob time = (2 days) post-stake ***/
        assertRewardsAccounting({
            user:                   address(bob),                  // User accounting for
            totalSupply:            40 ether,                      // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt,     // Updated on stake to snapshot rewardPerToken up to that point
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt,     // Used so Bob can't do claims on past rewards
            earned:                 dTime_2_rpt * 10 ether / WAD,  // Earned updated to reflect all unclaimed earnings pre stake
            rewards:                dTime_2_rpt * 10 ether / WAD,  // Rewards updated to earnings on updateReward
            rewardTokenBal:         0                              // Not updated yet
        });

        hevm.warp(start + 2 days + 1 hours);  // Warp to time = (2 days + 1 hours) (dTime = 1 hours)

        uint256 dTime_3_rpt = rewardRate * 1 hours * WAD / 40 ether;  // Reward per token (RPT) that was used after bob staked more into the pool (accrued over dTime = 1 hours)

        /*** Ali time = (2 days + 1 hours) pre-claim ***/
        assertRewardsAccounting({
            user:                   address(ali),                                  // User accounting for
            totalSupply:            40 ether,                                      // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt,                     // Not updated yet
            userRewardPerTokenPaid: dTime_1_rpt,                                   // Used so Ali can't do multiple claims
            earned:                 (dTime_2_rpt + dTime_3_rpt) * 10 ether / WAD,  // Ali has not claimed any rewards that have accrued during day 2
            rewards:                0,                                             // Not updated yet
            rewardTokenBal:         dTime_1_rpt * 10 ether / WAD                   // From previous claim
        });

        /*** Bob time = (2 days + 1 hours) pre-claim ***/
        assertRewardsAccounting({
            user:                   address(bob),                                             // User accounting for
            totalSupply:            40 ether,                                                 // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt,                                // Not updated yet
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt,                                // Used so Bob can't do claims on past rewards
            earned:                 (dTime_2_rpt * 10 ether + dTime_3_rpt * 30 ether) / WAD,  // Bob's earnings since he entered the pool
            rewards:                dTime_2_rpt * 10 ether / WAD,                             // Rewards updated to reflect all unclaimed earnings pre stake
            rewardTokenBal:         0                                                         // Not updated yet
        });

        bob.getReward();  // Get reward at time = (2 days + 1 hours)

        /*** Bob time = (2 days + 1 hours) post-claim ***/
        assertRewardsAccounting({
            user:                   address(bob),                                            // User accounting for
            totalSupply:            40 ether,                                                // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,                 // Updated on updateReward
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,                 // Used so Bob can't do multiple claims
            earned:                 0,                                                       // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                       // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime_2_rpt * 10 ether + dTime_3_rpt * 30 ether) / WAD  // Updated on getReward, user has claimed rewards (equal to original earned() amt at this timestamp))
        });

        bob.getReward();  // Try double claim

        /*** Bob time = (2 days + 1 hours) post-claim (ASSERT NOTHING CHANGES) ***/
        assertRewardsAccounting({
            user:                   address(bob),                                            // User accounting for
            totalSupply:            40 ether,                                                // Ali + Bob stake (makes rewardPerTokenStored smaller)
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,                 // Updated on updateReward
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,                 // Used so Bob can't do multiple claims
            earned:                 0,                                                       // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                       // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime_2_rpt * 10 ether + dTime_3_rpt * 30 ether) / WAD  // Updated on getReward, user has claimed rewards (equal to original earned() amt at this timestamp))
        });

        ali.withdraw(5 ether);  // Ali withdraws 5 ether at time = (2 days + 1 hours)

        /*** Ali time = (2 days) pre-claim ***/
        assertRewardsAccounting({
            user:                   address(ali),                                  // User accounting for
            totalSupply:            35 ether,                                      // Ali + Bob stake, lower now that Ali withdrew
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,       // Not updated yet
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,       // Used so Ali can't claim past earnings
            earned:                 (dTime_2_rpt + dTime_3_rpt) * 10 ether / WAD,  // Ali has not claimed any rewards that have accrued during dTime2 and dTime3
            rewards:                (dTime_2_rpt + dTime_3_rpt) * 10 ether / WAD,  // Updated on updateReward to earned()
            rewardTokenBal:         dTime_1_rpt * 10 ether / WAD                   // From previous claim
        });

        hevm.warp(start + 3 days + 1 hours);  // Warp to time = (3 days + 1 hours) (dTime = 1 days)

        uint256 dTime_4_rpt = rewardRate * 1 days * WAD / 35 ether;  // Reward per token (RPT) that was used after ali withdrew from the pool (accrued over dTime = 1 days)

        /*** Ali time = (3 days + 1 hours) pre-exit ***/
        assertRewardsAccounting({
            user:                     address(ali),                             // User accounting for
            totalSupply:              35 ether,                                 // Ali + Bob stake 
            rewardPerTokenStored:     dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,  // Not updated yet
            userRewardPerTokenPaid:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,  // Used so Ali can't do multiple claims
            earned:                 ((dTime_2_rpt + dTime_3_rpt) * 10 ether + dTime_4_rpt * 5 ether) / WAD,            // Ali has not claimed any rewards that have accrued during dTime4
            rewards:                 (dTime_2_rpt + dTime_3_rpt) * 10 ether / WAD,                                       // Not updated yet
            rewardTokenBal:           dTime_1_rpt * 10 ether / WAD              // From previous claim
        });

        /*** Bob time = (2 days + 1 hours) pre-exit ***/
        assertRewardsAccounting({
            user:                   address(bob),                                            // User accounting for
            totalSupply:            35 ether,                                                // Ali + Bob stake 
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,                 // Not updated yet
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt + dTime_3_rpt,                 // Used so Bob can't do multiple claims
            earned:                 dTime_4_rpt * 30 ether / WAD,                            // Bob has not claimed any rewards that have accrued during dTime4
            rewards:                0,                                                       // Not updated yet
            rewardTokenBal:         (dTime_2_rpt * 10 ether + dTime_3_rpt * 30 ether) / WAD  // From previous claim
        });

        ali.exit();  // Ali exits 5 ether  at time = (3 days + 1 hours)
        bob.exit();  // Bob exits 20 ether at time = (3 days + 1 hours)

        /*** Ali time = (3 days + 1 hours) post-exit ***/
        assertRewardsAccounting({
            user:                   address(ali),                                                                         // User accounting for
            totalSupply:            0,                                                                                    // Ali + Bob withdrew all stake
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt + dTime_4_rpt,                                // Updated on updateReward
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt + dTime_3_rpt + dTime_4_rpt,                                // Used so Ali can't do multiple claims
            earned:                 0,                                                                                    // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                                                    // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         ((dTime_1_rpt + dTime_2_rpt + dTime_3_rpt) * 10 ether + dTime_4_rpt * 5 ether) / WAD  // Total earnings from pool
        });

        /*** Bob time = (2 days + 1 hours) post-exit ***/
        assertRewardsAccounting({
            user:                   address(bob),                                                            // User accounting for
            totalSupply:            0,                                                                       // Ali + Bob withdrew all stake
            rewardPerTokenStored:   dTime_1_rpt + dTime_2_rpt + dTime_3_rpt + dTime_4_rpt,                   // Updated on updateReward
            userRewardPerTokenPaid: dTime_1_rpt + dTime_2_rpt + dTime_3_rpt + dTime_4_rpt,                   // Used so Bob can't do multiple claims
            earned:                 0,                                                                       // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                                       // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         (dTime_2_rpt * 10 ether + (dTime_3_rpt + dTime_4_rpt) * 30 ether) / WAD  // Total earnings from pool
        });
    }
}
