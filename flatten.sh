#!/usr/bin/env bash
set -e

FILES1=./contracts/core/*/*/*.sol
FILES2=./contracts/core/*/*/interfaces/*.sol
FILES3=./contracts/libraries/*/*/*.sol

for f in $FILES1
do
    filepath=${f:2}
    filename=${filepath:10}
    mkdir -p "flattened-contracts/${filename%/*}"
    echo "Flattening: $filepath to flattened-contracts/$filename"
    hevm flatten --source-file $filepath | sed '/SPDX-License-Identifier/d' | sed -e '1s/^/\/\/ SPDX-License-Identifier: AGPL-3.0-or-later /' | sed -r 'N;s/(\/\/\/\/\/\/ .*)\n\s*$/\1/;P;D' > "flattened-contracts/$filename"
done

for f in $FILES2
do
    filepath=${f:2}
    filename=${filepath:10}
    mkdir -p "flattened-contracts/${filename%/*}"
    echo "Flattening: $filepath to flattened-contracts/$filename"
    hevm flatten --source-file $filepath | sed '/SPDX-License-Identifier/d' | sed -e '1s/^/\/\/ SPDX-License-Identifier: AGPL-3.0-or-later /' | sed -r 'N;s/(\/\/\/\/\/\/ .*)\n\s*$/\1/;P;D' > "flattened-contracts/$filename"
done

for f in $FILES3
do
    filepath=${f:2}
    filename=${filepath:10}
    mkdir -p "flattened-contracts/${filename%/*}"
    echo "Flattening: $filepath to flattened-contracts/$filename"
    hevm flatten --source-file $filepath | sed '/SPDX-License-Identifier/d' | sed -e '1s/^/\/\/ SPDX-License-Identifier: AGPL-3.0-or-later /' | sed -r 'N;s/(\/\/\/\/\/\/ .*)\n\s*$/\1/;P;D' > "flattened-contracts/$filename"
done
