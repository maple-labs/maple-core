/// value.sol - a value is a simple thing, it can be get and set

// Copyright (C) 2017  DappHub, LLC

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.




// NOTE: Code modified for test mocking:
// Changed bytes32 to uint256
// Changed read() to price()

pragma solidity >=0.4.23;

contract DSValue {
    bool    has;
    uint256 val;
    function peek() public view returns (uint256, bool) {
        return (val,has);
    }
    function price() public view returns (uint256) {
        uint256 wut; bool haz;
        (wut, haz) = peek();
        require(haz, "haz-not");
        return wut;
    }
    function poke(uint256 wut) public {
        val = wut;
        has = true;
    }
    function void() public {  // unset the value
        has = false;
    }
}
