# Maple Finance Core

The Maple Core protocol.

### Toolset

- <a href="https://github.com/dapphub/dapptools">Dapp tools</a>
- <a href="https://docs.soliditylang.org/en/v0.6.11/">Solidity 0.6.11</a>
- <a href="https://github.com/OpenZeppelin/solidity-docgen">Solidity-Docgen</a>
- Node v14
- Yarn
- VSCode
  - Juan Blanco's Solidity plugin for VsCode
  - Prettier Plugin

### Dev Setup

```sh
git clone git@github.com:maple-labs/maple-core.git
cd maple-core
dapp update
```

### Testing

- To run unit tests: `make unit-test`
- To run fuzz tests: `make fuzz-test` (runs `test-fuzz.sh`)
- To run all tests: `make ci-test` (runs `test-ci.sh`)

To alter number of fuzz runs, change the `--fuzz-runs` flag in `./test-ci.sh` or `test-fuzz.sh`

Note: Number of `--fuzz-runs` in `./test-ci.sh` should remain constant on push. Only change for local testing if needed.

### Join us on Discord

<a href="https://discord.gg/tuNYQse">Maple Discord</a>
