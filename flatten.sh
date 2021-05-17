#!/usr/bin/env bash
set -e

mkdir -p flattened-contracts/functions

FILES1=./contracts/*.sol
FILES2=./contracts/library/*.sol
FILES3=./contracts/oracles/*.sol

for f in $FILES1
do
    filepath=${f:2}
    filename=${filepath:10}
    echo "Flattening: $filename"
    hevm flatten --source-file $filepath | sed '/SPDX-License-Identifier/d' | sed -e '1s/^/\/\/ SPDX-License-Identifier:  AGPL-3.0-or-later /' | sed -r 'N;s/(\/\/\/\/\/\/ .*)\n\s*$/\1/;P;D' > "flattened-contracts/$filename"
    cat "flattened-contracts/$filename" | grep -E ") external |) public" > "flattened-contracts/functions/$filename"
done

for f in $FILES2
do
    filepath=${f:2}
    filename=${filepath:17}
    echo "Flattening: $filename"
    hevm flatten --source-file $filepath | sed '/SPDX-License-Identifier/d' | sed -e '1s/^/\/\/ SPDX-License-Identifier:  AGPL-3.0-or-later /' | sed -r 'N;s/(\/\/\/\/\/\/ .*)\n\s*$/\1/;P;D' > "flattened-contracts/$filename"
done

for f in $FILES3
do
    filepath=${f:2}
    filename=${filepath:17}
    echo "Flattening: $filename"
    hevm flatten --source-file $filepath | sed '/SPDX-License-Identifier/d' | sed -e '1s/^/\/\/ SPDX-License-Identifier:  AGPL-3.0-or-later /' | sed -r 'N;s/(\/\/\/\/\/\/ .*)\n\s*$/\1/;P;D' > "flattened-contracts/$filename"
done
