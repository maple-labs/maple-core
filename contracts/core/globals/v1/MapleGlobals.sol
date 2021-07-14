// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { SafeMath } from "../../../../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";

import { IERC20Details } from "../../../external-interfaces/IERC20Details.sol";

import { ICalc }       from "../../calculator/v1/interfaces/ICalc.sol";
import { IOracle }     from "../../oracle/v1/interfaces/IOracle.sol";
import { ISubFactory } from "../../subfactory/v1/interfaces/ISubFactory.sol";

import { IMapleGlobals } from "./interfaces/IMapleGlobals.sol";

/// @title MapleGlobals maintains a central source of parameters and allowlists for the Maple protocol.
contract MapleGlobals is IMapleGlobals {

    using SafeMath for uint256;

    address public override immutable mpl;

    address public override pendingGovernor;
    address public override governor;
    address public override mapleTreasury;
    address public override globalAdmin;

    uint256 public override defaultGracePeriod;
    uint256 public override swapOutRequired;
    uint256 public override fundingPeriod;
    uint256 public override investorFee;
    uint256 public override treasuryFee;
    uint256 public override maxSwapSlippage;
    uint256 public override minLoanEquity;
    uint256 public override stakerCooldownPeriod;
    uint256 public override lpCooldownPeriod;
    uint256 public override stakerUnstakeWindow;
    uint256 public override lpWithdrawWindow;

    bool public override protocolPaused;

    mapping(address => bool) public override isValidLiquidityAsset;
    mapping(address => bool) public override isValidCollateralAsset;
    mapping(address => bool) public override validCalcs;
    mapping(address => bool) public override isValidPoolDelegate;
    mapping(address => bool) public override isValidBalancerPool;

    mapping(address => mapping(address => address)) public override defaultUniswapPath;

    mapping(address => address) public override oracleFor;

    mapping(address => bool)                     public override isValidPoolFactory;
    mapping(address => bool)                     public override isValidLoanFactory;
    mapping(address => mapping(address => bool)) public override validSubFactories;

    /**
        @dev Checks that `msg.sender` is the Governor.
     */
    modifier isGovernor() {
        require(msg.sender == governor, "MG:NOT_GOV");
        _;
    }

    /**
        @dev   Constructor function. 
        @dev   It emits an `Initialized` event. 
        @param _governor    Address of Governor.
        @param _mpl         Address of the ERC-2222 Maple Token for the Maple protocol.
        @param _globalAdmin Address the Global Admin.
     */
    constructor(address _governor, address _mpl, address _globalAdmin) public {
        governor             = _governor;
        mpl                  = _mpl;
        swapOutRequired      = 10_000;     // $10,000 of Pool cover
        fundingPeriod        = 10 days;
        defaultGracePeriod   = 5 days;
        investorFee          = 50;         // 0.5 %
        treasuryFee          = 50;         // 0.5 %
        maxSwapSlippage      = 1000;       // 10 %
        minLoanEquity        = 2000;       // 20 %
        globalAdmin          = _globalAdmin;
        stakerCooldownPeriod = 10 days;
        lpCooldownPeriod     = 10 days;
        stakerUnstakeWindow  = 2 days;
        lpWithdrawWindow     = 2 days;
        emit Initialized();
    }

    /************************/
    /*** Setter Functions ***/
    /************************/

    function setStakerCooldownPeriod(uint256 newCooldownPeriod) external override isGovernor {
        stakerCooldownPeriod = newCooldownPeriod;
        emit GlobalsParamSet("STAKER_COOLDOWN_PERIOD", newCooldownPeriod);
    }

    function setLpCooldownPeriod(uint256 newCooldownPeriod) external override isGovernor {
        lpCooldownPeriod = newCooldownPeriod;
        emit GlobalsParamSet("LP_COOLDOWN_PERIOD", newCooldownPeriod);
    }

    function setStakerUnstakeWindow(uint256 newUnstakeWindow) external override isGovernor {
        stakerUnstakeWindow = newUnstakeWindow;
        emit GlobalsParamSet("STAKER_UNSTAKE_WINDOW", newUnstakeWindow);
    }

    function setLpWithdrawWindow(uint256 newLpWithdrawWindow) external override isGovernor {
        lpWithdrawWindow = newLpWithdrawWindow;
        emit GlobalsParamSet("LP_WITHDRAW_WINDOW", newLpWithdrawWindow);
    }

    function setMaxSwapSlippage(uint256 newMaxSlippage) external override isGovernor {
        _checkPercentageRange(newMaxSlippage);
        maxSwapSlippage = newMaxSlippage;
        emit GlobalsParamSet("MAX_SWAP_SLIPPAGE", newMaxSlippage);
    }

    function setGlobalAdmin(address newGlobalAdmin) external override {
        require(msg.sender == governor && newGlobalAdmin != address(0), "MG:NOT_GOV_OR_ADMIN");
        require(!protocolPaused, "MG:PROTO_PAUSED");
        globalAdmin = newGlobalAdmin;
        emit GlobalAdminSet(newGlobalAdmin);
    }

    function setValidBalancerPool(address balancerPool, bool valid) external override isGovernor {
        isValidBalancerPool[balancerPool] = valid;
        emit BalancerPoolSet(balancerPool, valid);
    }

    function setProtocolPause(bool pause) external override {
        require(msg.sender == globalAdmin, "MG:NOT_ADMIN");
        protocolPaused = pause;
        emit ProtocolPaused(pause);
    }

    function setValidPoolFactory(address poolFactory, bool valid) external override isGovernor {
        isValidPoolFactory[poolFactory] = valid;
    }

    function setValidLoanFactory(address loanFactory, bool valid) external override isGovernor {
        isValidLoanFactory[loanFactory] = valid;
    }

    function setValidSubFactory(address superFactory, address subFactory, bool valid) external override isGovernor {
        require(isValidLoanFactory[superFactory] || isValidPoolFactory[superFactory], "MG:INVALID_SUPER_F");
        validSubFactories[superFactory][subFactory] = valid;
    }

    function setDefaultUniswapPath(address from, address to, address mid) external override isGovernor {
        defaultUniswapPath[from][to] = mid;
    }

    function setPoolDelegateAllowlist(address delegate, bool valid) external override isGovernor {
        isValidPoolDelegate[delegate] = valid;
        emit PoolDelegateSet(delegate, valid);
    }

    function setCollateralAsset(address asset, bool valid) external override isGovernor {
        isValidCollateralAsset[asset] = valid;
        emit CollateralAssetSet(asset, IERC20Details(asset).decimals(), IERC20Details(asset).symbol(), valid);
    }

    function setLiquidityAsset(address asset, bool valid) external override isGovernor {
        isValidLiquidityAsset[asset] = valid;
        emit LiquidityAssetSet(asset, IERC20Details(asset).decimals(), IERC20Details(asset).symbol(), valid);
    }

    function setCalc(address calc, bool valid) external override isGovernor {
        validCalcs[calc] = valid;
    }

    function setInvestorFee(uint256 _fee) external override isGovernor {
        _checkPercentageRange(treasuryFee.add(_fee));
        investorFee = _fee;
        emit GlobalsParamSet("INVESTOR_FEE", _fee);
    }

    function setTreasuryFee(uint256 _fee) external override isGovernor {
        _checkPercentageRange(investorFee.add(_fee));
        treasuryFee = _fee;
        emit GlobalsParamSet("TREASURY_FEE", _fee);
    }

    function setMapleTreasury(address _mapleTreasury) external override isGovernor {
        require(_mapleTreasury != address(0), "MG:ZERO_ADDR");
        mapleTreasury = _mapleTreasury;
        emit GlobalsAddressSet("MAPLE_TREASURY", _mapleTreasury);
    }

    function setDefaultGracePeriod(uint256 _defaultGracePeriod) external override isGovernor {
        defaultGracePeriod = _defaultGracePeriod;
        emit GlobalsParamSet("DEFAULT_GRACE_PERIOD", _defaultGracePeriod);
    }

    function setMinLoanEquity(uint256 _minLoanEquity) external override isGovernor {
        _checkPercentageRange(_minLoanEquity);
        minLoanEquity = _minLoanEquity;
        emit GlobalsParamSet("MIN_LOAN_EQUITY", _minLoanEquity);
    }

    function setFundingPeriod(uint256 _fundingPeriod) external override isGovernor {
        fundingPeriod = _fundingPeriod;
        emit GlobalsParamSet("FUNDING_PERIOD", _fundingPeriod);
    }

    function setSwapOutRequired(uint256 amt) external override isGovernor {
        require(amt >= uint256(10_000), "MG:SWAP_OUT_TOO_LOW");
        swapOutRequired = amt;
        emit GlobalsParamSet("SWAP_OUT_REQUIRED", amt);
    }

    function setPriceOracle(address asset, address oracle) external override isGovernor {
        oracleFor[asset] = oracle;
        emit OracleSet(asset, oracle);
    }

    /************************************/
    /*** Transfer Ownership Functions ***/
    /************************************/

    function setPendingGovernor(address _pendingGovernor) external override isGovernor {
        require(_pendingGovernor != address(0), "MG:ZERO_ADDR");
        pendingGovernor = _pendingGovernor;
        emit PendingGovernorSet(_pendingGovernor);
    }

    function acceptGovernor() external override {
        require(msg.sender == pendingGovernor, "MG:NOT_PENDING_GOV");
        governor        = msg.sender;
        pendingGovernor = address(0);
        emit GovernorAccepted(msg.sender);
    }

    /************************/
    /*** Getter Functions ***/
    /************************/

    function getLatestPrice(address asset) external override view returns (uint256) {
        return uint256(IOracle(oracleFor[asset]).getLatestPrice());
    }

    function isValidSubFactory(address superFactory, address subFactory, uint8 factoryType) external override view returns (bool) {
        return validSubFactories[superFactory][subFactory] && ISubFactory(subFactory).factoryType() == factoryType;
    }

    function isValidCalc(address calc, uint8 calcType) external override view returns (bool) {
        return validCalcs[calc] && ICalc(calc).calcType() == calcType;
    }

    function getLpCooldownParams() external override view returns (uint256, uint256) {
        return (lpCooldownPeriod, lpWithdrawWindow);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
        @dev Checks that percentage is less than 100%.
     */
    function _checkPercentageRange(uint256 percentage) internal pure {
        require(percentage <= uint256(10_000), "MG:PCT_OOB");
    }

}
