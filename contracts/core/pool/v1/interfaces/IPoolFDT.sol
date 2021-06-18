// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "core/funds-distribution-token/v1/interfaces/IExtendedFDT.sol";

interface IPoolFDT is IExtendedFDT {

    function interestSum() external view returns (uint256);

    function poolLosses() external view returns (uint256);

    function interestBalance() external view returns (uint256);

    function lossesBalance() external view returns (uint256);

}
