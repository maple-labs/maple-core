pragma solidity 0.7.0;

interface IGlobals {
    function governor() external view returns (address);

    function mapleToken() external view returns (address);

    function mapleTreasury() external view returns (address);

    function establishmentFeeBasisPoints() external view returns (uint256);

    function treasuryFeeBasisPoints() external view returns (uint256);

    function gracePeriod() external view returns (uint256);

    function stakeAmountRequired() external view returns (uint256);

    function validPaymentIntervalSeconds(uint256) external view returns (bool);

    function interestStructureCalculators(bytes32) external view returns (address);

    function unstakeDelay() external view returns (uint256);
}
