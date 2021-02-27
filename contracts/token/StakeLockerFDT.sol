// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;

import "./ExtendedFDT.sol";

abstract contract StakeLockerFDT is ExtendedFDT {
    using SafeMath       for uint256;
    using SafeMathUint   for uint256;
    using SignedSafeMath for  int256;
    using SafeMathInt    for  int256;

    IERC20 public immutable fundsToken;

    constructor(string memory name, string memory symbol, address fundsToken) ExtendedFDT(name, symbol) public {
        fundsToken = IERC20(fundsToken);
     }

}
