# BlockFS

**A FUSE-based filesystem supporting hybrid block allocation (direct, single-indirect, and double-indirect pointers).**

BlockFS mounts a simulated disk image as a real, browsable virtual filesystem on Linux. It implements the core read path of a Unix-style filesystem — metadata lookup, file opening, and data reads — using the same hybrid block-allocation scheme found in filesystems like ext2: a small number of direct pointers for small files, a single-indirect block for medium files, and a double-indirect block for large files.

## Features

- **Hybrid block allocation** — direct, single-indirect, and double-indirect pointers, resolved transparently based on file offset
- **Custom FUSE syscall handlers** — `getattr`, `open`, and `read` implemented from scratch in C
- **Path resolution** — walks arbitrarily nested directory paths down to the target inode
- **512-byte block addressing** — all reads are translated from a logical file offset into the correct physical block(s) on disk
- **Supports files up to ~8MB** per inode, via nested indirection (8 direct blocks + 128 single-indirect + 128×128 double-indirect, at 512 bytes/block)

## How It Works

### Disk Layout

The entire filesystem lives in a single binary file (`mydisk.img`), laid out as:

```
+--------------------+
| Block 0            |  Superblock / metadata
+--------------------+
| Block 1 - 64       |  Inode table
+--------------------+
| Block 65+          |  Data blocks
|                    |
|   - File data      |
|   - Directory       |
|     entries        |
|   - Indirect /     |
|     double-indirect |
|     index tables   |
+--------------------+
```

### Inode Structure

Each inode is 128 bytes:

| Field             | Size     | Description                                  |
|-------------------|----------|-----------------------------------------------|
| `size`            | 4 bytes  | File/directory size in bytes                  |
| `is_dir`          | 4 bytes  | 1 if directory, 0 if regular file             |
| `direct[8]`       | 32 bytes | 8 direct pointers to data blocks              |
| `indirect`        | 4 bytes  | Pointer to a single-indirect block            |
| `double_indirect` | 4 bytes  | Pointer to a block of indirect-block pointers |
| *(reserved)*      | 80 bytes | Reserved for future use                       |

### Block Resolution

Given a file offset, BlockFS determines which of the three pointer tiers to use:

1. **Direct** — the first 8 blocks (≤ 4KB) are addressed directly from the inode.
2. **Single-indirect** — the next 64KB is addressed through one indirect block holding 128 pointers.
3. **Double-indirect** — anything beyond that is addressed through a block of 128 pointers, each pointing to its own single-indirect block of 128 pointers (128 × 128 blocks), extending capacity to ~8MB per file.

Path resolution (`cs1550_walk_path`) tokenizes an incoming path (e.g. `/dir1/file.txt`) and walks the directory tree from the root inode, matching directory entries by name until it resolves to the target inode.

## Project Structure

```
.
├── cs1550_fs_main.c       # FUSE operation implementations (getattr, open, read)
├── cs1550_fs_structs.h    # Inode and DirEntry struct definitions
├── mydisk.img             # Simulated disk image
├── Makefile
└── tests/                 # Test scripts (see Testing below)
```

## Build & Run

```bash
# Build
make all

# Mount the filesystem (foreground, with debug output)
make run
# equivalent to: ./myfs -d testmount/
```

Make sure `testmount/` exists and is empty before mounting.

To unmount:

```bash
make unmount
```

## Testing

A test suite validates block addressing, path resolution, and read correctness across all three pointer tiers:

```bash
make run-tests
```

This runs `run_all_tests.sh`, which covers:

- `test_small_file.sh` — direct-block-only reads
- `test_indirect_block.sh` — single-indirect addressing
- `test_double_indirect.sh` — double-indirect addressing
- `test_offset_read.sh` — reads at arbitrary byte offsets
- `test_multi_block.sh` — reads spanning multiple blocks
- `test_invalid_file.sh` — error handling for nonexistent paths

Each script mounts the filesystem against a known disk state, performs file operations (`cat`, `ls`, `dd`), and diffs the output against expected results.

To run a single test:

```bash
chmod +x tests/test_small_file.sh
./tests/test_small_file.sh
```

## Debugging

Build with debug symbols and step through with GDB:

```bash
make clean && make CFLAGS="-g"
gdb --args ./myfs -d testmount/
```

```
(gdb) break cs1550_getattr
(gdb) break cs1550_read
(gdb) run
```

To inspect raw disk contents directly:

```bash
hexdump -C mydisk.img | less
# or a specific block:
dd if=mydisk.img bs=512 skip=300 count=1 | hexdump -C
```

## Tech Stack

C · FUSE · Linux

## Scope & Limitations

BlockFS currently supports **read-only** operations (`getattr`, `open`, `read`). Write support, free-block allocation, and on-disk journaling would be natural next steps to extend it toward a fully read/write filesystem.
