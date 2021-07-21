// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IERC20, SafeERC20 } from "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";
import { Initializable }     from "../../../../lib/openzeppelin-contracts/contracts/proxy/Initializable.sol";

import { BasicFDTUpgradeable, SignedSafeMath } from "../../funds-distribution-token/v1/BasicFDTUpgradeable.sol";

import { IBasicFundsTokenFDT } from "./interfaces/IBasicFundsTokenFDT.sol";

/// @title BasicFundsTokenFDT implements the Basic FDT functionality with a separate Funds Token.
abstract contract BasicFundsTokenFDTUpgradeable is Initializable, IBasicFundsTokenFDT, BasicFDTUpgradeable {

    using SafeERC20      for  IERC20;
    using SignedSafeMath for  int256;

    IERC20 public override immutable fundsToken;

    uint256 public override fundsTokenBalance;

    function _basicFundsTokenFDTUpgradeable_initialize(string memory name, string memory symbol, address _fundsToken) internal initializer {
        _basicFDTUpgradeable_initialize(name, symbol);
        fundsToken = IERC20(_fundsToken);
    }

    function withdrawFunds() public virtual override(IBasicFundsTokenFDT, BasicFDTUpgradeable) {
        uint256 withdrawableFunds = _prepareWithdraw();

        if (withdrawableFunds > uint256(0)) {
            fundsToken.safeTransfer(msg.sender, withdrawableFunds);

            _updateFundsTokenBalance();
        }
    }

    /**
        @dev    Updates the current `fundsToken` balance and returns the difference of the new and previous `fundsToken` balance.
        @return A int256 representing the difference of the new and previous `fundsToken` balance.
     */
    function _updateFundsTokenBalance() internal virtual override returns (int256) {
        uint256 _prevFundsTokenBalance = fundsTokenBalance;

        fundsTokenBalance = fundsToken.balanceOf(address(this));

        return int256(fundsTokenBalance).sub(int256(_prevFundsTokenBalance));
    }

}
