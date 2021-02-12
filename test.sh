#!/usr/bin/env bash
set -e

[[ "$ETH_RPC_URL" && "$(seth chain)" == "ethlive"  ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1;  }

export DAPP_TEST_TIMESTAMP=1612311576
export DAPP_TEST_NUMBER=11780000
export DAPP_SOLC_VERSION=0.6.11
export DAPP_SRC="contracts"
export SOLC_FLAGS="--optimize --optimize-runs 200"
export DAPP_LINK_TEST_LIBRARIES=1

LANG=C.UTF-8 dapp test --match "contracts/test" --rpc-url "$ETH_RPC_URL" --verbose --cache "cache/dapp-cache"

# --match "contracts/test/MapleGlobals.t.sol" 
