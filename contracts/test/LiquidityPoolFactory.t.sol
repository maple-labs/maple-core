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
import "../LiquidityPoolFactory.sol";
import "../StakeLockerFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../LiquidityPool.sol";

interface IBPoolFactory {
    function newBPool() external returns (address);
}

contract PoolDelegate {
    function try_createLiquidityPool(
        address liquidityPoolFactory, 
        address liquidityAsset,
        address stakeAsset,
        uint256 stakingFee,
        uint256 delegateFee
    ) 
        external returns (bool ok) 
    {
        string memory sig = "createLiquidityPool(address,address,uint256,uint256)";
        (ok,) = address(liquidityPoolFactory).call(
            abi.encodeWithSignature(sig, liquidityAsset, stakeAsset, stakingFee, delegateFee)
        );
    }
}

contract LiquidityPoolFactoryTest is TestUtil {

    ERC20                  fundsToken;
    MapleToken             mapleToken;
    MapleGlobals           globals;
    LiquidityPoolFactory   liquidityPoolFactory;
    StakeLockerFactory     stakeLockerFactory;
    LiquidityLockerFactory liquidityLockerFactory;  
    DSValue                daiOracle;
    DSValue                usdcOracle;
    PoolDelegate           ali;
    IBPool                 bPool;

    function setUp() public {

        fundsToken             = new ERC20("FundsToken", "FT");
        mapleToken             = new MapleToken("MapleToken", "MAPL", IERC20(fundsToken));
        globals                = new MapleGlobals(address(this), address(mapleToken));
        stakeLockerFactory     = new StakeLockerFactory();
        liquidityLockerFactory = new LiquidityLockerFactory();
        liquidityPoolFactory   = new LiquidityPoolFactory(address(globals), address(stakeLockerFactory), address(liquidityLockerFactory));
        daiOracle              = new DSValue();
        usdcOracle             = new DSValue();
        ali                    = new PoolDelegate();

        mint("USDC", address(this), 50_000_000 * 10 ** 6);

        // Initialize MPL/USDC Balancer pool (without finalizing)
        bPool = IBPool(IBPoolFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), uint(-1));
        mapleToken.approve(address(bPool), uint(-1));

        bPool.bind(USDC, 50_000_000 * 10 ** 6, 5 * WAD);          // Bind 50m USDC with 5 denormalization weight
        bPool.bind(address(mapleToken), 100_000 * WAD, 5 * WAD);  // Bind 100k MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * 10 ** 6);
        assertEq(mapleToken.balanceOf(address(bPool)),   100_000 * WAD);

        assertEq(bPool.balanceOf(address(this)), 0);  // Not finalized
    }

    function test_createLiquidityPool_no_finalize() public {
        globals.setPoolDelegateWhitelist(address(ali), true);
        
        assertTrue(!ali.try_createLiquidityPool(
            address(liquidityPoolFactory),
            DAI,
            address(bPool),
            500,
            100
        ));
    }

    function test_createLiquidityPool_no_whitelist() public {
        bPool.finalize();
        
        assertTrue(!ali.try_createLiquidityPool(
            address(liquidityPoolFactory),
            DAI,
            address(bPool),
            500,
            100
        ));
    }

    function test_createLiquidityPool_no_mpl_token() public {

        mint("USDC", address(this), 50_000_000 * 10 ** 6);
        mint("DAI", address(this), 50_000_000 ether);

        // Initialize DAI/USDC Balancer pool (Doesn't include mapleToken)
        bPool = IBPool(IBPoolFactory(BPOOL_FACTORY).newBPool());

        IERC20(USDC).approve(address(bPool), uint(-1));
        IERC20(DAI).approve(address(bPool), uint(-1));

        bPool.bind(USDC, 50_000_000 * 10 ** 6, 5 * WAD);  // Bind 50m USDC with 5 denormalization weight
        bPool.bind(DAI,  50_000_000 * WAD, 5 * WAD);      // Bind 100k MPL with 5 denormalization weight

        assertEq(IERC20(USDC).balanceOf(address(bPool)), 50_000_000 * 10 ** 6);
        assertEq(IERC20(DAI).balanceOf(address(bPool)),  50_000_000 * WAD);

        bPool.finalize();
        
        assertTrue(!ali.try_createLiquidityPool(
            address(liquidityPoolFactory),
            DAI,
            address(bPool),
            500,
            100
        ));
    }

    function test_createLiquidityPool() public {
        globals.setPoolDelegateWhitelist(address(ali), true);
        bPool.finalize();

        assertEq(bPool.balanceOf(address(this)), 100 * WAD);
        assertEq(bPool.balanceOf(address(this)), bPool.INIT_POOL_SUPPLY());  // Assert BPTs were minted

        assertTrue(ali.try_createLiquidityPool(
            address(liquidityPoolFactory),
            DAI,
            address(bPool),
            500,
            100
        ));

        LiquidityPool lPool = LiquidityPool(liquidityPoolFactory.getLiquidityPool(0));

        assertTrue(address(lPool) != address(0));
        assertTrue(liquidityPoolFactory.isLiquidityPool(address(lPool)));
        assertEq(liquidityPoolFactory.liquidityPoolsCreated(), 1);

        assertEq(lPool.liquidityAsset(),    DAI);
        assertEq(lPool.stakeAsset(),        address(bPool));
        assertEq(lPool.poolDelegate(),      address(ali));
        assertEq(lPool.stakingFee(),        500);
        assertEq(lPool.delegateFee(),       100);

        assertTrue(lPool.stakeLockerAddress()     != address(0));
        assertTrue(lPool.liquidityLockerAddress() != address(0));
    }
}
