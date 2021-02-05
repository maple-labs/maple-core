// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../interfaces/IBPool.sol";
import "../interfaces/IStakeLocker.sol";

import "./user/Governor.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../PoolFactory.sol";
import "../StakeLockerFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../Pool.sol";



interface IBPoolFactory {
    function newBPool() external returns (address);
}

contract PoolDelegate {
    function try_createPool(
        address poolFactory, 
        address liquidityAsset,
        address stakeAsset,
        address slFactory, 
        address llFactory,
        uint256 stakingFee,
        uint256 delegateFee,
        uint256 liquidityCap
    ) 
        external returns (bool ok) 
    {
        string memory sig = "createPool(address,address,address,address,uint256,uint256,uint256)";
        (ok,) = address(poolFactory).call(
            abi.encodeWithSignature(sig, liquidityAsset, stakeAsset, slFactory, llFactory, stakingFee, delegateFee, liquidityCap)
        );
    }
}

contract PoolFactoryTest is TestUtil {

    Governor                       gov;
    MapleToken                     mpl;
    MapleGlobals               globals;
    PoolFactory            poolFactory;
    StakeLockerFactory       slFactory;
    LiquidityLockerFactory   llFactory;  
    DSValue                  daiOracle;
    DSValue                 usdcOracle;
    PoolDelegate                   ali;
    IBPool                       bPool;

    uint256 public constant MAX_UINT = uint256(-1);

    function setUp() public {

        gov         = new Governor();
        mpl         = new MapleToken("MapleToken", "MAPL", USDC);
        globals     = gov.createGlobals(address(mpl), BPOOL_FACTORY);
        slFactory   = new StakeLockerFactory();
        llFactory   = new LiquidityLockerFactory();
        poolFactory = new PoolFactory(address(globals));
        daiOracle   = new DSValue();
        usdcOracle  = new DSValue();
        ali         = new PoolDelegate();

        gov.setValidPoolFactory(address(poolFactory), true);
        
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setPriceOracle(WETH, 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        gov.setPriceOracle(WBTC, 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
        gov.setPriceOracle(USDC, 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);

        mint("USDC", address(this), 50_000_000 * 10 ** 6);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBPoolFactory(BPOOL_FACTORY).newBPool());

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

    function setUpWhitelisting() internal {
        gov.setValidPoolFactory(address(poolFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(llFactory), true);
        gov.setValidSubFactory(address(poolFactory), address(slFactory), true);
        gov.setPoolDelegateWhitelist(address(ali), true);
        gov.setLoanAsset(USDC, true);
    }

    function test_createPool_globals_validations() public {
        setUpWhitelisting();
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

        // PoolFactory:MSG_SENDER_NOT_WHITELISTED
        gov.setPoolDelegateWhitelist(address(ali), false);
        assertTrue(createPoolFails()); 
        gov.setPoolDelegateWhitelist(address(ali), true);

        // PoolFactory:LIQ_ASSET_NOT_WHITELISTED
        gov.setLoanAsset(USDC, false);
        assertTrue(createPoolFails());   
        gov.setLoanAsset(USDC, true);
    }

    function test_createPool_bad_stakeAsset() public {
        setUpWhitelisting();
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
        setUpWhitelisting();
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
        bPool = IBPool(IBPoolFactory(BPOOL_FACTORY).newBPool());

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
        gov.setPoolDelegateWhitelist(address(ali), true);
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
        setUpWhitelisting();
        
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

        setUpWhitelisting();

        gov.setLoanAsset(USDC, true);

        gov.setPoolDelegateWhitelist(address(ali), true);
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
