FILES=./contracts/*.sol
for f in $FILES
do
  # take action on each file. $f store current file name
#   hevm flatten --source-file "contracts/StakeLocker.sol" > flatten/StakeLocker.sol
    filepath=${f:2}
    filename=${filepath:10}
    echo "Flattening: $filename"
    hevm flatten --source-file $filepath > "flatten/$filename"
    hevm flatten --source-file $filepath | grep -E ") external |) public" > "flatten/functions/$filename"
done
