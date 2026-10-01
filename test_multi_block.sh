#!/bin/bash
set -e

echo "[TEST] Multi-block file (direct + indirect)"
make clean && make
./initdisk

DISK="mydisk.img"
BLOCK_SIZE=512
FILENAME="multi_block.txt"

# Construct content to span 10 blocks (8 direct + 2 indirect)
DATA_BLOCKS=10
CONTENT=$(head -c $((BLOCK_SIZE * DATA_BLOCKS)) < /dev/zero | tr '\0' 'A')

# Write data blocks: 8 direct (blocks 100, 110, 120, 130, 140, 150, 160, 170), 2 indirect (blocks 180, 190)
for i in {0..9}; do
  BLOCK=$((100 + 10*i))
  echo -n "${CONTENT:$((i * BLOCK_SIZE)):BLOCK_SIZE}" | dd of=$DISK bs=1 seek=$((BLOCK * BLOCK_SIZE)) conv=notrunc status=none
done

# Set up indirect block (block 250)
INDIRECT_BLOCK=$(for i in {8..9}; do
  BLOCK=$((100 + 10*i))
  printf "%08x" $BLOCK | sed -E 's/(..)(..)(..)(..)/\\x\4\\x\3\\x\2\\x\1/'
done)
printf "$INDIRECT_BLOCK" | dd of=$DISK bs=1 seek=$((250 * BLOCK_SIZE)) conv=notrunc status=none

# Set up inode
INODE_OFFSET=$((BLOCK_SIZE + 1 * 128))
dd if=/dev/zero bs=128 count=1 of=tmp_inode status=none
FILESIZE=$((BLOCK_SIZE * DATA_BLOCKS))
FILESIZE_HEX=$(printf "%08x" $FILESIZE | sed -E 's/(..)(..)(..)(..)/\\x\4\\x\3\\x\2\\x\1/')
printf "$FILESIZE_HEX" | dd of=tmp_inode bs=1 seek=0 conv=notrunc status=none   # file size
printf "\x00\x00\x00\x00" | dd of=tmp_inode bs=1 seek=4 conv=notrunc status=none  # is_dir = 0

# Direct block pointers
DIRECT_BLOCKS=$(for i in {0..7}; do
  BLOCK=$((100 + 10*i))
  printf "%08x" $BLOCK | sed -E 's/(..)(..)(..)(..)/\\x\4\\x\3\\x\2\\x\1/'
done)
printf "$DIRECT_BLOCKS" | dd of=tmp_inode bs=1 seek=8 conv=notrunc status=none

# Indirect pointer (block 250)
printf "\xFA\x00\x00\x00" | dd of=tmp_inode bs=1 seek=40 conv=notrunc status=none
printf "\x00\x00\x00\x00" | dd of=tmp_inode bs=1 seek=44 conv=notrunc status=none

dd if=tmp_inode of=$DISK bs=1 seek=$INODE_OFFSET conv=notrunc status=none
cat tmp_inode
rm tmp_inode

# Write directory entry in block 66
echo -n "$FILENAME" | dd of=$DISK bs=1 seek=$((66 * BLOCK_SIZE)) conv=notrunc status=none
printf "\x01\x00\x00\x00" | dd of=$DISK bs=1 seek=$((66 * BLOCK_SIZE + 60)) conv=notrunc status=none

# Update root inode
printf "\x48\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE)) conv=notrunc status=none
printf "\x01\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE + 4)) conv=notrunc status=none
printf "\x42\x00\x00\x00" | dd of=$DISK bs=1 seek=$((BLOCK_SIZE + 8)) conv=notrunc status=none

# Mount and test
mkdir -p testmount
./myfs -d testmount &
sleep 1

echo "[CHECK] Reading multi_block.txt"
ACTUAL=$(dd if=testmount/multi_block.txt bs=1 count=$FILESIZE status=none)
EXPECTED=$(printf "%.0sA" $(seq 1 $FILESIZE))

if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "[FAIL] Multi-block file content mismatch"
  fusermount -uz testmount
  exit 1
else
  echo "[PASS] Multi-block file test passed"
  fusermount -uz testmount
fi
