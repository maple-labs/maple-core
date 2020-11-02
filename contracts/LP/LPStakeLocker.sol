// SPDX-License-Identifier: MIT

pragma solidity 0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../Token/IFundsDistributionToken.sol";
import "../Token/FundsDistributionToken.sol";

contract LPStakeLocker is IFundsDistributionToken, FundsDistributionToken {
    using SafeMathInt for int256;
    using SignedSafeMath for int256;

    // token in which the funds/dividends can be sent for the FundsDistributionToken
    IERC20 private IliquidAsset; //private if it doesnt need to be public to save gas

    uint256 public liquidTokenBalance;
    
    address stakedAsset;
    address liquidAsset;

    constructor(address _stakedAsset, address _liquidAsset)
        public
        FundsDistributionToken("Maple Stake Locker", "MPLSTAKE")
    {
        liquidAsset = _liquidAsset;
        stakedAsset = _stakedAsset;
        IliquidAsset = IERC20(_liquidAsset);
    }

	/**
	 * @notice Withdraws all available funds for a token holder
	 */
    function withdrawFunds() external override {
        uint256 withdrawableFunds = _prepareWithdraw();

        require(
            IliquidAsset.transfer(msg.sender, withdrawableFunds),
            "FDT_ERC20Extension.withdrawFunds: TRANSFER_FAILED"
        );

        _updateIliquidAssetBalance();
    }

    /**
     * @dev Updates the current funds token balance
     * and returns the difference of new and previous funds token balances
     * @return A int256 representing the difference of the new and previous funds token balance
     */
    function _updateIliquidAssetBalance() internal returns (int256) {
        uint256 prevIliquidAssetBalance = liquidTokenBalance;

        liquidTokenBalance = IliquidAsset.balanceOf(address(this));

        return int256(liquidTokenBalance).sub(int256(prevIliquidAssetBalance));
    }

    /**
     * @notice Register a payment of funds in tokens. May be called directly after a deposit is made.
     * @dev Calls _updateIliquidAssetBalance(), whereby the contract computes the delta of the previous and the new
     * funds token balance and increments the total received funds (cumulative) by delta by calling _registerFunds()
     */
}