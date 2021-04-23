#!/usr/bin/env bash
set -e

mkdir -p flatten/functions

FILES1=./contracts/*.sol
FILES2=./contracts/library/*.sol
for f in $FILES1
do
    filepath=${f:2}
    filename=${filepath:10}
    echo "Flattening: $filename"
    hevm flatten --source-file $filepath | sed '/SPDX-License-Identifier/d' | sed -e '1s/^/ \/\/ SPDX-License-Identifier:  AGPL-3.0-or-later /' > "flatten/$filename"
    cat "flatten/$filename" | grep -E ") external |) public" > "flatten/functions/$filename"
done

for f in $FILES2
do
    filepath=${f:2}
    filename=${filepath:17}
    echo "Flattening: $filename"
    hevm flatten --source-file $filepath | sed '/SPDX-License-Identifier/d' | sed -e '1s/^/ \/\/ SPDX-License-Identifier:  AGPL-3.0-or-later /' > "flatten/$filename"
done