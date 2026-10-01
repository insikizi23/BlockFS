#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cs1550_fs_structs.h"

#define DISK_NAME "mydisk.img"
#define INODE_TABLE_BLOCKS 64
#define TOTAL_BLOCKS 1024
#define ROOT_INODE_IDX 0

int main() {
    FILE *fp = fopen(DISK_NAME, "wb");
    if (!fp) {
        perror("Failed to create disk");
        return 1;
    }

    // Initialize all blocks to 0
    char zero[BLOCK_SIZE] = {0};
    for (int i = 0; i < TOTAL_BLOCKS; i++) {
        fwrite(zero, 1, BLOCK_SIZE, fp);
    }

    // Prepare root directory inode
    Inode root;
    memset(&root, 0, sizeof(Inode));
    root.size = 0;
    root.is_dir = 1;

    fseek(fp, BLOCK_SIZE, SEEK_SET); // Write to first inode (block 1)
    fwrite(&root, sizeof(Inode), 1, fp);

    printf("Initialized disk with root directory.\n");
    fclose(fp);
    return 0;
}
