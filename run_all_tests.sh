#!/bin/bash
echo "Running all CS 1550 FS tests..."
echo "==============================="

PASS=0
FAIL=0

for script in test_small_file.sh test_indirect_block.sh test_invalid_file.sh test_offset_read.sh test_double_indirect.sh test_multi_block.sh; do
    echo "[RUNNING] $script"
    bash $script
    if [ $? -eq 0 ]; then
        PASS=$((PASS + 1))
    else
        echo "[ERROR] Test $script failed."
        FAIL=$((FAIL + 1))
    fi
    echo "--------------------------------"
done

echo "SUMMARY: $PASS passed, $FAIL failed."
exit $FAIL
