// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.6.11;

import { IERC2258 } from "../../interfaces/IERC2258.sol";

contract ERC2258Account {

    function erc2258_increaseCustodyAllowance(address token, address custodian, uint256 amount) external {
        IERC2258(token).increaseCustodyAllowance(custodian, amount);
    }

    function try_erc2258_increaseCustodyAllowance(address token, address custodian, uint256 amount) external returns (bool ok) {
        (ok,) = token.call(abi.encodeWithSignature("increaseCustodyAllowance(address,uint256)", custodian, amount));
    }

}
