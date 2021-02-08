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
        uint256 rewardPerTokenStored, 
        uint256 userRewardPerTokenPaid, 
        uint256 earned, 
        uint256 rewards, 
        uint256 rewardTokenBal
    ) 
        public 
    {
        assertEq(stakingRewards.rewardPerTokenStored(),       rewardPerTokenStored);
        assertEq(stakingRewards.userRewardPerTokenPaid(user), userRewardPerTokenPaid);
        assertEq(stakingRewards.earned(user),                 earned);
        assertEq(stakingRewards.rewards(user),                rewards);
        assertEq(mpl.balanceOf(user),                         rewardTokenBal);
    }

    function test_rewards_single_epoch() public {
        ali.approve(address(stakingRewards), 100 ether);
        ali.stake(10 ether);

        mpl.transfer(address(stakingRewards), 60_000 ether); // 60k MPL per week => 3.12m MPL per year

        stakingRewards.notifyRewardAmount(60_000 ether);

        uint256 rewardRate = stakingRewards.rewardRate();
        uint256 start      = block.timestamp;

        assertRewardsAccounting({
            user:                   address(ali),  // User accounting for
            rewardPerTokenStored:   0,             // Starting state
            userRewardPerTokenPaid: 0,             // Starting state
            earned:                 0,             // Starting state
            rewards:                0,             // Starting state
            rewardTokenBal:         0              // Starting state
        });

        ali.getReward();  // Get reward at time = 0

        assertRewardsAccounting({
            user:                   address(ali),  // User accounting for
            rewardPerTokenStored:   0,             // Starting state (getReward has no effect at time = 0)
            userRewardPerTokenPaid: 0,             // Starting state (getReward has no effect at time = 0)
            earned:                 0,             // Starting state (getReward has no effect at time = 0)
            rewards:                0,             // Starting state (getReward has no effect at time = 0)
            rewardTokenBal:         0              // Starting state (getReward has no effect at time = 0)
        });

        hevm.warp(start + 1 hours);  // Warp to time = 1 hours

        assertRewardsAccounting({
            user:                   address(ali),          // User accounting for
            rewardPerTokenStored:   0,                     // Not updated yet
            userRewardPerTokenPaid: 0,                     // Not updated yet
            earned:                 rewardRate * 1 hours,  // Time-based calculation
            rewards:                0,                     // Not updated yet
            rewardTokenBal:         0                      // Nothing claimed
        });

        ali.getReward();  // Get reward at time = 1 hours

        assertRewardsAccounting({
            user:                   address(ali),                                               // User accounting for
            rewardPerTokenStored:   rewardRate * 1 hours * WAD / stakingRewards.totalSupply(),  // Updated for 100% ownership in pool after 1hr
            userRewardPerTokenPaid: stakingRewards.rewardPerToken(),                            // Updated on updateReward
            earned:                 0,                                                          // Time-based calculation and userRewardPerTokenPaid cancel out
            rewards:                0,                                                          // Updated on updateReward to earned(), then set to zero on getReward
            rewardTokenBal:         rewardRate * 1 hours                                        // Updated on getReward, user has claimed rewards (equal to original earned() amt at this timestamp))
        });

        // withinDiff(dai.balanceOf(address(ali)), 1 ether, REWARDS_TOLERANCE);
        // withinDiff(stakingRewards.earned(address(ali)), 0 ether, REWARDS_TOLERANCE);

        // bob.doStake(10 ether);

        // withinDiff(dai.balanceOf(address(bob)), 0 ether, REWARDS_TOLERANCE);
        // withinDiff(stakingRewards.earned(address(bob)), 0 ether, REWARDS_TOLERANCE);

        // hevm.warp(now + 2 hours);

        // withinDiff(stakingRewards.earned(address(ali)), 1 ether, REWARDS_TOLERANCE);
        // withinDiff(stakingRewards.earned(address(bob)), 1 ether, REWARDS_TOLERANCE);

        // bob.doGetReward();

        // withinDiff(stakingRewards.earned(address(ali)), 1 ether, REWARDS_TOLERANCE);
        // withinDiff(dai.balanceOf(address(bob)), 1 ether, REWARDS_TOLERANCE);
        // withinDiff(stakingRewards.earned(address(bob)), 0 ether, REWARDS_TOLERANCE);

        // vat.mint(address(distributor), rad(27 ether));
        // distributor.drip();

        // assertEq(stakingRewards.rewardRate(), uint256(48 ether) / 1 days, 1);
        // assertEq(stakingRewards.lastUpdateTime(), now);
        // assertEq(stakingRewards.periodFinish(), now + 1 days);

        // withinDiff(stakingRewards.earned(address(ali)), 1 ether, REWARDS_TOLERANCE);
        // withinDiff(stakingRewards.earned(address(bob)), 0 ether, REWARDS_TOLERANCE);

        // hevm.warp(now + 1 hours);

        // withinDiff(dai.balanceOf(address(ali)), 1 ether, REWARDS_TOLERANCE);
        // withinDiff(stakingRewards.earned(address(ali)), 2 ether, REWARDS_TOLERANCE);
        // withinDiff(dai.balanceOf(address(bob)), 1 ether, REWARDS_TOLERANCE);
        // withinDiff(stakingRewards.earned(address(bob)), 1 ether, REWARDS_TOLERANCE);

        // ali.doGetReward();
        // bob.doGetReward();

        // withinDiff(dai.balanceOf(address(ali)), 3 ether, REWARDS_TOLERANCE);
        // withinDiff(dai.balanceOf(address(bob)), 2 ether, REWARDS_TOLERANCE);

        // hevm.warp(now + 7 days);

        // ali.doGetReward();
        // bob.doGetReward();

        // withinDiff(dai.balanceOf(address(ali)), 26 ether, REWARDS_TOLERANCE);
        // withinDiff(dai.balanceOf(address(bob)), 25 ether, REWARDS_TOLERANCE);
    }

}
