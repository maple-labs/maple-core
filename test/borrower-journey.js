const { expect, assert } = require("chai");

describe("Borrower Journey", function () {

  it("A - Fetch the list of borrowTokens / collateralTokens", async function () {

    const MapleGlobalsAddress = require("../../contracts/localhost/addresses/MapleGlobals.address");
    const MapleGlobalsABI = require("../../contracts/localhost/abis/MapleGlobals.abi");

    let MapleGlobals;

    MapleGlobals = new ethers.Contract(
      MapleGlobalsAddress,
      MapleGlobalsABI,
      ethers.provider.getSigner(0)
    );

    const BorrowTokenList_0 = await MapleGlobals.validBorrowTokenAddresses(0);
    const BorrowTokenList_1 = await MapleGlobals.validBorrowTokenAddresses(1);
    const BorrowTokenList_2 = await MapleGlobals.validBorrowTokenAddresses(2);
    const BorrowTokenList_3 = await MapleGlobals.validBorrowTokenAddresses(3);

    let tokenList = {
      'DAI': BorrowTokenList_0,
      'USDC': BorrowTokenList_1,
      'WETH': BorrowTokenList_2,
      'wBTC': BorrowTokenList_3,
    }

    // or

    let tokenListPlus = {
      'DAI':{'address': BorrowTokenList_0, 'decimals': 18},
      'USDC':{'address': BorrowTokenList_1, 'decimals': 6},
      'WETH':{'address': BorrowTokenList_2, 'decimals': 18},
      'wBTC':{'address': BorrowTokenList_3, 'decimals': 8},
    }

    for (var key in tokenList) {
        if (tokenList.hasOwnProperty(key)) {
            console.log(key + " -> " + tokenList[key]);
        }
    }

    for (var key in tokenListPlus) {
        if (tokenListPlus.hasOwnProperty(key)) {
            console.log(key + " -> " + tokenListPlus[key]['address'] + ', ' + tokenListPlus[key]['decimals']);
        }
    }

    // const menu = (
    //   <Menu>
    //     <Menu.Item key="key">
    //       tokenList[key]
    //     </Menu.Item>
    //   </Menu>
    // );

  });

});
