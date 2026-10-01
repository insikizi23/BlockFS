#ifndef CS1550_FS_STRUCTS_H
#define CS1550_FS_STRUCTS_H

#include <stdint.h>

#define MAX_INODES 64
#define MAX_NAME_LEN 60
#define BLOCK_SIZE 512
#define NUM_DIRECT 8
#define INDIRECT_PTRS 128

typedef struct {
    uint32_t size;                        // 4 bytes
    uint32_t is_dir;                      // 4 bytes
    uint32_t direct_blocks[8];       // 32 bytes
    uint32_t indirect_block;         // 4 bytes
    uint32_t double_indirect_block;  // 4 bytes
    char padding[80];                // pad to 128 total
} Inode;

typedef struct {
    char name[MAX_NAME_LEN];             // 64 bytes
    uint32_t inode_idx;              // 4 bytes
} DirEntry;

_Static_assert(sizeof(Inode) == 128, "Inode must be 128 bytes");
_Static_assert(sizeof(DirEntry) == 64, "DirEntry must be 64 bytes");

#endif // CS1550_FS_STRUCTS_H