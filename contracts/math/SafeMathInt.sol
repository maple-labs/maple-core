// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

library SafeMathInt {
    function toUint256Safe(int256 a) internal pure returns (uint256) {
        require(a >= 0);
        return uint256(a);
    }
}
