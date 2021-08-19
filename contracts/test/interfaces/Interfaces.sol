// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IERC20 } from "../../../modules/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IBFactoryLike {

    function isBPool(address) external view returns (bool);

    function newBPool() external returns (address);

}

interface IBPoolLike is IERC20 {

    function bind(address, uint256, uint256) external;

    function finalize() external;

}
