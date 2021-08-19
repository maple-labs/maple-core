// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.6.11;

import { IERC20 } from "../../../modules/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract ERC20User {

    /************************/
    /*** Direct Functions ***/
    /************************/

    function erc20_approve(address token, address spender, uint256 amount) external {
        IERC20(token).approve(spender, amount);
    }

    function erc20_transfer(address token, address recipient, uint256 amount) external {
        IERC20(token).transfer(recipient, amount);
    }

    function erc20_transferFrom(address token, address owner, address recipient, uint256 amount) external {
        IERC20(token).transferFrom(owner, recipient, amount);
    }

    /*********************/
    /*** Try Functions ***/
    /*********************/

    function try_erc20_approve(address token, address spender, uint256 amount) external returns (bool ok) {
        (ok,) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
    }

    function try_erc20_transfer(address token, address recipient, uint256 amount) external returns (bool ok) {
        (ok,) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, recipient, amount));
    }

    function try_erc20_transferFrom(address token, address owner, address recipient, uint256 amount) external returns (bool ok) {
        (ok,) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, owner, recipient, amount));
    }

}
