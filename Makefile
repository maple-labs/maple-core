all       :; dapp build
clean     :; dapp clean
unit-test :; ./test.sh
fuzz-test :; ./test-fuzz.sh
ci-test   :; ./test-ci.sh
deploy    :; dapp create MapleCore
ci        :; circleci config process .circleci/config.yml > process.yml && circleci local execute -c process.yml --job dapp_build
