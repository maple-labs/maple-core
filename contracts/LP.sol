// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../Token/IFundsDistributionToken.sol";
import "../Token/FundsDistributionToken.sol";
import "../Math/CalcBPool.sol";
import "../interface/IBPool.sol";

/// @title IMapleGlobals interacts with the core MapleGlobals.sol contract.
interface IMapleGlobals {
    function mapleToken() external view returns (address);
}

/// @title ILPStakeLockerFactory is responsbile for instantiating/initializing a staked asset locker.
interface ILPStakeLockerFactory {
    function newLocker(address _stakedAsset, address _liquidAsset) external returns (address);
}

/// @title ILPStakeLocker interfaces with the staked asset locker of the liquidity pool.
interface ILPStakeLocker {
    function stake(uint256 _amountStakedAsset) external returns (uint256);
    function unstake(uint256 _amountStakedAsset) external returns (uint256);
    function withdrawUnstaked(uint256 _amountUnstaked) external returns (uint256);
    function withdrawInterest() external returns (uint256);
}

/// @title LP is the core liquidity pool contract.
contract LP is IFundsDistributionToken, FundsDistributionToken {

    using SafeMathInt for int256;
    using SignedSafeMath for int256;
    using SafeMath for uint256;

    // The dividend token for this contract's FundsDistributionToken.
    IERC20 private ILiquidAsset;

    // The factory for instantiating staked asset lockers.
    ILPStakeLockerFactory private ILockerFactory;

    // The staked asset for this liquidity pool (the Balancer Pool).
    IERC20 private IStakedAsset;

    // The staked asset locker which escrows the staked asset.
    ILPStakeLocker private IStakedAssetLocker;

    // The maple globals contract.
    IMapleGlobals private MapleGlobals;

    /// @notice The amount of LiquidAsset tokens (dividends) currently present and accounted for in this contract. 
    uint256 public liquidTokenBalance;

    /// @notice Represents the fees, in basis points, distributed to the lender when a borrower's loan is funded.
    uint256 public stakerFeeBasisPoints;
    
    /// @notice Represents the fees, in basis points, distributed to the MapleToken when a borrower's loan is funded.
    uint256 public ongoingFeeBasisPoints;

    /// @notice The asset deposited by lenders into the liquidAssetLocker, for funding loans.
    address public liquidAsset;

    /// @notice The asset deposited by stakers into the stakedAssetLocker, for liquidation during defaults.
    address public stakedAsset;

    /// @notice The address of the staked asset locker, escrowing the staked asset.
    address public stakedAssetLocker; //supports 8 for fixed memory

    /// @notice The pool delegate which has full authority over the liquidity pool and investment decisions.
    address public poolDelegate;

    /// TODO: Remove this, move this to globals.
    uint256 public minStake = 100;//min stake in usd/usdc/dai SHOULD BE IN GLOBALS!!!!

    // TODO: What is this? Remove?
    uint tokenOne;

    constructor (
        address _liquidAsset,
        address _stakedAsset,
        address _stakedAssetLockerFactory,
        string memory name,
        string memory symbol,
        address _mapleGlobals
    )
        FundsDistributionToken(name, symbol)
    {
        require(
            address(_liquidAsset) != address(0),
            "FDT_ERC20Extension: INVALID_FUNDS_TOKEN_ADDRESS"
        );

        liquidAsset = _liquidAsset;
        stakedAsset = _stakedAsset;
        ILiquidAsset = IERC20(_liquidAsset);
        ILockerFactory = ILPStakeLockerFactory(_stakedAssetLockerFactory);
        MapleGlobals = IMapleGlobals(_mapleGlobals);
        poolDelegate = tx.origin;
        tokenOne = 10**ERC20(liquidAsset).decimals(); // What is this? tokenOne?
        makeStakeLocker(_stakedAsset);

        // TODO: Put the BPTs in the stake lockers?
    }

    function makeStakeLocker(address _stakedAsset) private {
        require(
            IBPool(_stakedAsset).isBound(MapleGlobals.mapleToken()) &&
                IBPool(_stakedAsset).isBound(liquidAsset) &&
                IBPool(_stakedAsset).isFinalized() &&
                (IBPool(_stakedAsset).getNumTokens() == 2),
            "FDT_LP.makeStakeLocker: BALANCER_POOL_NOT_VALID"
        );
        //this is to test the function but needs to be changed to be applied to the delegate's stake in the locker
        require(CalcBPool.BPTVal(_stakedAsset,poolDelegate,liquidAsset) > minStake.mul(tokenOne), "FDT_LP.makeStakeLocker: NOT_ENOUGH_STAKE");
        stakedAssetLocker = ILockerFactory.newLocker(
            _stakedAsset,
            liquidAsset
        );
    }

    /**
     * @notice Withdraws all available funds for a token holder
     */
    function withdrawFunds() external override {
        uint256 withdrawableFunds = _prepareWithdraw();

        require(
            ILiquidAsset.transfer(msg.sender, withdrawableFunds),
            "FDT_ERC20Extension.withdrawFunds: TRANSFER_FAILED"
        );

        _updateILiquidAssetBalance();
    }

    /**
     * @dev Updates the current funds token balance
     * and returns the difference of new and previous funds token balances
     * @return A int256 representing the difference of the new and previous funds token balance
     */
    function _updateILiquidAssetBalance() internal returns (int256) {
        uint256 prevILiquidAssetBalance = liquidTokenBalance;

        liquidTokenBalance = ILiquidAsset.balanceOf(address(this));

        return int256(liquidTokenBalance).sub(int256(prevILiquidAssetBalance));
    }

    /**
     * @notice Register a payment of funds in tokens. May be called directly after a deposit is made.
     * @dev Calls _updateILiquidAssetBalance(), whereby the contract computes the delta of the previous and the new
     * funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
     */
    function updateFundsReceived() external {
        int256 newFunds = _updateILiquidAssetBalance();

        if (newFunds > 0) {
            _distributeFunds(newFunds.toUint256Safe());
        }
    }
}
