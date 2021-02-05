#!/usr/bin/env bash
set -e

[[ "$ETH_RPC_URL" && "$(seth chain)" == "ethlive"  ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1;  }

export DAPP_TEST_TIMESTAMP=$(seth block latest timestamp)
export DAPP_TEST_NUMBER=$(seth block latest number)	export DAPP_TEST_NUMBER=$(seth block latest number)
export DAPP_SKIP_BUILD=1
export DAPP_SOLC_VERSION=0.6.11
export DAPP_SRC="contracts"
export SOLC_FLAGS="--optimize --optimize-runs 200"
export DAPP_LINK_TEST_LIBRARIES=1

dapp build
LANG=C.UTF-8 dapp test --match "contracts/test" --rpc-url "$ETH_RPC_URL" --verbose

# --match "contracts/test/CollateralLockerFactory.t.sol"
# --match "contracts/test/DebtLockerFactory.t.sol"
# --match "contracts/test/FundingLockerFactory.t.sol"
# --match "contracts/test/Gulp.t.sol"
# --match "contracts/test/Loan.t.sol"
# --match "contracts/test/LoanFactory.t.sol"
# --match "contracts/test/LoanLiquidation.t.sol"
# --match "contracts/test/MapleGlobals.t.sol"
# --match "contracts/test/MapleTreasury.t.sol"
# --match "contracts/test/Pool.t.sol"
# --match "contracts/test/PoolExcess.t.sol"
# --match "contracts/test/PoolFactory.t.sol"
# --match "contracts/test/PoolLiquidation.t.sol"
# --match "contracts/test/StakeLocker.t.sol"
# --match "contracts/test/StakeLockerFactory.t.sol"
