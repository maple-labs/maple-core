// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

contract EmergencyAdmin {
   function try_setProtocolPause(address globals, bool pause) external returns (bool ok) {
        string memory sig = "setProtocolPause(bool)";
        (ok,) = globals.call(abi.encodeWithSignature(sig, pause));
    }
}
