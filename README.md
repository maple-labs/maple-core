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

## Testing

- To run all unit tests: `make test` (runs `./test.sh`)
- To run a specific unit test: `./test.sh <test_name>` (e.g. `./test.sh test_fundLoan`)

To alter number of fuzz runs, change the `--fuzz-runs` flag in `test.sh`. Note: Number of `--fuzz-runs` in `test.sh` should remain constant on push. Only change for local testing if needed.

## Audit reports
| Auditor | Report link |
|---|---|
| Peckshield                            | [PeckShield-Audit-Report-Maple-v1.0](https://github.com/maple-labs/maple-core/files/6423601/PeckShield-Audit-Report-Maple-v1.0.1.pdf) |
| Code Arena                            | [Code Arena April 2021 Audit](https://code423n4.com/reports/2021-04-maple/) |
| Dedaub (before v1.0.0 release commit) | [Dedaub-Audit-Report-Maple-Core](https://github.com/maple-labs/maple-core/files/6423621/Dedaub-Audit-Report-Maple-Core.2.pdf) |

## Join us on Discord

<a href="https://discord.gg/tuNYQse">Maple Discord</a>

---

<p align="center">
  <img src="https://user-images.githubusercontent.com/44272939/116272804-33e78d00-a74f-11eb-97ab-77b7e13dc663.png" height="100" />
</p>
