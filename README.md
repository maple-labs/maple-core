## Background
Maple is a decentralized corporate credit market. Maple provides capital to institutional borrowers through globally accessible fixed-income yield opportunities.

For Borrowers, Maple offers **transparent and efficient financing done entirely on-chain.**

* Funds can leverage their reputation to borrow undercollateralized without constant fear of liquidation and margin calls
* Borrowers access pools of capital governed by smart contracts and liaise with Pool Delegates to confidentially complete loan assessments

For Liquidity Providers, Maple offers a **sustainable yield source through professionally managed lending pools.**

* Diversified exposure across premium borrowers with staked `MPL-<liquidityAsset>` 50-50 Balancer Pool Tokens (BPTs) providing reserve capital against loan defaults (E.g., MPL-USDC 50-50 BPTs for USDC Pools)
* Set and forget solution with diligence outsourced to Pool Delegates
* Interest is accrued and reinvested to enable capital to compound over time

For Pool Delegates, Maple is a **vehicle to attract funding and earn performance fees.**

* Maple is a new platform providing decentralised asset management infrastructure
* Globally accessible pools enable increased AUM from varied liquidity sources to be provided to networks of premium, creditworthy borrowers

## Technical Documentation

For all technical documentation related to the Maple protocol, please refer to the GitHub [wiki](https://github.com/maple-labs/maple-core/wiki).

## Toolset

- <a href="https://github.com/dapphub/dapptools">dapptools</a>
- <a href="https://docs.soliditylang.org/en/v0.6.11/">Solidity 0.6.11</a>

## Development Setup

```sh
git clone git@github.com:maple-labs/maple-core.git
cd maple-core
dapp update
```

## Build Config
To create a new config.json file, use `DAPP_SRC=contracts dapp mk-standard-json | pbcopy` and then paste that into a new file. If using deployed libraries, make sure to add 
```sh
export DAPP_LIBRARIES=" contracts/libraries/loan/v1/LoanLib.sol:LoanLib:0x51A189ccD2eB5e1168DdcA7e59F7c8f39AA52232 contracts/libraries/pool/v1/PoolLib.sol:PoolLib:0x2c1C30fb8cC313Ef3cfd2E2bBf2da88AdD902C30"
``` 
in that format (space delimited with a space at the beginning) with relevant libraries and addresses.

## Testing

- To run all unit tests: `make test` (runs `./test.sh`)
- To run a specific unit test: `./test.sh <test_name>` (e.g. `./test.sh test_fundLoan`)

To alter number of fuzz runs, change the `--fuzz-runs` flag in `test.sh`. Note: Number of `--fuzz-runs` in `test.sh` should remain constant on push. Only change for local testing if needed.

## Audit Reports
| Auditor | Report link |
|---|---|
| Peckshield                            | [PeckShield-Audit-Report-Maple-v1.0](https://github.com/maple-labs/maple-core/files/6423601/PeckShield-Audit-Report-Maple-v1.0.1.pdf) |
| Code Arena                            | [Code Arena April 2021 Audit](https://code423n4.com/reports/2021-04-maple/) |
| Dedaub (before v1.0.0 release commit) | [Dedaub-Audit-Report-Maple-Core](https://github.com/maple-labs/maple-core/files/6423621/Dedaub-Audit-Report-Maple-Core.2.pdf) |

# Deployed Addresses

## Mainnet
### v1.0.0
| Contract | Address |
| -------- | ------- |
| Governor                | [0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196](https://etherscan.io/address/0xd6d4Bcde6c816F17889f1Dd3000aF0261B03a196) |
| GlobalAdmin             | [0x93CC3E39C91cf93fd57acA416ed6fE66e8bdD573](https://etherscan.io/address/0x93CC3E39C91cf93fd57acA416ed6fE66e8bdD573) |
| SecurityAdmin           | [0x6b1A78C1943b03086F7Ee53360f9b0672bD60818](https://etherscan.io/address/0x6b1A78C1943b03086F7Ee53360f9b0672bD60818) |
| USDC                    | [0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48](https://etherscan.io/address/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48) |
| WBTC                    | [0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599](https://etherscan.io/address/0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) |
| WETH9                   | [0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2](https://etherscan.io/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) |
| MapleToken              | [0x33349B282065b0284d756F0577FB39c158F935e6](https://etherscan.io/address/0x33349B282065b0284d756F0577FB39c158F935e6) |
| UniswapV2Router02       | [0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D](https://etherscan.io/address/0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D) |
| BFactory                | [0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd](https://etherscan.io/address/0x9424B1412450D0f8Fc2255FAf6046b98213B76Bd) |
| ChainLinkAggregatorWBTC | [0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c](https://etherscan.io/address/0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c) |
| BPool                   | [0xc1b10e536CD611aCFf7a7c32A9E29cE6A02Ef6ef](https://etherscan.io/address/0xc1b10e536CD611aCFf7a7c32A9E29cE6A02Ef6ef) |
| MapleGlobals            | [0xC234c62c8C09687DFf0d9047e40042cd166F3600](https://etherscan.io/address/0xC234c62c8C09687DFf0d9047e40042cd166F3600) |
| Util                    | [0x95f9676A34aF2675B63948dDba8F8c798741A52a](https://etherscan.io/address/0x95f9676A34aF2675B63948dDba8F8c798741A52a) |
| PoolLib                 | [0x2c1C30fb8cC313Ef3cfd2E2bBf2da88AdD902C30](https://etherscan.io/address/0x2c1C30fb8cC313Ef3cfd2E2bBf2da88AdD902C30) |
| LoanLib                 | [0x51A189ccD2eB5e1168DdcA7e59F7c8f39AA52232](https://etherscan.io/address/0x51A189ccD2eB5e1168DdcA7e59F7c8f39AA52232) |
| MapleTreasury           | [0xa9466EaBd096449d650D5AEB0dD3dA6F52FD0B19](https://etherscan.io/address/0xa9466EaBd096449d650D5AEB0dD3dA6F52FD0B19) |
| RepaymentCalc           | [0x7d622bB6Ed13a599ec96366Fa95f2452c64ce602](https://etherscan.io/address/0x7d622bB6Ed13a599ec96366Fa95f2452c64ce602) |
| LateFeeCalc             | [0x8dC5aa328142aa8a008c25F66a77eaA8E4B46f3c](https://etherscan.io/address/0x8dC5aa328142aa8a008c25F66a77eaA8E4B46f3c) |
| PremiumCalc             | [0xe88Ab4Cf1Ec06840d16feD69c964aD9DAFf5c6c2](https://etherscan.io/address/0xe88Ab4Cf1Ec06840d16feD69c964aD9DAFf5c6c2) |
| PoolFactory             | [0x2Cd79F7f8b38B9c0D80EA6B230441841A31537eC](https://etherscan.io/address/0x2Cd79F7f8b38B9c0D80EA6B230441841A31537eC) |
| StakeLockerFactory      | [0x53a597A4730Eb02095dD798B203Dcc306348B8d6](https://etherscan.io/address/0x53a597A4730Eb02095dD798B203Dcc306348B8d6) |
| LiquidityLockerFactory  | [0x966528BB1C44f96b3AA8Fbf411ee896116b068C9](https://etherscan.io/address/0x966528BB1C44f96b3AA8Fbf411ee896116b068C9) |
| DebtLockerFactory       | [0x2a7705594899Db6c3924A872676E54f041d1f9D8](https://etherscan.io/address/0x2a7705594899Db6c3924A872676E54f041d1f9D8) |
| LoanFactory             | [0x908cC851Bc757248514E060aD8Bd0a03908308ee](https://etherscan.io/address/0x908cC851Bc757248514E060aD8Bd0a03908308ee) |
| CollateralLockerFactory | [0xEE3e59D381968f4F9C92460D9d5Cfcf5d3A67987](https://etherscan.io/address/0xEE3e59D381968f4F9C92460D9d5Cfcf5d3A67987) |
| FundingLockerFactory    | [0x0eB96A53EC793a244876b018073f33B23000F25b](https://etherscan.io/address/0x0eB96A53EC793a244876b018073f33B23000F25b) |
| MplRewardsFactory       | [0x0155729EbCd47Cb1fBa02bF5a8DA20FaF3860535](https://etherscan.io/address/0x0155729EbCd47Cb1fBa02bF5a8DA20FaF3860535) |
| PriceOracleUSDC         | [0x5DC5E14be1280E747cD036c089C96744EBF064E7](https://etherscan.io/address/0x5DC5E14be1280E747cD036c089C96744EBF064E7) |
| PriceOracleWBTC         | [0xF808ec05c1760DE4794813d08d2Bf1E16e7ECD0B](https://etherscan.io/address/0xF808ec05c1760DE4794813d08d2Bf1E16e7ECD0B) |

## Rinkeby
### v1.0.0
| Contract | Address |
| -------- | ------- |
| Governor                | [0x82B10F0E1dcf5EE87b6F380B63D2bED14Bf1F260](https://rinkeby.etherscan.io/address/0x82B10F0E1dcf5EE87b6F380B63D2bED14Bf1F260) |
| GlobalAdmin             | [0xe630d03521fD47f8a6e46c957eBb4fe2c5078A85](https://rinkeby.etherscan.io/address/0xe630d03521fD47f8a6e46c957eBb4fe2c5078A85) |
| SecurityAdmin           | [0x295Dfe980d19bdEc69B047809c2073b443747FE2](https://rinkeby.etherscan.io/address/0x295Dfe980d19bdEc69B047809c2073b443747FE2) |
| USDC                    | [0x553D0a8807f8E325671Ce953a4D00883CCE1ee56](https://rinkeby.etherscan.io/address/0x553D0a8807f8E325671Ce953a4D00883CCE1ee56) |
| WBTC                    | [0xBa711fCa79c559EC8D98c39a81876105A6C0cefa](https://rinkeby.etherscan.io/address/0xBa711fCa79c559EC8D98c39a81876105A6C0cefa) |
| WETH9                   | [0x464Fd1dE206cB8ed2Ee77f100dd75CaEdF1F9738](https://rinkeby.etherscan.io/address/0x464Fd1dE206cB8ed2Ee77f100dd75CaEdF1F9738) |
| MapleToken              | [0x58Db0d6686431266229b8A864381E8F42fff5408](https://rinkeby.etherscan.io/address/0x58Db0d6686431266229b8A864381E8F42fff5408) |
| UniswapV2Router02       | [0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D](https://rinkeby.etherscan.io/address/0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D) |
| BFactory                | [0x9C84391B443ea3a48788079a5f98e2EaD55c9309](https://rinkeby.etherscan.io/address/0x9C84391B443ea3a48788079a5f98e2EaD55c9309) |
| ChainLinkAggregatorWBTC | [0xECe365B379E1dD183B20fc5f022230C044d51404](https://rinkeby.etherscan.io/address/0xECe365B379E1dD183B20fc5f022230C044d51404) |
| BPool                   | [0x08F3fB954F5E80FA71bC04ad5bbbd534e60294C9](https://rinkeby.etherscan.io/address/0x08F3fB954F5E80FA71bC04ad5bbbd534e60294C9) |
| MapleGlobals            | [0xDd3f6539cC113C9f71071f2564616fE520B0c0EE](https://rinkeby.etherscan.io/address/0xDd3f6539cC113C9f71071f2564616fE520B0c0EE) |
| Util                    | [0xCf0CED756414Ce4E7496E86f73330338c1372fff](https://rinkeby.etherscan.io/address/0xCf0CED756414Ce4E7496E86f73330338c1372fff) |
| PoolLib                 | [0xEe0E6E3131DC5E096bE02F11Ff690dec5E05374f](https://rinkeby.etherscan.io/address/0xEe0E6E3131DC5E096bE02F11Ff690dec5E05374f) |
| LoanLib                 | [0x653C43b40a8A2876C2264224c5E1Db9cc1086830](https://rinkeby.etherscan.io/address/0x653C43b40a8A2876C2264224c5E1Db9cc1086830) |
| MapleTreasury           | [0xbEc11108612594408b506e53BBa93001a1a25607](https://rinkeby.etherscan.io/address/0xbEc11108612594408b506e53BBa93001a1a25607) |
| RepaymentCalc           | [0xE256455b4a711E9d4E276202e658C843a310FB64](https://rinkeby.etherscan.io/address/0xE256455b4a711E9d4E276202e658C843a310FB64) |
| LateFeeCalc             | [0xec743cd8dee270E31cab6e01d0533282105697A0](https://rinkeby.etherscan.io/address/0xec743cd8dee270E31cab6e01d0533282105697A0) |
| PremiumCalc             | [0xeBcbE20E52dCE08b9947Bf02e39000391CA756D7](https://rinkeby.etherscan.io/address/0xeBcbE20E52dCE08b9947Bf02e39000391CA756D7) |
| PoolFactory             | [0x9a350c34d12981940dcD3f73876e4b320cF3Cb65](https://rinkeby.etherscan.io/address/0x9a350c34d12981940dcD3f73876e4b320cF3Cb65) |
| StakeLockerFactory      | [0xF48EB5C1314893b5392a5C10446E9f331c53d627](https://rinkeby.etherscan.io/address/0xF48EB5C1314893b5392a5C10446E9f331c53d627) |
| LiquidityLockerFactory  | [0xde7e989049e6F5164C9818F81D7044353ad15311](https://rinkeby.etherscan.io/address/0xde7e989049e6F5164C9818F81D7044353ad15311) |
| DebtLockerFactory       | [0x2b01694a7959bC4721Bbcaa219eA076Ee746fb91](https://rinkeby.etherscan.io/address/0x2b01694a7959bC4721Bbcaa219eA076Ee746fb91) |
| LoanFactory             | [0x31db11dd6f2d3F03ad7641EEF07D181DCdE92eBf](https://rinkeby.etherscan.io/address/0x31db11dd6f2d3F03ad7641EEF07D181DCdE92eBf) |
| CollateralLockerFactory | [0x7170c78e08c1577C8Fdf106D959163B6bFDeB030](https://rinkeby.etherscan.io/address/0x7170c78e08c1577C8Fdf106D959163B6bFDeB030) |
| FundingLockerFactory    | [0x964031C8c4A42CA9Df61025D1C363f81660D06Fe](https://rinkeby.etherscan.io/address/0x964031C8c4A42CA9Df61025D1C363f81660D06Fe) |
| MplRewardsFactory       | [0xC2cf6BAFfe1d2EaA23bc632A1395B7b4828407b7](https://rinkeby.etherscan.io/address/0xC2cf6BAFfe1d2EaA23bc632A1395B7b4828407b7) |
| PriceOracleUSDC         | [0x4D31De6e7b810328AF4196dC6D5b400C31B34180](https://rinkeby.etherscan.io/address/0x4D31De6e7b810328AF4196dC6D5b400C31B34180) |
| PriceOracleWBTC         | [0xEb63E18E54912FB7437e7c974C0Cd03D8d830906](https://rinkeby.etherscan.io/address/0xEb63E18E54912FB7437e7c974C0Cd03D8d830906) |

## Join us on Discord

<a href="https://discord.gg/tuNYQse">Maple Discord</a>

---

<p align="center">
  <img src="https://user-images.githubusercontent.com/44272939/116272804-33e78d00-a74f-11eb-97ab-77b7e13dc663.png" height="100" />
</p>
