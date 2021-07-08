// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import "../../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IERC20Details is IERC20 {

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint256);

}
