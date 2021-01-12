// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "./TestUtil.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../interfaces/IBPool.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";
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
        uint256 stakingFee,
        uint256 delegateFee
    ) 
        external returns (bool ok) 
    {
        string memory sig = "createPool(address,address,uint256,uint256)";
        (ok,) = address(poolFactory).call(
            abi.encodeWithSignature(sig, liquidityAsset, stakeAsset, stakingFee, delegateFee)
        );
    }
}

contract PoolFactoryTest is TestUtil {

    ERC20                  fundsToken;
    MapleToken             mpl;
    MapleGlobals           globals;
    PoolFactory   poolFactory;
    StakeLockerFactory     stakeLockerFactory;
    LiquidityLockerFactory liquidityLockerFactory;  
    DSValue                daiOracle;
    DSValue                usdcOracle;
    PoolDelegate           ali;
    IBPool                 bPool;

    function setUp() public {

        mpl                    = new MapleToken("MapleToken", "MAPL", USDC);
        globals                = new MapleGlobals(address(this), address(mpl), BPOOL_FACTORY);
        stakeLockerFactory     = new StakeLockerFactory();
        liquidityLockerFactory = new LiquidityLockerFactory();
        poolFactory            = new PoolFactory(address(globals), address(stakeLockerFactory), address(liquidityLockerFactory));
        daiOracle              = new DSValue();
        usdcOracle             = new DSValue();
        ali                    = new PoolDelegate();

        mint("USDC", address(this), 50_000_000 * 10 ** 6);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBPoolFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), uint(-1));
        mpl.approve(address(bPool), uint(-1));

        bPool.bind(USDC, 50_000_000 * 10 ** 6, 5 * WAD);          // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mpl), 100_000 * WAD, 5 * WAD);  // Bind 100k MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * 10 ** 6);
        assertEq(mpl.balanceOf(address(bPool)),   100_000 * WAD);

        assertEq(bPool.balanceOf(address(this)), 0);  // Not finalized
    }

    function test_createPool_no_finalize() public {
        globals.setPoolDelegateWhitelist(address(ali), true);
        
        assertTrue(!ali.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            500,
            100
        ));
    }

    function test_createPool_error_stakeAsset() public {
        globals.setPoolDelegateWhitelist(address(ali), true);
        
        assertTrue(!ali.try_createPool(
            address(poolFactory),
            USDC,
            address(ali),
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
            500,
            100
        ));
    }

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
            500,
            100
        ));
    }

    function test_createPool() public {
        globals.setPoolDelegateWhitelist(address(ali), true);
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        assertTrue(ali.try_createPool(
            address(poolFactory),
            USDC,
            address(bPool),
            500,
            100
        ));

        Pool lPool = Pool(poolFactory.pools(0));

        assertTrue(address(lPool) != address(0));
        assertTrue(poolFactory.isPool(address(lPool)));
        assertEq(poolFactory.poolsCreated(), 1);

        assertEq(lPool.liquidityAsset(),    USDC);
        assertEq(lPool.stakeAsset(),        address(bPool));
        assertEq(lPool.poolDelegate(),      address(ali));
        assertEq(lPool.stakingFee(),        500);
        assertEq(lPool.delegateFee(),       100);

        assertTrue(lPool.stakeLocker()     != address(0));
        assertTrue(lPool.liquidityLocker() != address(0));
    }
}
