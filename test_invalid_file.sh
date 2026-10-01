#!/bin/bash
set -e

echo "[TEST] Access non-existent file"
make clean && make
./initdisk

mkdir -p testmount
./myfs -d testmount &
sleep 1

echo "[CHECK] Reading nonexistent.txt"
if cat testmount/nonexistent.txt 2>/dev/null; then
  echo "[FAIL] Expected failure but file was found"
  fusermount -uz testmount
  exit 1
else
  echo "[PASS] Invalid file correctly returned error"
  fusermount -uz testmount
fi
