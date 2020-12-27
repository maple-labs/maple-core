pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "lib/ds-test/contracts/test.sol";

import "../mocks/value.sol";
import "../mocks/token.sol";

import "../interface/IBPool.sol";

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";
import "../LiquidityPoolFactory.sol";
import "../StakeLockerFactory.sol";
import "../LiquidityLockerFactory.sol";
import "../LiquidityPool.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

interface IBPoolFactory {
    function newBPool() external returns (address);
}

contract PoolDelegate {
    function try_createLiquidityPool(
        address liquidityPoolFactory, 
        address liquidityAsset,
        address stakeAsset,
        uint256 stakingFeeBasisPoints,
        uint256 delegateFeeBasisPoints,
        string memory name,
        string memory symbol
    ) 
        external returns (bool ok) 
    {
        string memory sig = "createLiquidityPool(address,address,uint256,uint256,string,string)";
        (ok,) = address(liquidityPoolFactory).call(
            abi.encodeWithSignature(sig, liquidityAsset, stakeAsset, stakingFeeBasisPoints, delegateFeeBasisPoints, name, symbol)
        );
    }
}



contract LiquidityPoolTest is DSTest {

    address constant DAI           = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC          = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant BPOOL_FACTORY = 0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd; // Balancer pool factory

    uint256 constant WAD = 10 ** 18;

    Hevm                   hevm;
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

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    function setUp() public {

        hevm = Hevm(address(CHEAT_CODE));

        fundsToken             = new ERC20("FundsToken", "FT");
        mapleToken             = new MapleToken("MapleToken", "MAPL", IERC20(fundsToken));
        globals                = new MapleGlobals(address(this), address(mapleToken));
        stakeLockerFactory     = new StakeLockerFactory();
        liquidityLockerFactory = new LiquidityLockerFactory();
        liquidityPoolFactory   = new LiquidityPoolFactory(address(globals), address(stakeLockerFactory), address(liquidityLockerFactory));
        daiOracle              = new DSValue();
        usdcOracle             = new DSValue();
        ali                    = new PoolDelegate();

        // Mint 50m USDC into this account
        assertEq(IERC20(USDC).balanceOf(address(this)), 0);
        hevm.store(
            USDC,
            keccak256(abi.encode(address(this), uint256(9))),
            bytes32(uint256(50_000_000 * 10 ** 6))
        );
        assertEq(IERC20(USDC).balanceOf(address(this)), 50_000_000 * 10 ** 6);

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
            100,
            "Maple Liquidity Pool 0",
            "MPL_LP_0"
        ));
    }

    function test_createLiquidityPool_no_whitelist() public {
        bPool.finalize();
        
        assertTrue(!ali.try_createLiquidityPool(
            address(liquidityPoolFactory),
            DAI,
            address(bPool),
            500,
            100,
            "Maple Liquidity Pool 0",
            "MPL_LP_0"
        ));
    }

    function test_createLiquidityPool_no_mpl_token() public {

        // Mint 50m USDC into this account
        assertEq(IERC20(USDC).balanceOf(address(this)), 0);
        hevm.store(
            USDC,
            keccak256(abi.encode(address(this), uint256(9))),
            bytes32(uint256(50_000_000 * 10 ** 6))
        );
        assertEq(IERC20(USDC).balanceOf(address(this)), 50_000_000 * 10 ** 6);

        // Mint 50m DAI into this account
        assertEq(IERC20(DAI).balanceOf(address(this)), 0);
        hevm.store(
            DAI,
            keccak256(abi.encode(address(this), uint256(2))),
            bytes32(uint256(50_000_000 * WAD))
        );
        assertEq(IERC20(DAI).balanceOf(address(this)), 50_000_000 * WAD);

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
            100,
            "Maple Liquidity Pool 0",
            "MPL_LP_0"
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
            100,
            "Maple Liquidity Pool 0",
            "MPL_LP_0"
        ));

        LiquidityPool lPool = LiquidityPool(liquidityPoolFactory.getLiquidityPool(0));

        assertTrue(address(lPool) != address(0));
        assertTrue(liquidityPoolFactory.isLiquidityPool(address(lPool)));
        assertEq(liquidityPoolFactory.liquidityPoolsCreated(), 1);

        assertEq(lPool.liquidityAsset(),              DAI);
        assertEq(lPool.stakeAsset(),                  address(bPool));
        assertEq(lPool.poolDelegate(),                address(ali));
        assertEq(lPool.stakingFeeBasisPoints(),       500);
        assertEq(lPool.delegateFeeBasisPoints(),      100);

        assertTrue(lPool.stakeLockerAddress()     != address(0));
        assertTrue(lPool.liquidityLockerAddress() != address(0));
    }
}
