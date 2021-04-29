// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "./IBasicFDT.sol";

interface ILoanFDT is IBasicFDT {
    function fundsToken() external view returns (address);

    function fundsTokenBalance() external view returns (uint256);
}
