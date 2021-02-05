// SPDX-License-Identifier: MIT

pragma solidity >=0.6.11;

contract MockPriceFeedUSDC {
    
    int256 price;
    address asset;

    constructor(int256 _price, address _asset) public {
        price = _price;
        asset = _asset;
    }

    function latestRoundData() 
        external 
        view 
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            roundId = 0;
            answer = price;
            startedAt = 0;
            updatedAt = 0;
            answeredInRound = 0;
        }

}
