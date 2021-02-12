// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;
pragma experimental ABIEncoderV2;

import "../../MapleGlobals.sol";
import "../../StakingRewards.sol";

contract Governor {

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    MapleGlobals   globals;
    StakingRewards stakingRewards;

    function createGlobals(address mpl, address bPoolFactory) external returns (MapleGlobals) {
        globals = new MapleGlobals(address(this), mpl, bPoolFactory);
        return globals;
    }

    function createStakingRewards(address mpl, address pool) external returns (StakingRewards) {
        stakingRewards = new StakingRewards(mpl, pool);
        return stakingRewards;
    }

    // Used for "fake" governors pointing at a globals contract they didnt create
    function setGovGlobals(MapleGlobals _globals) external {
        globals = _globals;
    }

    // Used for "fake" governors pointing at a staking rewards contract they dont own
    function setGovStakingRewards(StakingRewards _stakingRewards) external {
        stakingRewards = _stakingRewards;
    }

    /*** MapleGlobals Setters ***/ 
    function setCalc(address calc, bool valid)                            external { globals.setCalc(calc, valid); }
    function setCollateralAsset(address asset, bool valid)                external { globals.setCollateralAsset(asset, valid); }
    function setLoanAsset(address asset, bool valid)                      external { globals.setLoanAsset(asset, valid); }
    function assignPriceFeed(address asset, address oracle)               external { globals.assignPriceFeed(asset, oracle); }
    function setValidLoanFactory(address factory, bool valid)             external { globals.setValidLoanFactory(factory, valid); }
    function setValidPoolFactory(address factory, bool valid)             external { globals.setValidPoolFactory(factory, valid); }
    function setValidSubFactory(address fac, address sub, bool valid)     external { globals.setValidSubFactory(fac, sub, valid); }
    function setMapleTreasury(address treasury)                           external { globals.setMapleTreasury(treasury); }
    function setPoolDelegateWhitelist(address pd, bool valid)             external { globals.setPoolDelegateWhitelist(pd, valid); }
    function setInvestorFee(uint256 fee)                                  external { globals.setInvestorFee(fee); }
    function setTreasuryFee(uint256 fee)                                  external { globals.setTreasuryFee(fee); }
    function setGracePeriod(uint256 gracePeriod)                          external { globals.setGracePeriod(gracePeriod); }
    function setDrawdownGracePeriod(uint256 gracePeriod)                  external { globals.setDrawdownGracePeriod(gracePeriod); }
    function setSwapOutRequired(uint256 swapAmt)                          external { globals.setSwapOutRequired(swapAmt); }
    function setUnstakeDelay(uint256 delay)                               external { globals.setUnstakeDelay(delay); }
    function setGovernor(address gov)                                     external { globals.setGovernor(gov); }
    function setPriceOracle(address asset, address oracle)                external { globals.setPriceOracle(asset, oracle); }
    function setMaxSwapSlippage(uint256 newSlippage)                      external { globals.setMaxSwapSlippage(newSlippage); }
    function setDefaultUniswapPath(address from, address to, address mid) external { globals.setDefaultUniswapPath(from, to, mid); }

    /*** StakingReards Setters ***/ 
    function notifyRewardAmount(uint256 reward)       external { stakingRewards.notifyRewardAmount(reward); }
    function updatePeriodFinish(uint256 timestamp)    external { stakingRewards.updatePeriodFinish(timestamp); }
    function recoverERC20(address asset, uint256 amt) external { stakingRewards.recoverERC20(asset, amt); }
    function setRewardsDuration(uint256 duration)     external { stakingRewards.setRewardsDuration(duration); }
    function setPaused(bool paused)                   external { stakingRewards.setPaused(paused); }


    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    /*** MapleGlobals Setters ***/ 
    function try_setGlobals(address target, address _globals) external returns (bool ok) {
        string memory sig = "setGlobals(address)";
        (ok,) = address(target).call(abi.encodeWithSignature(sig, _globals));
    }

    function try_setDefaultUniswapPath(address from, address to, address mid) external returns (bool ok) { 
        string memory sig = "setDefaultUniswapPath(address,address,address)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, from, to, mid)); 
    }

    function try_setCalc(address calc, bool valid) external returns (bool ok) { 
        string memory sig = "setCalc(address,bool)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, calc, valid)); 
    }

    function try_setCollateralAsset(address asset, bool valid) external returns (bool ok) { 
        string memory sig = "setCollateralAsset(address,bool)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, asset, valid)); 
    }

    function try_setLoanAsset(address asset, bool valid) external returns (bool ok) { 
        string memory sig = "setLoanAsset(address,bool)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, asset, valid)); 
    }

    function try_assignPriceFeed(address asset, address oracle) external returns (bool ok) { 
        string memory sig = "assignPriceFeed(address,address)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, asset, oracle)); 
    }

    function try_setValidLoanFactory(address factory, bool valid) external returns (bool ok) { 
        string memory sig = "setValidLoanFactory(address,bool)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, factory, valid));
    }

    function try_setValidPoolFactory(address factory, bool valid) external returns (bool ok) { 
        string memory sig = "setValidPoolFactory(address,bool)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, factory, valid));
    }

    function try_setValidSubFactory(address fac, address sub, bool valid) external returns (bool ok) { 
        string memory sig = "setValidSubFactory(address,address,bool)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, fac, sub, valid));
    }

    function try_setMapleTreasury(address treasury) external returns (bool ok) { 
        string memory sig = "setMapleTreasury(address)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, treasury));
    }

    function try_setPoolDelegateWhitelist(address pd, bool valid) external returns (bool ok) { 
        string memory sig = "setPoolDelegateWhitelist(address,bool)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, pd, valid));
    }

    function try_setInvestorFee(uint256 fee) external returns (bool ok) { 
        string memory sig = "setInvestorFee(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, fee));
    }

    function try_setTreasuryFee(uint256 fee) external returns (bool ok) { 
        string memory sig = "setTreasuryFee(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, fee));
    }

    function try_setGracePeriod(uint256 gracePeriod) external returns (bool ok) { 
        string memory sig = "setGracePeriod(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, gracePeriod)); 
    }

    function try_setDrawdownGracePeriod(uint256 gracePeriod) external returns (bool ok) { 
        string memory sig = "setDrawdownGracePeriod(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, gracePeriod)); 
    }

    function try_setSwapOutRequired(uint256 swapAmt) external returns (bool ok) { 
        string memory sig = "setSwapOutRequired(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, swapAmt)); 
    }

    function try_setUnstakeDelay(uint256 delay) external returns (bool ok) { 
        string memory sig = "setUnstakeDelay(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, delay)); 
    }

    function try_setGovernor(address gov) external returns (bool ok) { 
        string memory sig = "setGovernor(address)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, gov)); 
    }

    function try_setPriceOracle(address asset, address oracle) external returns (bool ok) { 
        string memory sig = "setPriceOracle(address,address)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, asset, oracle)); 
    }

    function try_passThroughFundsToken(address trs) external returns (bool ok) { 
        string memory sig = "passThroughFundsToken()";
        (ok,) = address(trs).call(abi.encodeWithSignature(sig)); 
    }

    function try_setMaxSwapSlippage(uint256 newSlippage) external returns (bool ok) { 
        string memory sig = "setMaxSwapSlippage(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, newSlippage)); 
    }
    
    /*** StakingRewards Setters ***/ 
    function try_notifyRewardAmount(uint256 reward) external returns (bool ok) { 
        string memory sig = "notifyRewardAmount(uint256)";
        (ok,) = address(stakingRewards).call(abi.encodeWithSignature(sig, reward)); 
    }
    function try_updatePeriodFinish(uint256 timestamp) external returns (bool ok) { 
        string memory sig = "updatePeriodFinish(uint256)";
        (ok,) = address(stakingRewards).call(abi.encodeWithSignature(sig, timestamp)); 
    }
    function try_recoverERC20(address asset, uint256 amt) external returns (bool ok) { 
        string memory sig = "recoverERC20(address,uint256)";
        (ok,) = address(stakingRewards).call(abi.encodeWithSignature(sig, asset, amt)); 
    }
    function try_setRewardsDuration(uint256 duration) external returns (bool ok) { 
        string memory sig = "setRewardsDuration(uint256)";
        (ok,) = address(stakingRewards).call(abi.encodeWithSignature(sig, duration)); 
    }
    function try_setPaused(bool paused) external returns (bool ok) { 
        string memory sig = "setPaused(bool)";
        (ok,) = address(stakingRewards).call(abi.encodeWithSignature(sig, paused)); 
    }
}
