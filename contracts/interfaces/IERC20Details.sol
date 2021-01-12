// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

interface IERC20Details {
    function name()   external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint256);
}
