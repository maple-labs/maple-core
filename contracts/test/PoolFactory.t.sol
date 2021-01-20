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

    function test_createPool_no_finalize() public {
        gov.setPoolDelegateWhitelist(address(ali), true);
        
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

    function test_createPool_error_stakeAsset() public {
        gov.setPoolDelegateWhitelist(address(ali), true);
        
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

    // Tests failure mode in createStakeLocker
    function test_createPool_bPool_not_finalized() public {
        gov.setPoolDelegateWhitelist(address(ali), true);
        
        assertTrue(!ali.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            address(slFactory),
            address(llFactory),
            500,
            100
        ));
    }

    function test_createPool_no_whitelist() public {
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

    // Tests failure mode in createStakeLocker
    function test_createPool_no_mpl_token() public {

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

    function test_createPool() public {

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

        Pool lPool = Pool(poolFactory.pools(0));

        assertTrue(address(lPool) != address(0));
        assertTrue(poolFactory.isPool(address(lPool)));
        assertEq(poolFactory.poolsCreated(), 1);

        assertEq(address(lPool.liquidityAsset()),  USDC);
        assertEq(lPool.stakeAsset(),               address(bPool));
        assertEq(lPool.poolDelegate(),             address(ali));
        assertEq(lPool.stakingFee(),               500);
        assertEq(lPool.delegateFee(),              100);
        assertEq(lPool.liquidityCap(),             MAX_UINT);

        assertTrue(lPool.stakeLocker()     != address(0));
        assertTrue(lPool.liquidityLocker() != address(0));


    }
}
