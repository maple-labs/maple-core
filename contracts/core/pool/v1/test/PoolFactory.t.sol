// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { TestUtil } from "test/TestUtil.sol";

contract PoolFactoryTest is TestUtil {

    function setUp() public {
        setUpGlobals();
        setUpPoolDelegate();
        setUpTokens();
        setUpFactories();
        setUpOracles();
        setUpBalancerPool();
    }

    function test_setGlobals() public {
        MapleGlobals globals2 = fakeGov.createGlobals(address(mpl));                   // Create upgraded MapleGlobals

        assertEq(address(poolFactory.globals()), address(globals));

        assertTrue(!fakeGov.try_setGlobals(address(poolFactory), address(globals2)));  // Non-governor cannot set new globals

        globals2 = gov.createGlobals(address(mpl));                                    // Create upgraded MapleGlobals

        assertTrue(gov.try_setGlobals(address(poolFactory), address(globals2)));       // Governor can set new globals
        assertEq(address(poolFactory.globals()), address(globals2));                   // Globals is updated
    }

    function createPoolFails() internal returns (bool) {
        return !pat.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),  // Passing in address of pool delegate for StakeAsset, an EOA which should fail isBPool check.
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT
        );
    }

    function test_createPool_globals_validations() public {

        gov.setValidPoolFactory(address(poolFactory), true);

        // PoolFactory:INVALID_LL_FACTORY
        gov.setValidSubFactory(address(poolFactory), address(llFactory), false);
        assertTrue(createPoolFails());
        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);

        // PoolFactory:INVALID_SL_FACTORY
        gov.setValidSubFactory(address(poolFactory), address(slFactory), false);
        assertTrue(createPoolFails());
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);

        // PoolFactory:MSG_SENDER_NOT_ALLOWED
        gov.setPoolDelegateAllowlist(address(pat), false);
        assertTrue(createPoolFails());
        gov.setPoolDelegateAllowlist(address(pat), true);

        // PoolFactory:LIQ_ASSET_NOT_ALLOWED
        gov.setLiquidityAsset(USDC, false);
        assertTrue(createPoolFails());
        gov.setLiquidityAsset(USDC, true);
    }

    function test_createPool_bad_stakeAsset() public {

        // PoolFactory:STAKE_ASSET_NOT_BPOOL
        assertTrue(!pat.try_createPool(
            address(poolFactory),
            USDC,
            address(pat),  // Passing in address of pool delegate for StakeAsset, an EOA which should fail isBPool check.
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT
        ));
    }

    function test_createPool_wrong_staking_pair_asset() public {

        gov.setLiquidityAsset(DAI, true);

        // Pool:Pool:INVALID_STAKING_POOL
        assertTrue(!pat.try_createPool(
            address(poolFactory),
            DAI,
            address(bPool),    // This pool uses MPL/USDC, so it can't cover DAI losses
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT
        ));
    }

    // Tests failure mode in createStakeLocker
    function test_createPool_createStakeLocker_no_mpl_token() public {

        mint("USDC", address(this), 50_000_000 * 10 ** 6);
        mint("DAI", address(this), 50_000_000 ether);

        // Initialize USDC/USDC Balancer pool (Doesn't include mpl)
        bPool = IBPool(IBFactory(BPOOL_FACTORY).newBPool());

        IERC20(DAI).approve(address(bPool), uint256(-1));
        IERC20(USDC).approve(address(bPool), uint256(-1));

        bPool.bind(USDC, 50_000_000 * 10 ** 6, 5 * WAD);  // Bind 50m   DAI with 5 denormalization weight
        bPool.bind(DAI,  50_000_000 * WAD,     5 * WAD);  // Bind 100k USDC with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * 10 ** 6);
        assertEq(IERC20(DAI).balanceOf(address(bPool)),  50_000_000 * WAD);
        bPool.finalize();

        assertTrue(!pat.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT
        ));
    }

    function test_createPool_invalid_fees() public {

        // PoolLib:INVALID_FEES
        assertTrue(!pat.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            5000,  // 50.00%
            5001,  // 50.01%
            MAX_UINT
        ));

        assertTrue(pat.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            5000,  // 50.00%
            5000,  // 50.00%
            MAX_UINT
        ));
    }

    // Tests failure mode in createStakeLocker
    function test_createPool_createStakeLocker_bPool_not_finalized() public {

        bPool = IBPool(IBFactory(BPOOL_FACTORY).newBPool());
        mint("USDC", address(this), 50_000_000 * USD);
        usdc.approve(address(bPool), MAX_UINT);
        mpl.approve(address(bPool),  MAX_UINT);
        bPool.bind(USDC,         50_000_000 * USD, 5 ether);  // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl),    100_000 * WAD, 5 ether);  // Bind 100k MPL with 5 denormalization weight

        // Pool:INVALID_BALANCER_POOL
        assertTrue(!pat.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT
        ));
    }

    function test_createPool_paused() public {

        // Pause PoolFactory and attempt createPool()
        assertTrue( gov.try_pause(address(poolFactory)));
        assertTrue(!pat.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT
        ));
        assertEq(poolFactory.poolsCreated(), 0);

        // Unpause PoolFactory and createPool()
        assertTrue(gov.try_unpause(address(poolFactory)));
        assertTrue(pat.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT
        ));
        assertEq(poolFactory.poolsCreated(), 1);

        // Pause protocol and attempt createPool()
        assertTrue(!globals.protocolPaused());
        assertTrue( emergencyAdmin.try_setProtocolPause(address(globals), true));
        assertTrue(!pat.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT
        ));
        assertEq(poolFactory.poolsCreated(), 1);

        // Unpause protocol and createPool()
        assertTrue(emergencyAdmin.try_setProtocolPause(address(globals), false));
        assertTrue(pat.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT
        ));
        assertEq(poolFactory.poolsCreated(), 2);
    }

    function test_createPool_overflow() public {

        assertTrue(!pat.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            MAX_UINT,
            MAX_UINT
        ));
        assertEq(poolFactory.poolsCreated(), 0);
    }

    function test_createPool() public {

        assertTrue(pat.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT
        ));

        Pool pool = Pool(poolFactory.pools(0));

        assertTrue(address(pool) != address(0));
        assertTrue(poolFactory.isPool(address(pool)));
        assertEq(poolFactory.poolsCreated(), 1);

        assertEq(address(pool.liquidityAsset()),  USDC);
        assertEq(pool.stakeAsset(),               address(bPool));
        assertEq(pool.poolDelegate(),             address(pat));
        assertEq(pool.stakingFee(),               500);
        assertEq(pool.delegateFee(),              100);
        assertEq(pool.liquidityCap(),             MAX_UINT);

        assertTrue(pool.stakeLocker()     != address(0));
        assertTrue(pool.liquidityLocker() != address(0));
    }

}
