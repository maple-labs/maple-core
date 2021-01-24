// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "../../MapleGlobals.sol";

contract Governor {

    MapleGlobals globals;

    function createGlobals(address mpl, address bPoolFactory) external returns (MapleGlobals) {
        globals = new MapleGlobals(address(this), address(mpl), bPoolFactory);
        return globals;
    }

    function try_setGlobals(address loan, address globals) external returns (bool ok) {
        string memory sig = "setGlobals(address)";
        (ok,) = address(loan).call(abi.encodeWithSignature(sig, globals));
    }

    function setCalc(address calc, bool valid)                        external { globals.setCalc(calc, valid); }
    function setCollateralAsset(address asset, bool valid)            external { globals.setCollateralAsset(asset, valid); }
    function setLoanAsset(address asset, bool valid)                  external { globals.setLoanAsset(asset, valid); }
    function assignPriceFeed(address asset, address oracle)           external { globals.assignPriceFeed(asset, oracle); }
    function setValidLoanFactory(address factory, bool valid)         external { globals.setValidLoanFactory(factory, valid); }
    function setValidPoolFactory(address factory, bool valid)         external { globals.setValidPoolFactory(factory, valid); }
    function setValidSubFactory(address fac, address sub, bool valid) external { globals.setValidSubFactory(fac, sub, valid); }
    function setMapleTreasury(address treasury)                       external { globals.setMapleTreasury(treasury); }
    function setPoolDelegateWhitelist(address pd, bool valid)         external { globals.setPoolDelegateWhitelist(pd, valid); }
    function setInvestorFee(uint256 fee)                              external { globals.setInvestorFee(fee); }
    function setTreasuryFee(uint256 fee)                              external { globals.setTreasuryFee(fee); }
    function setGracePeriod(uint256 gracePeriod)                      external { globals.setGracePeriod(gracePeriod); }
    function setDrawdownGracePeriod(uint256 gracePeriod)              external { globals.setDrawdownGracePeriod(gracePeriod); }
    function setSwapOutRequired(uint256 swapAmt)                      external { globals.setSwapOutRequired(swapAmt); }
    function setUnstakeDelay(uint256 delay)                           external { globals.setUnstakeDelay(delay); }
    function setGovernor(address gov)                                 external { globals.setGovernor(gov); }
}
