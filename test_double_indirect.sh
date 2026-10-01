#!/bin/bash
set -e

echo "[TEST] File in double indirect block"
make clean && make
./initdisk

DISK="mydisk.img"
BLOCK_SIZE=512
CONTENT="data_from_double_indirect"
FILENAME="dblindirect.txt"

# Create data block at 300 and write content
DATA_BLOCK=300
echo -n "$CONTENT" | dd of=$DISK bs=1 seek=$((DATA_BLOCK * BLOCK_SIZE)) conv=notrunc status=none

# Create second-level indirect block at 250 pointing to data block
SECOND_LEVEL_BLOCK=250
printf "\x2c\x01\x00\x00" | dd of=$DISK bs=1 seek=$((SECOND_LEVEL_BLOCK * BLOCK_SIZE)) conv=notrunc status=none

# Create double indirect block at 200 pointing to second-level block
DOUBLE_INDIRECT_BLOCK=200
printf "\xfa\x00\x00\x00" | dd of=$DISK bs=1 seek=$((DOUBLE_INDIRECT_BLOCK * BLOCK_SIZE)) conv=notrunc status=none

# Setup inode (index 1) with double indirect block pointer and correct file size
INODE_OFFSET=$((BLOCK_SIZE + 1 * 128))
dd if=/dev/zero bs=128 count=1 of=tmp_inode status=none
FILESIZE=$(( 69632 + ${#CONTENT} ))
FILESIZE_HEX=$(printf "%08x" $FILESIZE | sed -E 's/(..)(..)(..)(..)/\\x\4\\x\3\\x\2\\x\1/')
printf "$FILESIZE_HEX" | dd of=tmp_inode bs=1 seek=0 conv=notrunc status=none   # size = length of content
printf "\x00\x00\x00\x00" | dd of=tmp_inode bs=1 seek=4 conv=notrunc status=none   # is_dir = 0
printf "\xc8\x00\x00\x00" | dd of=tmp_inode bs=1 seek=44 conv=notrunc status=none  # double_indirect = 200
dd if=tmp_inode of=$DISK bs=1 seek=$INODE_OFFSET conv=notrunc status=none
rm tmp_inode

# Write DirEntry for dblindirect.txt into block 66
echo -n "dblindirect.txt" | dd of=$DISK bs=1 seek=$((66 * BLOCK_SIZE)) conv=notrunc status=none
printf "\x01\x00\x00\x00" | dd of=$DISK bs=1 seek=$((66 * BLOCK_SIZE + 60)) conv=notrunc status=none

# Update root inode
printf "\x48\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE)) conv=notrunc status=none
printf "\x01\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE + 4)) conv=notrunc status=none
printf "\x42\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE + 8)) conv=notrunc status=none

# Mount and test
mkdir -p testmount
./myfs -d testmount &
sleep 1

echo "[CHECK] Reading dblindirect.txt"
# Offset: skip blocks for 8 direct + 128 indirect = 136 * BLOCK_SIZE
OFFSET=$((136 * BLOCK_SIZE))
ACTUAL=$(dd if=testmount/dblindirect.txt bs=1 count=${#CONTENT} skip=$OFFSET status=none)
EXPECTED="data_from_double_indirect"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "[FAIL] Expected '$EXPECTED', got '$ACTUAL'"
  fusermount -uz testmount
  exit 1
else
  echo "[PASS] Double indirect block test passed"
  fusermount -uz testmount
fi
