// SPDX-License-Identifier: MIT
pragma solidity >=0.6.11;

/// @title Generates a UUID, used for Pool and Loan (debt) tokens in respective factories.
library TokenUUID {

    /// @notice Generates a UUID.
    /// @param serial ranodmizes the output.
    /// @return UUID
    function generatedUUID(uint256 serial) internal view returns (string memory) {

        bytes32 inBytes       =  keccak256(abi.encodePacked(block.timestamp, serial));
        bytes memory outBytes = new bytes(8);

        for (uint8 i = 0; i < 7; i++) {
            uint8 digit = uint8(inBytes[i]) % 10;
            outBytes[i] = byte(48 + digit);
        }

        uint8 digit = uint8(serial) % 26;
        outBytes[7] = byte(97 + digit);

        return string(outBytes);
    }
}
