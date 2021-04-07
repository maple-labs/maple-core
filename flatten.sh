#!/usr/bin/env bash
set -e

mkdir -p flatten/functions

FILES=./contracts/*.sol
for f in $FILES
do
    filepath=${f:2}
    filename=${filepath:10}
    echo "Flattening: $filename"
    hevm flatten --source-file $filepath > "flatten/$filename"
    cat "flatten/$filename" | grep -E ") external |) public" > "flatten/functions/$filename"
done
