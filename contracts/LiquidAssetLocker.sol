pragma solidity 0.7.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidAssetLocker {
	address public liquidAsset;
	address public immutable ownerLP;
	constructor(address _liquidAsset, _LPaddy) public {
		liquidAsset = _liquidAsset;
		ownerLP = _LPaddy;
	}

	modifier isOwner(address _addy){
		require(_addy == ownerLP);
		_;
	}

}
