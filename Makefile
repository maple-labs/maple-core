all       :; dapp build
clean     :; dapp clean
unit-test :; ./test.sh
fuzz-test :; ./test-fuzz.sh
ci-test   :; ./test-ci.sh
deploy    :; dapp create MapleCore
