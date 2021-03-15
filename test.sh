#!/usr/bin/env bash
set -e

[[ "$ETH_RPC_URL" && "$(seth chain)" == "ethlive"  ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1;  }

export DAPP_TEST_TIMESTAMP=1615792486
export DAPP_TEST_NUMBER=12045000
export DAPP_SOLC_VERSION=0.6.11
export DAPP_SRC="contracts"
export SOLC_FLAGS="--optimize --optimize-runs 200"
export DAPP_LINK_TEST_LIBRARIES=1

LANG=C.UTF-8 dapp test --match "test_transfer_depositDate" --rpc-url "$ETH_RPC_URL" --verbose --cache "cache/dapp-cache" --fuzz-runs 100
