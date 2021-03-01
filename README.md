<p align="center">
  <img src="https://www.maple.finance/static/logo-52b94a65fa2c9a7c9ede3cb978b2408f.png" />
</p>

***

## Background
Maple is a decentralized corporate credit market. Maple provides capital to institutional borrowers through globally accessible fixed-income yield opportunities.

For Borrowers, Maple offers **transparent and efficient financing done entirely on-chain.**

* Funds can leverage their reputation to borrow undercollateralized without constant fear of liquidation and margin calls
* Borrowers access pools of capital governed by smart contracts and liaise with Pool Delegates to confidentially complete loan assessments

For Liquidity Providers, Maple offers a **sustainable yield source through professionally managed lending pools.**

* Diversified exposure across premium borrowers with staked MPL tokens providing reserve capital against loan defaults
* Set and forget solution with diligence outsourced to Pool Delegates
* Interest is accrued and reinvested to enable capital to compound over time

For Pool Delegates, Maple is a **vehicle to attract funding and earn performance fees.**

* Maple is a new platform providing decentralised asset management infrastructure
* Globally accessible pools enable increased AUM from varied liquidity sources to be provided to networks of premium, credit worthy borrowers

## Toolset

- <a href="https://github.com/dapphub/dapptools">DappTools</a>
- <a href="https://docs.soliditylang.org/en/v0.6.11/">Solidity 0.6.11</a>

## Development Setup

```sh
git clone git@github.com:maple-labs/maple-core.git
cd maple-core
dapp update
```

## Testing

- To run unit tests: `make unit-test`
- To run fuzz tests: `make fuzz-test` (runs `test-fuzz.sh`)
- To run all tests: `make ci-test` (runs `test-ci.sh`)

To alter number of fuzz runs, change the `--fuzz-runs` flag in `./test-ci.sh` or `test-fuzz.sh`

Note: Number of `--fuzz-runs` in `./test-ci.sh` should remain constant on push. Only change for local testing if needed.

## Join us on Discord

<a href="https://discord.gg/tuNYQse">Maple Discord</a>
