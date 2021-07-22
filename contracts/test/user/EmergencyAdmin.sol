// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { IMapleGlobals } from "../../core/globals/contracts/interfaces/IMapleGlobals.sol";

contract EmergencyAdmin {

    function try_setProtocolPause(address globals, bool pause) external returns (bool ok) {
        string memory sig = "setProtocolPause(bool)";
        (ok,) = globals.call(abi.encodeWithSignature(sig, pause));
    }

    function setProtocolPause(IMapleGlobals globals, bool pause) external {
        globals.setProtocolPause(pause);
    }

}
