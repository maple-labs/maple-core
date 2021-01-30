#!/usr/bin/env bash
set -e

[[ "$ETH_RPC_URL" && "$(seth chain)" == "ethlive"  ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1;  }

export DAPP_TEST_TIMESTAMP=$(seth block latest timestamp)
export DAPP_TEST_NUMBER=$(seth block latest number)	export DAPP_TEST_NUMBER=$(seth block latest number)
export DAPP_SKIP_BUILD=1
export DAPP_SOLC_VERSION=0.6.11
export DAPP_SRC="contracts"
export SOLC_FLAGS="--optimize --optimize-runs 200"

dapp build
LANG=C.UTF-8 dapp test --match "test_getInitialStakeRequirements" --rpc-url "$ETH_RPC_URL" --verbose

# --match "contracts/test/MapleGlobals.t.sol" 
