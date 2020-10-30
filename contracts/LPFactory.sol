pragma solidity ^0.7.0;

<<<<<<< HEAD
import "./LP.sol";

contract LiquidityPoolFactory {

    mapping(uint => address) public LiquidityPools;
    uint public LiquidityPoolsCreated;

    function createLiquidityPool(
        address _investmentAsset,
        address _stakedAsset,
        address _stakedAssetLockerFactory,
		string memory name, 
		string memory symbol
    ) public {
        LP lpool = new LP(
            _investmentAsset,
=======
import "./LP/LP.sol";

contract LPFactory {
    mapping(uint256 => address) private LiquidityPools;
    uint256 public LiquidityPoolsCreated;

    function createLiquidityPool(
        address _liquidAsset,
        address _stakedAsset,
        address _stakedAssetLockerFactory,
        string memory name,
        string memory symbol,
        address _MapleGlobalsaddy
    ) public {
        LP lpool = new LP(
            _liquidAsset,
>>>>>>> 456d3977412a202065b53d21d5b8287abee822c9
            _stakedAsset,
            _stakedAssetLockerFactory,
            name,
            symbol,
<<<<<<< HEAD
            IERC20(_investmentAsset)
=======
            _MapleGlobalsaddy //IERC20(_liquidAsset)
>>>>>>> 456d3977412a202065b53d21d5b8287abee822c9
        );
        LiquidityPools[LiquidityPoolsCreated] = address(lpool);
        LiquidityPoolsCreated++;
    }

<<<<<<< HEAD
}
=======
    function getLiquidityPool(uint256 _ind) public view returns (address) {
        return LiquidityPools[_ind];
    }
}
>>>>>>> 456d3977412a202065b53d21d5b8287abee822c9
