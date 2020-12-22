pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./MapleCore.sol";

contract MapleCoreTest is DSTest {
    MapleCore core;

    function setUp() public {
        core = new MapleCore();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
