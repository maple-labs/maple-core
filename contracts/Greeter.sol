//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.0;

import "@nomiclabs/buidler/console.sol";

/// @author Maple
/// @title Greeter Contract
contract Greeter {

    /// @notice The greeting value.
    string public greeting;

    /// @notice This is an event description here.
    /// @param _greetings The greetings value.
    /// @param _timestamp The time of greeting.
    event Greeted (
        string _greetings,
        uint _timestamp
    );

    /**  
        @notice This is a description for the constructor function
        @param _greeting the value of the greeting.
        @param _value The value of the value.
    */
    constructor(string memory _greeting, uint _value) public {
        console.log("Deploying a Greeter with greeting:", _greeting);
        console.log("Deploying a Greeter with value:", _value);
        greeting = _greeting;
    }

    /** 
        @notice Returns the greeting value.
        @dev View only function. 
        @return string, greeting value
        @return uint, timestamp value
    */ 
    function greet() public view returns (string memory, uint) {
        return (greeting, 5253);
    }

    /**
        @notice Sets the greeting value.
        @dev The input value can be anything.
        @param _greeting The new greeting value.
    */ 
    function setGreeting(string memory _greeting) public {
        console.log("Changing greeting from '%s' to '%s'", greeting, _greeting);
        greeting = _greeting;
    }
}
