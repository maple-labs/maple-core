// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "../../../..//custodial-ownership-token/v1/interfaces/IERC2258.sol";

interface IStakeToken is IERC2258 {
    function balanceOf  (address who)  external view returns(uint256);
    function stakeDate  (address whom) external view returns(uint256);
    function depositDate(address whom) external view returns(uint256);
}
