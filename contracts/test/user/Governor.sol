// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { MapleGlobals } from "../../core/globals/v1/MapleGlobals.sol";
import { MplRewards } from "../../core/mpl-rewards/v1/MplRewards.sol";
import { MplRewardsFactory } from "../../core/mpl-rewards/v1/MplRewardsFactory.sol";
import { MapleTreasury } from "../../core/treasury/v1/MapleTreasury.sol";

contract Governor {

    /************************/
    /*** DIRECT FUNCTIONS ***/
    /************************/

    MapleGlobals      globals;
    MplRewards        mplRewards;
    MplRewardsFactory mplRewardsFactory;
    MapleTreasury     treasury;

    function createGlobals(address mpl) external returns (MapleGlobals) {
        globals = new MapleGlobals(address(this), mpl, address(1));
        return globals;
    }

    function createMplRewardsFactory() external returns (MplRewardsFactory) {
        mplRewardsFactory = new MplRewardsFactory(address(globals));
        return mplRewardsFactory;
    }

    function createMplRewards(address mpl, address pool) external returns (MplRewards) {
        mplRewards = MplRewards(mplRewardsFactory.createMplRewards(mpl, pool));
        return mplRewards;
    }

    // Used for "fake" governors pointing at a globals contract they didn't create
    function setGovGlobals(MapleGlobals _globals) external {
        globals = _globals;
    }

    function setGovMplRewardsFactory(MplRewardsFactory _mplRewardsFactory) external {
        mplRewardsFactory = _mplRewardsFactory;
    }

    // Used for "fake" governors pointing at a staking rewards contract they don't own
    function setGovMplRewards(MplRewards _mplRewards) external {
        mplRewards = _mplRewards;
    }

    // Used for "fake" governors pointing at a treasury contract they didn't create
    function setGovTreasury(MapleTreasury _treasury) external {
        treasury = _treasury;
    }

    function transfer(IERC20 token, address account, uint256 amt) external {
        token.transfer(account, amt);
    }

    /*** MapleGlobals Setters ***/
    function setCalc(address calc, bool valid)                                 external { globals.setCalc(calc, valid); }
    function setCollateralAsset(address asset, bool valid)                     external { globals.setCollateralAsset(asset, valid); }
    function setLiquidityAsset(address asset, bool valid)                      external { globals.setLiquidityAsset(asset, valid); }
    function setValidLoanFactory(address factory, bool valid)                  external { globals.setValidLoanFactory(factory, valid); }
    function setValidPoolFactory(address factory, bool valid)                  external { globals.setValidPoolFactory(factory, valid); }
    function setValidSubFactory(address fac, address sub, bool valid)          external { globals.setValidSubFactory(fac, sub, valid); }
    function setMapleTreasury(address _treasury)                               external { globals.setMapleTreasury(_treasury); }
    function setGlobalAdmin(address _globalAdmin)                              external { globals.setGlobalAdmin(_globalAdmin); }
    function setPoolDelegateAllowlist(address pd, bool valid)                  external { globals.setPoolDelegateAllowlist(pd, valid); }
    function setInvestorFee(uint256 fee)                                       external { globals.setInvestorFee(fee); }
    function setTreasuryFee(uint256 fee)                                       external { globals.setTreasuryFee(fee); }
    function setDefaultGracePeriod(uint256 period)                             external { globals.setDefaultGracePeriod(period); }
    function setFundingPeriod(uint256 period)                                  external { globals.setFundingPeriod(period); }
    function setSwapOutRequired(uint256 swapAmt)                               external { globals.setSwapOutRequired(swapAmt); }
    function setPendingGovernor(address gov)                                   external { globals.setPendingGovernor(gov); }
    function acceptGovernor()                                                  external { globals.acceptGovernor(); }
    function setPriceOracle(address asset, address oracle)                     external { globals.setPriceOracle(asset, oracle); }
    function setMaxSwapSlippage(uint256 newSlippage)                           external { globals.setMaxSwapSlippage(newSlippage); }
    function setDefaultUniswapPath(address from, address to, address mid)      external { globals.setDefaultUniswapPath(from, to, mid); }
    function setValidBalancerPool(address balancerPool, bool valid)            external { globals.setValidBalancerPool(balancerPool, valid); }
    function setLpCooldownPeriod(uint256 period)                               external { globals.setLpCooldownPeriod(period); }
    function setStakerCooldownPeriod(uint256 period)                           external { globals.setStakerCooldownPeriod(period); }
    function setLpWithdrawWindow(uint256 period)                               external { globals.setLpWithdrawWindow(period); }
    function setStakerUnstakeWindow(uint256 period)                            external { globals.setStakerUnstakeWindow(period); }

    /*** MapleTreasury Functions ***/
    function setGlobals(address newGlobals)              external { treasury.setGlobals(newGlobals); }
    function reclaimERC20(address asset, uint256 amount) external { treasury.reclaimERC20(asset, amount); }
    function distributeToHolders()                       external { treasury.distributeToHolders(); }
    function convertERC20(address asset)                 external { treasury.convertERC20(asset); }

    /*** MplRewards Setters ***/
    function transferOwnership(address newOwner)      external { mplRewards.transferOwnership(newOwner); }
    function notifyRewardAmount(uint256 reward)       external { mplRewards.notifyRewardAmount(reward); }
    function updatePeriodFinish(uint256 timestamp)    external { mplRewards.updatePeriodFinish(timestamp); }
    function recoverERC20(address asset, uint256 amt) external { mplRewards.recoverERC20(asset, amt); }
    function setRewardsDuration(uint256 duration)     external { mplRewards.setRewardsDuration(duration); }
    function setPaused(bool paused)                   external { mplRewards.setPaused(paused); }


    /*********************/
    /*** TRY FUNCTIONS ***/
    /*********************/

    /*** MapleGlobals Setters ***/
    function try_setGlobals(address target, address _globals) external returns (bool ok) {
        string memory sig = "setGlobals(address)";
        (ok,) = address(target).call(abi.encodeWithSignature(sig, _globals));
    }
    function try_createMplRewards(address mpl, address pool) external returns (bool ok) {
        string memory sig = "createMplRewards(address,address)";
        (ok,) = address(mplRewardsFactory).call(abi.encodeWithSignature(sig, mpl, pool));
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
    function try_setLiquidityAsset(address asset, bool valid) external returns (bool ok) {
        string memory sig = "setLiquidityAsset(address,bool)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, asset, valid));
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
    function try_setMapleTreasury(address _treasury) external returns (bool ok) {
        string memory sig = "setMapleTreasury(address)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, _treasury));
    }
    function try_setPoolDelegateAllowlist(address pd, bool valid) external returns (bool ok) {
        string memory sig = "setPoolDelegateAllowlist(address,bool)";
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
    function try_setDefaultGracePeriod(uint256 defaultGracePeriod) external returns (bool ok) {
        string memory sig = "setDefaultGracePeriod(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, defaultGracePeriod));
    }
    function try_setFundingPeriod(uint256 fundingPeriod) external returns (bool ok) {
        string memory sig = "setFundingPeriod(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, fundingPeriod));
    }
    function try_setSwapOutRequired(uint256 swapAmt) external returns (bool ok) {
        string memory sig = "setSwapOutRequired(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, swapAmt));
    }
    function try_setPendingGovernor(address pendingGov) external returns (bool ok) {
        string memory sig = "setPendingGovernor(address)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, pendingGov));
    }
    function try_acceptGovernor() external returns (bool ok) {
        string memory sig = "acceptGovernor()";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig));
    }
    function try_setPriceOracle(address asset, address oracle) external returns (bool ok) {
        string memory sig = "setPriceOracle(address,address)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, asset, oracle));
    }
    function try_setMaxSwapSlippage(uint256 newSlippage) external returns (bool ok) {
        string memory sig = "setMaxSwapSlippage(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, newSlippage));
    }
    function try_setValidBalancerPool(address balancerPool, bool valid) external returns (bool ok) {
        string memory sig = "setValidBalancerPool(address,bool)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, balancerPool, valid));
    }
    function try_setMinLoanEquity(uint256 newLiquidity) external returns (bool ok) {
        string memory sig = "setMinLoanEquity(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, newLiquidity));
    }
    function try_setLpCooldownPeriod(uint256 period) external returns (bool ok) {
        string memory sig = "setLpCooldownPeriod(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, period));
    }
    function try_setStakerCooldownPeriod(uint256 period) external returns (bool ok) {
        string memory sig = "setStakerCooldownPeriod(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, period));
    }
    function try_setLpWithdrawWindow(uint256 period) external returns (bool ok) {
        string memory sig = "setLpWithdrawWindow(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, period));
    }
    function try_setStakerUnstakeWindow(uint256 period) external returns (bool ok) {
        string memory sig = "setStakerUnstakeWindow(uint256)";
        (ok,) = address(globals).call(abi.encodeWithSignature(sig, period));
    }

    /*** MplRewards Setters ***/
    function try_transferOwnership(address newOwner) external returns (bool ok) {
        string memory sig = "transferOwnership(address)";
        (ok,) = address(mplRewards).call(abi.encodeWithSignature(sig, newOwner));
    }
    function try_notifyRewardAmount(uint256 reward) external returns (bool ok) {
        string memory sig = "notifyRewardAmount(uint256)";
        (ok,) = address(mplRewards).call(abi.encodeWithSignature(sig, reward));
    }
    function try_updatePeriodFinish(uint256 timestamp) external returns (bool ok) {
        string memory sig = "updatePeriodFinish(uint256)";
        (ok,) = address(mplRewards).call(abi.encodeWithSignature(sig, timestamp));
    }
    function try_recoverERC20(address asset, uint256 amt) external returns (bool ok) {
        string memory sig = "recoverERC20(address,uint256)";
        (ok,) = address(mplRewards).call(abi.encodeWithSignature(sig, asset, amt));
    }
    function try_setRewardsDuration(uint256 duration) external returns (bool ok) {
        string memory sig = "setRewardsDuration(uint256)";
        (ok,) = address(mplRewards).call(abi.encodeWithSignature(sig, duration));
    }
    function try_setPaused(bool paused) external returns (bool ok) {
        string memory sig = "setPaused(bool)";
        (ok,) = address(mplRewards).call(abi.encodeWithSignature(sig, paused));
    }

    /*** Treasury Functions ***/
    function try_setGlobals(address newGlobals) external returns (bool ok) {
        string memory sig = "setGlobals(address)";
        (ok,) = address(treasury).call(abi.encodeWithSignature(sig, newGlobals));
    }
    function try_reclaimERC20_treasury(address asset, uint256 amount) external returns (bool ok) {
        string memory sig = "reclaimERC20(address,uint256)";
        (ok,) = address(treasury).call(abi.encodeWithSignature(sig, asset, amount));
    }
    function try_distributeToHolders() external returns (bool ok) {
        string memory sig = "distributeToHolders()";
        (ok,) = address(treasury).call(abi.encodeWithSignature(sig));
    }
    function try_convertERC20(address asset) external returns (bool ok) {
        string memory sig = "convertERC20(address)";
        (ok,) = address(treasury).call(abi.encodeWithSignature(sig, asset));
    }

    /*** Pool Functions ***/
    function try_reclaimERC20(address target, address token) external returns (bool ok) {
        string memory sig = "reclaimERC20(address)";
        (ok,) = target.call(abi.encodeWithSignature(sig, token));
    }

    /*** PoolFactory/LoanFactory Functions ***/
    function try_pause(address target) external returns (bool ok) {
        string memory sig = "pause()";
        (ok,) = target.call(abi.encodeWithSignature(sig));
    }
    function try_unpause(address target) external returns (bool ok) {
        string memory sig = "unpause()";
        (ok,) = target.call(abi.encodeWithSignature(sig));
    }

}
