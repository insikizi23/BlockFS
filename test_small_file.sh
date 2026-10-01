#!/bin/bash
set -e

echo "[TEST] Small file in direct block range"
make clean && make
./initdisk

# Manually add small file to disk
DISK="mydisk.img"
FILE_NAME="small.txt"
CONTENT="hello world"
BLOCK_SIZE=512

# Write file data
OFFSET=$((65 * BLOCK_SIZE))
echo -n "$CONTENT" | dd of=$DISK bs=1 seek=$OFFSET conv=notrunc status=none

# Write inode (index 1)
INODE_OFFSET=$((BLOCK_SIZE + 1 * 128))  # assuming sizeof(Inode) = 128
printf "\x0b\x00\x00\x00" > tmp.bin  # size = 11
printf "\x00\x00\x00\x00" >> tmp.bin  # is_dir = 0
printf "\x41\x00\x00\x00" >> tmp.bin  # direct block 65
dd if=tmp.bin of=$DISK bs=1 seek=$INODE_OFFSET conv=notrunc status=none
rm tmp.bin

# Add dir entry to root
echo -n "small.txt" | dd of=$DISK bs=1 seek=$((66 * BLOCK_SIZE)) conv=notrunc status=none
printf "\x01\x00\x00\x00" | dd of=$DISK bs=1 seek=$((66 * BLOCK_SIZE + 60)) conv=notrunc status=none

# Update root inode
printf "\x48\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE)) conv=notrunc status=none
printf "\x01\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE + 4)) conv=notrunc status=none
printf "\x42\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE + 8)) conv=notrunc status=none

# Mount and test
mkdir -p testmount
./myfs -d testmount &
sleep 1
echo "[CHECK] Reading small.txt"
ACTUAL=$(cat testmount/small.txt)
EXPECTED="hello world"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "[FAIL] Expected '$EXPECTED', got '$ACTUAL'"
  fusermount -uz testmount
  exit 1
else
  echo "[PASS] Small file test passed"
  fusermount -uz testmount
fi
