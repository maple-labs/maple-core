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

    function mplRewards_transferOwnership(MplRewards mplRewards, address newOwner) external {
        mplRewards.transferOwnership(newOwner);
    }

    function try_mplRewards_transferOwnership(address mplRewards, address newOwner) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("transferOwnership(address)", newOwner));
    }

    function mplRewards_notifyRewardAmount(MplRewards mplRewards, uint256 amount) external {
        mplRewards.notifyRewardAmount(amount);
    }

    function try_mplRewards_notifyRewardAmount(address mplRewards, uint256 amount) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("notifyRewardAmount(uint256)", amount));
    }

    function mplRewards_updatePeriodFinish(MplRewards mplRewards, uint256 periodFinish) external {
        mplRewards.updatePeriodFinish(periodFinish);
    }

    function try_mplRewards_updatePeriodFinish(address mplRewards, uint256 periodFinish) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("updatePeriodFinish(uint256)", periodFinish));
    }

    function mplRewards_recoverERC20(MplRewards mplRewards, address tokenAddress, uint256 amount) external {
        mplRewards.recoverERC20(tokenAddress, amount);
    }

    function try_mplRewards_recoverERC20(address mplRewards, address tokenAddress, uint256 amount) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("recoverERC20(address,uint256)", tokenAddress, amount));
    }

    function mplRewards_setRewardsDuration(MplRewards mplRewards, uint256 duration) external {
        mplRewards.setRewardsDuration(duration);
    }

    function try_mplRewards_setRewardsDuration(address mplRewards, uint256 duration) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("setRewardsDuration(uint256)", duration));
    }

    function mplRewards_setPaused(MplRewards mplRewards, bool paused) external {
        mplRewards.setPaused(paused);
    }

    function try_mplRewards_setPaused(address mplRewards, bool paused) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("setPaused(bool)", paused));
    }

    function mplRewards_stake(MplRewards mplRewards, uint256 amount) external {
        mplRewards.stake(amount);
    }

    function try_mplRewards_stake(address mplRewards, uint256 amount) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("stake(uint256)", amount));
    }

    function mplRewards_withdraw(MplRewards mplRewards, uint256 amount) external {
        mplRewards.withdraw(amount);
    }

    function try_mplRewards_withdraw(address mplRewards, uint256 amount) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("withdraw(uint256)", amount));
    }

    function mplRewards_getReward(MplRewards mplRewards) external {
        mplRewards.getReward();
    }

    function try_mplRewards_getReward(address mplRewards) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("getReward()"));
    }

    function mplRewards_exit(MplRewards mplRewards) external {
        mplRewards.exit();
    }

    function try_mplRewards_exit(address mplRewards) external returns (bool ok) {
        (ok,) = mplRewards.call(abi.encodeWithSignature("exit()"));
    }

    function erc2258_increaseCustodyAllowance(ERC2258 token, address custodian, uint256 amount) external {
        token.increaseCustodyAllowance(custodian, amount);
    }

    function try_erc2258_increaseCustodyAllowance(address token, address custodian, uint256 amount) external returns (bool ok) {
        (ok,) = token.call(abi.encodeWithSignature("increaseCustodyAllowance(address,uint256)", custodian, amount));
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

        assertTrue(!account2.try_mplRewards_transferOwnership(address(rewardsContract), address(account2)));

        assertTrue(account1.try_mplRewards_transferOwnership(address(rewardsContract), address(account2)));
        assertEq(rewardsContract.owner(), address(account2));
        
        assertTrue(!account1.try_mplRewards_transferOwnership(address(rewardsContract), address(account1)));

        assertTrue(account2.try_mplRewards_transferOwnership(address(rewardsContract), address(account1)));
        assertEq(rewardsContract.owner(), address(account1));
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

        assertTrue(!notOwner.try_mplRewards_notifyRewardAmount(address(rewardsContract), totalRewards));

        assertTrue(owner.try_mplRewards_notifyRewardAmount(address(rewardsContract), totalRewards));

        assertEq(rewardsContract.rewardRate(),        totalRewards / 7 days);
        assertEq(rewardsContract.lastUpdateTime(),          block.timestamp);
        assertEq(rewardsContract.periodFinish(),   block.timestamp + 7 days);
    }

    function test_updatePeriodFinish() external {
        SomeAccount owner = new SomeAccount();
        SomeAccount notOwner = new SomeAccount();
        MplRewards rewardsContract = new MplRewards(address(0), address(1), address(owner));

        assertTrue(!notOwner.try_mplRewards_updatePeriodFinish(address(rewardsContract), block.timestamp + 30 days));

        assertTrue(owner.try_mplRewards_updatePeriodFinish(address(rewardsContract), block.timestamp + 30 days));
    }

    function test_recoverERC20() external {
        SomeAccount owner = new SomeAccount();
        SomeAccount notOwner = new SomeAccount();
        SomeERC2258 someToken = new SomeERC2258("SMT", "SMT");
        MplRewards rewardsContract = new MplRewards(address(0), address(1), address(owner));

        someToken.mint(address(rewardsContract), 1);
        assertEq(someToken.balanceOf(address(rewardsContract)), 1);
        assertEq(rewardsContract.totalSupply(), 0);

        assertTrue(!notOwner.try_mplRewards_recoverERC20(address(rewardsContract), address(someToken), 1));

        assertTrue(owner.try_mplRewards_recoverERC20(address(rewardsContract), address(someToken), 1));
        assertEq(someToken.balanceOf(address(rewardsContract)), 0);

        assertEq(rewardsContract.totalSupply(), 0);
    }

    function test_setRewardsDuration() external {
        SomeAccount owner = new SomeAccount();
        SomeAccount notOwner = new SomeAccount();
        SomeERC2258 rewardsToken = new SomeERC2258("RWT", "RWT");
        MplRewards rewardsContract = new MplRewards(address(rewardsToken), address(0), address(owner));

        rewardsToken.mint(address(rewardsContract), 1);

        owner.mplRewards_notifyRewardAmount(rewardsContract, 1);        
        assertEq(rewardsContract.periodFinish(),    block.timestamp + 7 days);
        assertEq(rewardsContract.rewardsDuration(),                   7 days);

        assertTrue(!notOwner.try_mplRewards_setRewardsDuration(address(rewardsContract), 30 days));

        assertTrue(!owner.try_mplRewards_setRewardsDuration(address(rewardsContract), 30 days));

        hevm.warp(rewardsContract.periodFinish());

        assertTrue(!owner.try_mplRewards_setRewardsDuration(address(rewardsContract), 30 days));

        hevm.warp(rewardsContract.periodFinish() + 1);

        assertTrue(!notOwner.try_mplRewards_setRewardsDuration(address(rewardsContract), 30 days));

        assertTrue(owner.try_mplRewards_setRewardsDuration(address(rewardsContract), 30 days));

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

        assertTrue(!notOwner.try_mplRewards_setPaused(address(rewardsContract), true));

        assertTrue(owner.try_mplRewards_setPaused(address(rewardsContract), true));
        assertTrue(rewardsContract.paused());

        assertTrue(!notOwner.try_mplRewards_setPaused(address(rewardsContract), false));

        assertTrue(owner.try_mplRewards_setPaused(address(rewardsContract), false));
        assertTrue(!rewardsContract.paused());

        stakingToken.mint(address(account1), 2);

        account1.erc2258_increaseCustodyAllowance(stakingToken, address(rewardsContract), 2);
        assertTrue(account1.try_mplRewards_stake(address(rewardsContract), 2));
        assertTrue(account1.try_mplRewards_withdraw(address(rewardsContract), 1));

        owner.mplRewards_setPaused(rewardsContract, true);

        account1.erc2258_increaseCustodyAllowance(stakingToken, address(rewardsContract), 1);
        assertTrue(!account1.try_mplRewards_stake(address(rewardsContract), 1));
        assertTrue(!account1.try_mplRewards_withdraw(address(rewardsContract), 1));
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
            farmers[i].erc2258_increaseCustodyAllowance(stakingToken, address(rewardsContract), 100 * WAD);
        }

        farmers[0].mplRewards_stake(rewardsContract, 10 * WAD);

        rewardToken.mint(address(rewardsContract), totalRewardsInWad);

        owner.mplRewards_setRewardsDuration(rewardsContract, rewardsDuration);
        owner.mplRewards_notifyRewardAmount(rewardsContract, totalRewardsInWad);
        
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
        farmers[0].mplRewards_getReward(rewardsContract);

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
        farmers[0].mplRewards_getReward(rewardsContract);

        /*** Farmer-0 time = (1 days) post-claim ***/
        assertEq(rewardsContract.totalSupply(), 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[0])), dTime1_rpt);
        assertEq(rewardsContract.earned(address(farmers[0])), 0);
        assertEq(rewardsContract.rewards(address(farmers[0])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[0])), dTime1_rpt * 10);

        // Farmer-1 stakes 10 FDTs, giving him 50% stake in the pool rewards going forward
        farmers[1].mplRewards_stake(rewardsContract, 10 * WAD);

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
        farmers[1].mplRewards_stake(rewardsContract, 2 * 10 * WAD);

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
        farmers[1].mplRewards_getReward(rewardsContract);

        /*** Farmer-1 time = (2 days + 1 hours) post-claim ***/
        assertEq(rewardsContract.totalSupply(), 4 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[1])), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.earned(address(farmers[1])), 0);
        assertEq(rewardsContract.rewards(address(farmers[1])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[1])), dTime2_rpt * 10 + dTime3_rpt * 30);
        
        // Try double claim
        farmers[1].mplRewards_getReward(rewardsContract);

        /*** Farmer-1 time = (2 days + 1 hours) post-claim (ASSERT NOTHING CHANGES) ***/
        assertEq(rewardsContract.totalSupply(), 4 * 10 * WAD);
        assertEq(rewardsContract.rewardPerTokenStored(), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.userRewardPerTokenPaid(address(farmers[1])), dTime1_rpt + dTime2_rpt + dTime3_rpt);
        assertEq(rewardsContract.earned(address(farmers[1])), 0);
        assertEq(rewardsContract.rewards(address(farmers[1])), 0);
        assertEq(rewardToken.balanceOf(address(farmers[1])), dTime2_rpt * 10 + dTime3_rpt * 30);

        // Farmer-0 withdraws 5 * WAD at time = (2 days + 1 hours)
        farmers[0].mplRewards_withdraw(rewardsContract, 5 * WAD);

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
        farmers[0].mplRewards_exit(rewardsContract);

        // Farmer-1 exits at time = (3 days + 1 hours)
        farmers[1].mplRewards_exit(rewardsContract);

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
