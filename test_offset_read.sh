#!/bin/bash
set -e

echo "[TEST] Offset read inside file"
make clean && make
./initdisk

DISK="mydisk.img"
BLOCK_SIZE=512
CONTENT="ABCDEFGHIJ"  # 10 characters
FILENAME="offset.txt"

# Write full data to block 70
OFFSET=$((70 * BLOCK_SIZE))
echo -n "$CONTENT" | dd of=$DISK bs=1 seek=$OFFSET conv=notrunc status=none

# Setup inode (index 1) with direct block pointing to block 70
INODE_OFFSET=$((BLOCK_SIZE + 1 * 128))
printf "\x0a\x00\x00\x00" > tmp.bin  # size = 10
printf "\x00\x00\x00\x00" >> tmp.bin  # is_dir = 0
printf "\x46\x00\x00\x00" >> tmp.bin  # direct block 70
dd if=tmp.bin of=$DISK bs=1 seek=$INODE_OFFSET conv=notrunc status=none
rm tmp.bin

# Write DirEntry for offset.txt into block 66
echo -n "offset.txt" | dd of=$DISK bs=1 seek=$((66 * BLOCK_SIZE)) conv=notrunc status=none
printf "\x01\x00\x00\x00" | dd of=$DISK bs=1 seek=$((66 * BLOCK_SIZE + 60)) conv=notrunc status=none

# Update root inode
printf "\x48\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE)) conv=notrunc status=none
printf "\x01\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE + 4)) conv=notrunc status=none
printf "\x42\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE + 8)) conv=notrunc status=none

# Mount and test offset read
mkdir -p testmount
./myfs -d testmount &
sleep 1

echo "[CHECK] Reading from offset 3 of offset.txt"
ACTUAL=$(dd if=testmount/offset.txt bs=1 skip=3 count=4 2>/dev/null)
EXPECTED="DEFG"

if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "[FAIL] Expected '$EXPECTED', got '$ACTUAL'"
  fusermount -uz testmount
  exit 1
else
  echo "[PASS] Offset read test passed"
  fusermount -uz testmount
fi
