pragma solidity 0.7.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract liquidAssetLocker {
	address public liquidAsset;

	constructor(address _liquidAsset, address _LPaddy) public {
		liquidAsset = _liquidAsset;
	}
}
