pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";

import "lib/openzeppelin-contracts/src/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/src/token/ERC20/IERC20.sol";

import "../MapleToken.sol";
import "../MapleGlobals.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract MapleGlobalsTest is DSTest {

    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    ERC20        fundsToken;
    MapleToken   mapleToken;
    MapleGlobals globals;

    function setUp() public {
        fundsToken = new ERC20("FundsToken", "FT");
        mapleToken = new MapleToken("MapleToken", "MAPL", IERC20(fundsToken));
        globals    = new MapleGlobals(address(this), address(mapleToken));
    }

    function test_setters() public {
        assertEq(globals.establishmentFeeBasisPoints(), 200);
        globals.setEstablishmentFee(50);
        assertEq(globals.establishmentFeeBasisPoints(), 50);

        assertEq(globals.treasuryFeeBasisPoints(), 20);
        globals.setTreasurySplit(30);
        assertEq(globals.treasuryFeeBasisPoints(), 30);

        assertEq(globals.gracePeriod(), 5 days);
        globals.setGracePeriod(1 days);
        assertEq(globals.gracePeriod(), 1 days);

        assertEq(globals.stakeAmountRequired(), 25000);
        globals.setStakeRequired(35000);
        assertEq(globals.stakeAmountRequired(), 35000);

        assertEq(globals.unstakeDelay(), 90 days);
        globals.setUnstakeDelay(30 days);
        assertEq(globals.unstakeDelay(), 30 days);

        assertEq(globals.governor(), address(this));
        globals.setGovernor(address(this));
        assertEq(globals.governor(), address(this));
    }

    function test_add_tokens() public {
        string[]  memory validBorrowTokenSymbols;
        address[] memory validBorrowTokenAddresses;
        string[]  memory validCollateralTokenSymbols;
        address[] memory validCollateralTokenAddresses;
        (
            validBorrowTokenSymbols,
            validBorrowTokenAddresses,
            validCollateralTokenSymbols,
            validCollateralTokenAddresses
        ) = globals.getValidTokens();

        assertEq(validBorrowTokenSymbols.length,       0);
        assertEq(validBorrowTokenAddresses.length,     0);
        assertEq(validCollateralTokenSymbols.length,   0);
        assertEq(validCollateralTokenAddresses.length, 0);

        globals.addCollateralToken(WETH);
        (
            validBorrowTokenSymbols,
            validBorrowTokenAddresses,
            validCollateralTokenSymbols,
            validCollateralTokenAddresses
        ) = globals.getValidTokens();

        assertEq(validBorrowTokenSymbols.length,            0);
        assertEq(validBorrowTokenAddresses.length,          0);
        assertEq(validCollateralTokenSymbols.length,        1);
        assertEq(validCollateralTokenAddresses.length,      1);
        assertEq(validCollateralTokenSymbols[0],       "WETH");
        assertEq(validCollateralTokenAddresses[0],      WETH);

        globals.addBorrowToken(DAI);
        (
            validBorrowTokenSymbols,
            validBorrowTokenAddresses,
            validCollateralTokenSymbols,
            validCollateralTokenAddresses
        ) = globals.getValidTokens();

        assertEq(validBorrowTokenSymbols.length,           1);
        assertEq(validBorrowTokenAddresses.length,         1);
        assertEq(validCollateralTokenSymbols.length,       1);
        assertEq(validCollateralTokenAddresses.length,     1);
        assertEq(validBorrowTokenSymbols[0],           "DAI");
        assertEq(validBorrowTokenAddresses[0],          DAI);
    }
}


