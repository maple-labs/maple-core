// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { ILoan } from "../../../modules/loan/contracts/interfaces/ILoan.sol";

contract Explorer {

    function try_loan_triggerDefault(address loan) external returns (bool ok) {
        (ok,) = loan.call(abi.encodeWithSelector(ILoan.triggerDefault.selector));
    }

}
