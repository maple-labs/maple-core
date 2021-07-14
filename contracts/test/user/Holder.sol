// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { IBasicFDT } from "../../core/funds-distribution-token/v1/interfaces/IBasicFDT.sol";

contract Holder {

    function withdrawFunds(address token) external {
        IBasicFDT(token).withdrawFunds();
    }

}
