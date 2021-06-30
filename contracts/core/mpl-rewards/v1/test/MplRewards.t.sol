// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "lib/ds-test/contracts/test.sol";

import "core/custodial-ownership-token/v1/ERC2258.sol";

import "../MplRewards.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract SomeAccount {
    function tryCall(address someContract, bytes memory someData) external returns (bool ok, bytes memory returnData) {
        (ok, returnData) = someContract.call(someData);
    }

    function call(address someContract, bytes memory someData) external returns (bytes memory returnData) {
        bool ok;
        (ok, returnData) = someContract.call(someData);
        require(ok);
    }
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
        SomeAccount account1 = new SomeAccount();
        SomeAccount account2 = new SomeAccount();
        MplRewards rewardsContract = new MplRewards(address(0), address(1), address(account1));
        
        assertEq(rewardsContract.owner(), address(account1));

        {
            (bool success,) = account2.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("transferOwnership(address)", address(account1))
            );
            assertTrue(!success);
        }

        {
            (bool success,) = account1.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("transferOwnership(address)", address(account2))
            );
            assertTrue(success);
            assertEq(rewardsContract.owner(), address(account2));
        }
        
        {
            (bool success,) = account1.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("transferOwnership(address)", address(account2))
            );
            assertTrue(!success);
        }

        {
            (bool success,) = account2.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("transferOwnership(address)", address(account1))
            );
            assertTrue(success);
            assertEq(rewardsContract.owner(), address(account1));
        }
    }

    function test_notifyRewardAmount() external {
        uint256 totalRewards = 25_000 * WAD;

        SomeAccount owner = new SomeAccount();
        SomeAccount notOwner = new SomeAccount();
        SomeERC2258 rewardsToken = new SomeERC2258("RWT", "RWT");
        MplRewards rewardsContract = new MplRewards(address(rewardsToken), address(0), address(owner));

        assertEq(rewardsContract.periodFinish(),              0);
        assertEq(rewardsContract.rewardRate(),                0);
        assertEq(rewardsContract.rewardsDuration(),      7 days);  // Pre set value
        assertEq(rewardsContract.lastUpdateTime(),            0);
        assertEq(rewardsContract.rewardPerTokenStored(),      0);

        rewardsToken.mint(address(rewardsContract), totalRewards);

        {
            (bool success,) = notOwner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("notifyRewardAmount(uint256)", totalRewards)
            );
            assertTrue(!success);
        }

        {
            (bool success,) = owner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("notifyRewardAmount(uint256)", totalRewards)
            );
            assertTrue(success);
        }

        assertEq(rewardsContract.rewardRate(),        totalRewards / 7 days);
        assertEq(rewardsContract.lastUpdateTime(),          block.timestamp);
        assertEq(rewardsContract.periodFinish(),   block.timestamp + 7 days);
    }

    function test_updatePeriodFinish() external {
        SomeAccount owner = new SomeAccount();
        SomeAccount notOwner = new SomeAccount();
        MplRewards rewardsContract = new MplRewards(address(0), address(1), address(owner));

        {
            (bool success,) = notOwner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("updatePeriodFinish(uint256)", block.timestamp + 30 days)
            );
            assertTrue(!success);
        }

        {
            (bool success,) = owner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("updatePeriodFinish(uint256)", block.timestamp + 30 days)
            );
            assertTrue(success);
        }
    }

    function test_recoverERC20() external {
        SomeAccount owner = new SomeAccount();
        SomeAccount notOwner = new SomeAccount();
        SomeERC2258 someToken = new SomeERC2258("SMT", "SMT");
        MplRewards rewardsContract = new MplRewards(address(0), address(1), address(owner));

        someToken.mint(address(rewardsContract), 1);
        assertEq(someToken.balanceOf(address(rewardsContract)), 1);
        assertEq(rewardsContract.totalSupply(), 0);

        {
            (bool success,) = notOwner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("recoverERC20(address,uint256)", address(someToken), 1)
            );
            assertTrue(!success);
        }

        {
            (bool success,) = owner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("recoverERC20(address,uint256)", address(someToken), 1)
            );
            assertTrue(success);
            assertEq(someToken.balanceOf(address(rewardsContract)), 0);
        }
        
        assertEq(rewardsContract.totalSupply(), 0);
    }

    function test_setRewardsDuration() external {
        SomeAccount owner = new SomeAccount();
        SomeAccount notOwner = new SomeAccount();
        SomeERC2258 rewardsToken = new SomeERC2258("RWT", "RWT");
        MplRewards rewardsContract = new MplRewards(address(rewardsToken), address(0), address(owner));

        rewardsToken.mint(address(rewardsContract), 1);

        owner.call(
            address(rewardsContract),
            abi.encodeWithSignature("notifyRewardAmount(uint256)", 1)
        );
        
        assertEq(rewardsContract.periodFinish(),    block.timestamp + 7 days);
        assertEq(rewardsContract.rewardsDuration(),                   7 days);

        {
            (bool success,) = notOwner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("setRewardsDuration(uint256)", 30 days)
            );
            assertTrue(!success);
        }

        {
            (bool success,) = owner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("setRewardsDuration(uint256)", 30 days)
            );
            assertTrue(!success);
        }

        hevm.warp(rewardsContract.periodFinish());

        {
            (bool success,) = owner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("setRewardsDuration(uint256)", 30 days)
            );
            assertTrue(!success);
        }

        hevm.warp(rewardsContract.periodFinish() + 1);

        {
            (bool success,) = owner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("setRewardsDuration(uint256)", 30 days)
            );
            assertTrue(success);
        }

        assertEq(rewardsContract.rewardsDuration(), 30 days);
    }

    function test_setPaused() external {
        SomeAccount owner = new SomeAccount();
        SomeAccount notOwner = new SomeAccount();
        SomeAccount account1 = new SomeAccount();
        SomeERC2258 rewardToken = new SomeERC2258("RWT", "RWT");
        SomeERC2258 stakingToken = new SomeERC2258("SKT", "SKT");
        MplRewards rewardsContract = new MplRewards(address(rewardToken), address(stakingToken), address(owner));

        assertTrue(!rewardsContract.paused());

        {
            (bool success,) = notOwner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("setPaused(bool)", true)
            );
            assertTrue(!success);
        }

        {
            (bool success,) = owner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("setPaused(bool)", true)
            );
            assertTrue(success);
            assertTrue(rewardsContract.paused());
        }

        {
            (bool success,) = owner.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("setPaused(bool)", false)
            );
            assertTrue(success);
            assertTrue(!rewardsContract.paused());
        }

        stakingToken.mint(address(account1), 2);

        {
            account1.call(
                address(stakingToken),
                abi.encodeWithSignature("increaseCustodyAllowance(address,uint256)", address(rewardsContract), 2)
            );
            (bool success,) = account1.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("stake(uint256)", 2)
            );
            assertTrue(success);
        }

        {
            (bool success,) = account1.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("withdraw(uint256)", 1)
            );
            assertTrue(success);
        }

        {
            owner.call(
                address(rewardsContract),
                abi.encodeWithSignature("setPaused(bool)", true)
            );
        }

        {
            account1.call(
                address(stakingToken),
                abi.encodeWithSignature("increaseCustodyAllowance(address,uint256)", address(rewardsContract), 1)
            );
            (bool success,) = account1.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("stake(uint256)", 1)
            );
            assertTrue(!success);
        }

        {
            (bool success,) = account1.tryCall(
                address(rewardsContract),
                abi.encodeWithSignature("withdraw(uint256)", 1)
            );
            assertTrue(!success);
        }
    }

    function test_rewardsSingleEpoch() external {
        SomeAccount owner = new SomeAccount();
        SomeERC2258 rewardToken = new SomeERC2258("RWT", "RWT");
        SomeERC2258 stakingToken = new SomeERC2258("SKT", "SKT");
        MplRewards rewardsContract = new MplRewards(address(rewardToken), address(stakingToken), address(owner));

        uint256 totalRewardsInWad = 25_000 * WAD;
        uint256 rewardsDuration = 30 days;

        SomeAccount[] memory farmers = new SomeAccount[](2);
        farmers[0] = new SomeAccount();
        farmers[1] = new SomeAccount();

        for (uint256 i; i < farmers.length; ++i) {
            stakingToken.mint(address(farmers[i]), 100 * WAD);
            farmers[i].call(
                address(stakingToken),
                abi.encodeWithSignature("increaseCustodyAllowance(address,uint256)", address(rewardsContract), 100 * WAD)
            );
        }

        farmers[0].call(
            address(rewardsContract),
            abi.encodeWithSignature("stake(uint256)", 10 * WAD)
        );

        rewardToken.mint(address(rewardsContract), totalRewardsInWad);

        owner.call(
            address(rewardsContract),
            abi.encodeWithSignature("setRewardsDuration(uint256)", rewardsDuration)
        );
        owner.call(
            address(rewardsContract),
            abi.encodeWithSignature("notifyRewardAmount(uint256)", totalRewardsInWad)
        );
        
        uint256 start = block.timestamp;

        assertEq(rewardsContract.rewardRate(), uint256(totalRewardsInWad) / rewardsDuration);
        assertEq(rewardToken.balanceOf(address(rewardsContract)), totalRewardsInWad);

        /*** Farmer-0 time = 0 post-stake ***/
        assertEq(rewardsContract.totalSupply(), 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), 0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[0])), 0);
        assertEq(rewardsContract.earned(address(farmers[0])), 0);
        assertEq(rewardsContract.rewards(address(farmers[0])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[0])), 0);

        // getReward has no effect at time = 0
        farmers[0].call(
            address(rewardsContract),
            abi.encodeWithSignature("getReward()")
        );

        /*** Farmer-0 time = (0 days) post-claim ***/
        assertEq(rewardsContract.totalSupply(), 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), 0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[0])), 0);
        assertEq(rewardsContract.earned(address(farmers[0])), 0);
        assertEq(rewardsContract.rewards(address(farmers[0])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[0])), 0);

        // Warp to time = (1 days) (dTime = 1 days)
        hevm.warp(start + 1 days);

        // Reward per token (RPT) that was used before Farmer-1 entered the pool (accrued over dTime = 1 days)
        uint256 dTime1_rpt = (rewardsContract.rewardRate() * 1 days) / 10;

        /*** Farmer-0 time = (1 days) pre-claim ***/
        assertEq(rewardsContract.totalSupply(), 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), 0);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[0])), 0);
        assertEq(rewardsContract.earned(address(farmers[0])), dTime1_rpt * 10);
        assertEq(rewardsContract.rewards(address(farmers[0])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[0])), 0);

        // Get reward at time = (1 days)
        farmers[0].call(
            address(rewardsContract),
            abi.encodeWithSignature("getReward()")
        );

        /*** Farmer-0 time = (1 days) post-claim ***/
        assertEq(rewardsContract.totalSupply(), 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[0])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(farmers[0])), 0);
        assertEq(rewardsContract.rewards(address(farmers[0])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[0])), dTime1_rpt * 10);

        // Farmer-1 stakes 10 FDTs, giving him 50% stake in the pool rewards going forward
        farmers[1].call(
            address(rewardsContract),
            abi.encodeWithSignature("stake(uint256)", 10 * WAD)
        );

        /*** Farmer-1 time = (1 days) post-stake ***/
        assertEq(rewardsContract.totalSupply(), 2 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[1])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(farmers[1])), 0);
        assertEq(rewardsContract.rewards(address(farmers[1])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[1])), 0);

        // Warp to time = (2 days) (dTime = 1 days)
        hevm.warp(start + 2 days);

        // Reward per token (RPT) that was used after Farmer-1 entered the pool (accrued over dTime = 1 days, on second day), smaller since supply increased
        uint256 dTime2_rpt = (rewardsContract.rewardRate() * 1 days) / (2 * 10);

        /*** Farmer-0 time = (2 days) pre-claim ***/
        assertEq(rewardsContract.totalSupply(), 2 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[0])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(farmers[0])), dTime2_rpt * 10);
        assertEq(rewardsContract.rewards(address(farmers[0])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[0])), dTime1_rpt * 10);

        /*** Farmer-1 time = (2 days) pre-claim ***/
        assertEq(rewardsContract.totalSupply(), 2 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[1])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(farmers[1])), dTime2_rpt * 10);
        assertEq(rewardsContract.rewards(address(farmers[1])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[1])), 0);

        // Farmer-1 stakes another 2 * 10 FDTs, giving him 75% stake in the pool rewards going forward
        farmers[1].call(
            address(rewardsContract),
            abi.encodeWithSignature("stake(uint256)", 2 * 10 * WAD)
        );

        /*** Farmer-1 time = (2 days) post-stake ***/
        assertEq(rewardsContract.totalSupply(), 4 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[1])), dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.earned(address(farmers[1])), dTime2_rpt * 10);
        assertEq(rewardsContract.rewards(address(farmers[1])), dTime2_rpt * 10);
        assertEq(rewardToken.balanceOf(address(farmers[1])), 0);

        // Warp to time = (2 days + 1 hours) (dTime = 1 hours)
        hevm.warp(start + 2 days + 1 hours);

        // Reward per token (RPT) that was used after Farmer-1 staked more into the pool (accrued over dTime = 1 hours)
        uint256 dTime3_rpt = rewardsContract.rewardRate() * 1 hours / (4 * 10);

        /*** Farmer-0 time = (2 days + 1 hours) pre-claim ***/
        assertEq(rewardsContract.totalSupply(), 4 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[0])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(farmers[0])), (dTime2_rpt + dTime3_rpt) * 10);
        assertEq(rewardsContract.rewards(address(farmers[0])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[0])), dTime1_rpt * 10);

        /*** Farmer-1 time = (2 days + 1 hours) pre-claim ***/
        assertEq(rewardsContract.totalSupply(), 4 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[1])), dTime1_rpt + dTime2_rpt);
        assertEq(rewardsContract.earned(address(farmers[1])), dTime2_rpt * 10 + dTime3_rpt * 30);
        assertEq(rewardsContract.rewards(address(farmers[1])), dTime2_rpt * 10);
        assertEq(rewardToken.balanceOf(address(farmers[1])), 0);

        // Get reward at time = (2 days + 1 hours)
        farmers[1].call(
            address(rewardsContract),
            abi.encodeWithSignature("getReward()")
        );

        /*** Farmer-1 time = (2 days + 1 hours) post-claim ***/
        assertEq(rewardsContract.totalSupply(), 4 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[1])), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.earned(address(farmers[1])), 0);
        assertEq(rewardsContract.rewards(address(farmers[1])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[1])), dTime2_rpt * 10 + dTime3_rpt * 30);
        
        // Try double claim
        farmers[1].call(
            address(rewardsContract),
            abi.encodeWithSignature("getReward()")
        );

        /*** Farmer-1 time = (2 days + 1 hours) post-claim (ASSERT NOTHING CHANGES) ***/
        assertEq(rewardsContract.totalSupply(), 4 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[1])), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.earned(address(farmers[1])), 0);
        assertEq(rewardsContract.rewards(address(farmers[1])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[1])), dTime2_rpt * 10 + dTime3_rpt * 30);

        // Farmer-0 withdraws 5 * WAD at time = (2 days + 1 hours)
        farmers[0].call(
            address(rewardsContract),
            abi.encodeWithSignature("withdraw(uint256)", 5 * WAD)
        );

        /*** Farmer-0 time = (2 days + 1 hours) pre-claim ***/
        assertEq(rewardsContract.totalSupply(), 35 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[0])), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.earned(address(farmers[0])), (dTime2_rpt + dTime3_rpt) * 10);
        assertEq(rewardsContract.rewards(address(farmers[0])), (dTime2_rpt + dTime3_rpt) * 10);
        assertEq(rewardToken.balanceOf(address(farmers[0])), dTime1_rpt * 10);

        // Warp to time = (3 days + 1 hours) (dTime = 1 days)
        hevm.warp(start + 3 days + 1 hours);

        // Reward per token (RPT) that was used after Farmer-0 withdrew from the pool (accrued over dTime = 1 days)
        uint256 dTime4_rpt = rewardsContract.rewardRate() * 1 days / 35;

        /*** Farmer-0 time = (3 days + 1 hours) pre-exit ***/
        assertEq(rewardsContract.totalSupply(), 35 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[0])), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.earned(address(farmers[0])), (dTime2_rpt + dTime3_rpt) * 10 + dTime4_rpt * 5);
        assertEq(rewardsContract.rewards(address(farmers[0])), (dTime2_rpt + dTime3_rpt) * 10);
        assertEq(rewardToken.balanceOf(address(farmers[0])), dTime1_rpt * 10);

        /*** Farmer-1 time = (2 days + 1 hours) pre-exit ***/
        assertEq(rewardsContract.totalSupply(), 35 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[1])), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.earned(address(farmers[1])), dTime4_rpt * 30);
        assertEq(rewardsContract.rewards(address(farmers[1])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[1])), dTime2_rpt * 10 + dTime3_rpt * 30);

        // Farmer-0 exits at time = (3 days + 1 hours)
        farmers[0].call(
            address(rewardsContract),
            abi.encodeWithSignature("exit()")
        );

        // Farmer-1 exits at time = (3 days + 1 hours)
        farmers[1].call(
            address(rewardsContract),
            abi.encodeWithSignature("exit()")
        );

        /*** Farmer-0 time = (3 days + 1 hours) post-exit ***/
        assertEq(rewardsContract.totalSupply(), 0);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[0])), dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt);
        assertEq(rewardsContract.earned(address(farmers[0])), 0);
        assertEq(rewardsContract.rewards(address(farmers[0])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[0])), ((dTime1_rpt + dTime2_rpt + dTime3_rpt) * 10 ether + dTime4_rpt * 5 ether) / WAD);

        /*** Farmer-1 time = (2 days + 1 hours) post-exit ***/
        assertEq(rewardsContract.totalSupply(), 0);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[1])), dTime1_rpt + dTime2_rpt + dTime3_rpt + dTime4_rpt);
        assertEq(rewardsContract.earned(address(farmers[1])), 0);
        assertEq(rewardsContract.rewards(address(farmers[1])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[1])), (dTime2_rpt * 10 ether + (dTime3_rpt + dTime4_rpt) * 30 ether) / WAD);
    }
}
