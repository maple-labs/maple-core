
#!/usr/bin/env bash
set -e

[[ "$ETH_RPC_URL" && "$(seth chain)" == "ethlive"  ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1;  }

# DAPP_SRC="contracts" SOLC_FLAGS="--optimize --optimize-runs 200" dapp --use solc:0.6.11 build

export DAPP_TEST_TIMESTAMP=$(seth block latest timestamp)
export DAPP_TEST_NUMBER=$(seth block latest number)

LANG=C.UTF-8 DAPP_SRC="contracts" hevm dapp-test --match ${1} --rpc="$ETH_RPC_URL" --json-file=out/dapp.sol.json --dapp-root=. --verbose 1
