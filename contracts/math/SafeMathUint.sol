// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

library SafeMathUint {
    function toInt256Safe(uint256 a) internal pure returns (int256) {
        int256 b = int256(a);
        require(b >= 0, "SMU:INVALID_VALUE");
        return b;
    }
}
