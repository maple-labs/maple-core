//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.8;

import "@nomiclabs/buidler/console.sol";

contract Config {
    /**
        @notice The public Greeting
    */

    string public greeting;

    constructor(string memory _greeting) public {
        console.log("Deploying a Greeter with greeting:", _greeting);
        greeting = _greeting;
    }
}
