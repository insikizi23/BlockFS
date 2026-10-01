#!/bin/bash
set -e

echo "[TEST] File in indirect block range"
make clean && make
./initdisk

DISK="mydisk.img"
BLOCK_SIZE=512
FILE_CONTENT="this_is_data_in_indirect_block"
FILENAME="indirect.txt"

# Write data to block 200
OFFSET=$((200 * BLOCK_SIZE))
echo -n "$FILE_CONTENT" | dd of=$DISK bs=1 seek=$OFFSET conv=notrunc status=none

# Create an indirect block pointing to block 200 at block 150
INDIRECT_BLOCK=$((150 * BLOCK_SIZE))
printf "\xc8\x00\x00\x00" | dd of=$DISK bs=1 seek=$INDIRECT_BLOCK conv=notrunc status=none

# Set up inode (index 1) with indirect pointer at block 150
INODE_OFFSET=$((BLOCK_SIZE + 1 * 128))
FILESIZE=$(( 4096 + ${#FILE_CONTENT} ))
FILESIZE_HEX=$(printf "%08x" $FILESIZE | sed -E 's/(..)(..)(..)(..)/\\x\4\\x\3\\x\2\\x\1/')
printf "$FILESIZE_HEX" > tmp.bin
printf "\x00\x00\x00\x00" >> tmp.bin # is_dir = 0
for i in {1..8}; do printf "\x00\x00\x00\x00" >> tmp.bin; done  # no direct blocks
printf "\x96\x00\x00\x00" >> tmp.bin  # indirect block = 150
printf "\x00\x00\x00\x00" >> tmp.bin  # no double indirect
dd if=tmp.bin of=$DISK bs=1 seek=$INODE_OFFSET conv=notrunc status=none
rm tmp.bin

# Write DirEntry for indirect.txt into block 66
echo -n "indirect.txt" | dd of=$DISK bs=1 seek=$((66 * BLOCK_SIZE)) conv=notrunc status=none
printf "\x01\x00\x00\x00" | dd of=$DISK bs=1 seek=$((66 * BLOCK_SIZE + 60)) conv=notrunc status=none

# Update root inode
printf "\x48\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE)) conv=notrunc status=none
printf "\x01\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE + 4)) conv=notrunc status=none
printf "\x42\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE + 8)) conv=notrunc status=none

# Mount and test
mkdir -p testmount
./myfs -d testmount &
sleep 1
echo "[CHECK] Reading indirect.txt"
OFFSET=$((8 * BLOCK_SIZE))
ACTUAL=$(dd if=testmount/indirect.txt bs=1 count=${#FILE_CONTENT} skip=$OFFSET status=none)
EXPECTED="this_is_data_in_indirect_block"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "[FAIL] Expected '$EXPECTED', got '$ACTUAL'"
  fusermount -uz testmount
  exit 1
else
  echo "[PASS] Indirect block file test passed"
  fusermount -uz testmount
fi
