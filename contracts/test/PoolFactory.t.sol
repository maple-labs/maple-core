// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "./user/Governor.sol";
import "./user/PoolDelegate.sol";

import "../LiquidityLockerFactory.sol";
import "../Pool.sol";
import "../PoolFactory.sol";
import "../StakeLockerFactory.sol";

import "../oracles/ChainlinkOracle.sol";
import "../oracles/UsdOracle.sol";

import "../interfaces/IBFactory.sol";
import "../interfaces/IBPool.sol";
import "../interfaces/IStakeLocker.sol";

import "module/maple-token/contracts/MapleToken.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract PoolFactoryTest is TestUtil {

    Governor                       gov;
    PoolDelegate                   ali;

    MapleToken                     mpl;
    MapleGlobals               globals;
    PoolFactory            poolFactory;
    StakeLockerFactory       slFactory;
    LiquidityLockerFactory   llFactory;
    IBPool                       bPool;
    ChainlinkOracle         wethOracle;
    ChainlinkOracle         wbtcOracle;
    UsdOracle                usdOracle;

    uint256 public constant MAX_UINT = uint256(-1);

    function setUp() public {

        gov         = new Governor();       // Actor: Governor of Maple.
        ali         = new PoolDelegate();   // Actor: Manager of the Pool.

        mpl         = new MapleToken("MapleToken", "MAPL", USDC);
        globals     = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        slFactory   = new StakeLockerFactory();
        llFactory   = new LiquidityLockerFactory();
        poolFactory = new PoolFactory(address(globals));

        emit Debug("PoolFactorySize", getExtcodesize(address(poolFactory)));

        gov.setValidPoolFactory(address(poolFactory), true);
        
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        
        wethOracle = new ChainlinkOracle(tokens["WETH"].orcl, WETH, address(this));
        wbtcOracle = new ChainlinkOracle(tokens["WBTC"].orcl, WBTC, address(this));
        usdOracle  = new UsdOracle();
        
        gov.setPriceOracle(WETH, address(wethOracle));
        gov.setPriceOracle(WBTC, address(wbtcOracle));
        gov.setPriceOracle(USDC, address(usdOracle));

        mint("USDC", address(this), 50_000_000 * 10 ** 6);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), uint(-1));
        mpl.approve(address(bPool), uint(-1));

        bPool.bind(USDC, 50_000_000 * 10 ** 6, 5 * WAD);   // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl), 100_000 * WAD, 5 * WAD);  // Bind 100k MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * 10 ** 6);
        assertEq(mpl.balanceOf(address(bPool)),   100_000 * WAD);

        assertEq(bPool.balanceOf(address(this)), 0);  // Not finalized
    }

    function test_setGlobals() public {
        Governor fakeGov = new Governor();

        MapleGlobals globals2 = fakeGov.createGlobals(address(mpl), BPOOL_FACTORY);  // Create upgraded MapleGlobals

        assertEq(address(poolFactory.globals()), address(globals));

        assertTrue(!fakeGov.try_setGlobals(address(poolFactory), address(globals2)));  // Non-governor cannot set new globals

        globals2 = gov.createGlobals(address(mpl), BPOOL_FACTORY);                     // Create upgraded MapleGlobals

        assertTrue(gov.try_setGlobals(address(poolFactory), address(globals2)));       // Governor can set new globals
        assertEq(address(poolFactory.globals()), address(globals2));                   // Globals is updated
        assertTrue(false);
    }
        
    function createPoolFails() internal returns(bool) {
        return !ali.try_createPool(
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

    function setUpAllowlisting() internal {
        gov.setValidPoolFactory(address(poolFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setPoolDelegateAllowlist(address(ali), true);
        gov.setLoanAsset(USDC, true);
    }

    function test_createPool_globals_validations() public {
        setUpAllowlisting();
        bPool.finalize();

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
        gov.setPoolDelegateAllowlist(address(ali), false);
        assertTrue(createPoolFails()); 
        gov.setPoolDelegateAllowlist(address(ali), true);

        // PoolFactory:LIQ_ASSET_NOT_ALLOWED
        gov.setLoanAsset(USDC, false);
        assertTrue(createPoolFails());   
        gov.setLoanAsset(USDC, true);
    }

    function test_createPool_bad_stakeAsset() public {
        setUpAllowlisting();
        bPool.finalize();
        
        // PoolFactory:STAKE_ASSET_NOT_BPOOL
        assertTrue(!ali.try_createPool(
            address(poolFactory),
            USDC,
            address(ali),  // Passing in address of pool delegate for StakeAsset, an EOA which should fail isBPool check.
            address(slFactory),
            address(llFactory),
            500,
            100,
            MAX_UINT
        ));
    }

    function test_createPool_wrong_staking_pair_asset() public {
        setUpAllowlisting();
        bPool.finalize();

        gov.setLoanAsset(DAI, true);
        
        // Pool:Pool:INVALID_STAKING_POOL
        assertTrue(!ali.try_createPool(
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

        IERC20(DAI).approve(address(bPool), uint(-1));
        IERC20(USDC).approve(address(bPool), uint(-1));

        bPool.bind(USDC, 50_000_000 * 10 ** 6, 5 * WAD);  // Bind 50m   DAI with 5 denormalization weight
        bPool.bind(DAI,  50_000_000 * WAD,     5 * WAD);  // Bind 100k USDC with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * 10 ** 6);
        assertEq(IERC20(DAI).balanceOf(address(bPool)),  50_000_000 * WAD);

        bPool.finalize();
        
        assertTrue(!ali.try_createPool(
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

    function test_createPool_invalid_liquidity_cap() public {
        gov.setPoolDelegateAllowlist(address(ali), true);
        bPool.finalize();
        
        assertTrue(!ali.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100,
            0
        ));
    }

    // Tests failure mode in createStakeLocker
    function test_createPool_createStakeLocker_bPool_not_finalized() public {
        setUpAllowlisting();
        
        // Pool:INVALID_BALANCER_POOL
        assertTrue(!ali.try_createPool(
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

    function test_createPool() public {

        setUpAllowlisting();

        gov.setLoanAsset(USDC, true);

        gov.setPoolDelegateAllowlist(address(ali), true);
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        assertTrue(ali.try_createPool(
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
        assertEq(pool.slFactory(),                address(slFactory));
        assertEq(pool.poolDelegate(),             address(ali));
        assertEq(pool.stakingFee(),               500);
        assertEq(pool.delegateFee(),              100);
        assertEq(pool.liquidityCap(),             MAX_UINT);

        assertTrue(pool.stakeLocker()     != address(0));
        assertTrue(pool.liquidityLocker() != address(0));
    }
}
