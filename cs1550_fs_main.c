/*
 * CS 1550 Project: Hybrid Block Allocation Filesystem (Skeleton)
 * ----------------------------------------------------------------
 * In this assignment, you will implement a simple user-space filesystem
 * using FUSE with a hybrid block allocation method:
 * - Direct blocks (8 pointers)
 * - Single indirect block (points to up to 128 blocks)
 * - Double indirect block (points to 128 indirect blocks)
 *
 * You are responsible for implementing the following functions:
 * - cs1550_getattr
 * - cs1550_open
 * - cs1550_read
 *
 * You will also use cs1550_walk_path as a helper to resolve paths.
 *
 * All shared structures are in the cs1550_fs_structs.h header file.
 */

 #define FUSE_USE_VERSION 29
 #include <fuse.h>
 #include <stdio.h>
 #include <string.h>
 #include <errno.h>
 #include <fcntl.h>
 #include <stdlib.h>
 #include "cs1550_fs_structs.h"
 
 const char *disk_path = "mydisk.img";
 
 static int search_block(FILE *fp, uint32_t blk, const char *name, int epb) {
    if (blk == 0) return -1;
    DirEntry entries[epb];
    fseek(fp, (long)blk * BLOCK_SIZE, SEEK_SET);
    fread(entries, sizeof(DirEntry), epb, fp);
    for (int e = 0; e < epb; e++) {
        if (entries[e].name[0] == '\0') continue;
        if (strcmp(entries[e].name, name) == 0)
            return (int)entries[e].inode_idx;
    }
    return -1;
}

 // TODO: Implement this helper function to resolve a full path to an inode index
int cs1550_walk_path(const char *path, Inode *inodes) {
    if (strcmp(path, "/") == 0)
        return 0;

    char temp[512];
    strncpy(temp, path, sizeof(temp)-1);
    temp[sizeof(temp)-1] = '\0';

    int curr_inode_idx = 0;
    int epb = BLOCK_SIZE / sizeof(DirEntry);

    char *token = strtok(temp, "/");
    while (token != NULL) {
        Inode *cur = &inodes[curr_inode_idx];
        if (!cur->is_dir) return -ENOTDIR;

        int found = 0;
        int result = -1;

        FILE *fp = fopen(disk_path, "rb");
        if (!fp) return -EIO;

        for (int b = 0; b < NUM_DIRECT && !found; b++) {
            result = search_block(fp, cur->direct_blocks[b], token, epb);
            if (result >= 0) { curr_inode_idx = result; found = 1; }
        }

        if (!found && cur->indirect_block) {
            uint32_t ind[INDIRECT_PTRS];
            fseek(fp, (long)cur->indirect_block * BLOCK_SIZE, SEEK_SET);
            fread(ind, sizeof(uint32_t), INDIRECT_PTRS, fp);
            for (int i = 0; i < INDIRECT_PTRS && !found; i++) {
                result = search_block(fp, ind[i], token, epb);
                if (result >= 0) { curr_inode_idx = result; found = 1; }
            }
        }

        if (!found && cur->double_indirect_block) {
            uint32_t outer[INDIRECT_PTRS];
            fseek(fp, (long)cur->double_indirect_block * BLOCK_SIZE, SEEK_SET);
            fread(outer, sizeof(uint32_t), INDIRECT_PTRS, fp);
            for (int i = 0; i < INDIRECT_PTRS && !found; i++) {
                if (!outer[i]) continue;
                uint32_t inner[INDIRECT_PTRS];
                fseek(fp, (long)outer[i] * BLOCK_SIZE, SEEK_SET);
                fread(inner, sizeof(uint32_t), INDIRECT_PTRS, fp);
                for (int j = 0; j < INDIRECT_PTRS && !found; j++) {
                    result = search_block(fp, inner[j], token, epb);
                    if (result >= 0) { curr_inode_idx = result; found = 1; }
                }
            }
        }

        fclose(fp);
        if (!found) return -ENOENT;
        token = strtok(NULL, "/");
    }

    return curr_inode_idx;
}

 static int read_inodes(Inode inodes[MAX_INODES]) {
    memset(inodes, 0, sizeof(Inode) * MAX_INODES);
    FILE *fp = fopen(disk_path, "rb");
    if (!fp) return -EIO;
    fseek(fp, 1 * BLOCK_SIZE, SEEK_SET);
    fread(inodes, sizeof(Inode), MAX_INODES, fp);
    fclose(fp);
    return 0;
 }
 
 int cs1550_getattr(const char *path, struct stat *stbuf) {
     memset(stbuf, 0, sizeof(struct stat));

     if (strcmp(path, "/") == 0) {
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
        return 0;
    }
 
    Inode inodes[MAX_INODES];
    if (read_inodes(inodes) != 0)
        return -EIO;

    int idx = cs1550_walk_path(path, inodes);
    if (idx < 0)
        return idx;

    Inode *node = &inodes[idx];

    if (node->is_dir) {
        stbuf->st_mode  = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
        stbuf->st_size  = (off_t)node->size;
    } else {
        stbuf->st_mode  = S_IFREG | 0444;
        stbuf->st_nlink = 1;
        stbuf->st_size  = (off_t)node->size;
    }
 
     return 0; // or appropriate error code
 }
 
 int cs1550_open(const char *path, struct fuse_file_info *fi) {
    (void)fi;

    Inode inodes[MAX_INODES];
    if (read_inodes(inodes) != 0)
        return -EIO;

    int idx = cs1550_walk_path(path, inodes);
    if (idx < 0)
        return -ENOENT;

    if (inodes[idx].is_dir)
        return -EISDIR;

    return 0;
 }
 
 int cs1550_read(const char *path, char *buf, size_t size, off_t offset, struct fuse_file_info *fi) {
     (void)fi;

    if (size == 0) 
        return 0;

    Inode inodes[MAX_INODES];
    if (read_inodes(inodes) != 0)
        return -EIO;

    int idx = cs1550_walk_path(path, inodes);
    if (idx < 0)
        return -ENOENT;

    Inode *node = &inodes[idx];

    if (node->is_dir)
        return -EISDIR;

    if (offset >= (off_t)node->size)
        return 0;

    if (offset + (off_t)size > (off_t)node->size)
        size = (size_t)(node->size - offset);

    size_t bytes_read = 0;

    while (bytes_read < size) {
        off_t curr_off = offset + (off_t)bytes_read;
        int logic_block = (int)(curr_off / BLOCK_SIZE);
        int block_off = (int)(curr_off % BLOCK_SIZE);
        int avail = BLOCK_SIZE - block_off;
        int to_copy = (int)(size - bytes_read);
        if (to_copy > avail) to_copy = avail;

        uint32_t phys_block = 0;

        if (logic_block < NUM_DIRECT) {
            phys_block = node->direct_blocks[logic_block];

        } else if (logic_block < NUM_DIRECT + INDIRECT_PTRS) {
            if (node->indirect_block == 0) 
                return -EIO;

            uint32_t indirect_table[INDIRECT_PTRS];
            FILE *fp = fopen(disk_path, "rb");
            if (!fp) 
                return -EIO;
            fseek(fp, (long)node->indirect_block * BLOCK_SIZE, SEEK_SET);
            fread(indirect_table, sizeof(uint32_t), INDIRECT_PTRS, fp);
            fclose(fp);

            int slot = logic_block - NUM_DIRECT;
            phys_block = indirect_table[slot];

        } else {
            if (node->double_indirect_block == 0) 
                return -EIO;

            int dbl_logic = logic_block - NUM_DIRECT - INDIRECT_PTRS;
            int outer_slot  = dbl_logic / INDIRECT_PTRS;
            int inner_slot  = dbl_logic % INDIRECT_PTRS;

            uint32_t dbl_outer[INDIRECT_PTRS];
            FILE *fp = fopen(disk_path, "rb");
            if (!fp) 
                return -EIO;
            fseek(fp, (long)node->double_indirect_block * BLOCK_SIZE, SEEK_SET);
            fread(dbl_outer, sizeof(uint32_t), INDIRECT_PTRS, fp);
            fclose(fp);

            uint32_t inner_blk = dbl_outer[outer_slot];
            if (inner_blk == 0) 
                return -EIO;

            uint32_t dbl_inner[INDIRECT_PTRS];
            FILE *fp2 = fopen(disk_path, "rb");
            if (!fp2) return -EIO;
            fseek(fp2, (long)inner_blk * BLOCK_SIZE, SEEK_SET);
            fread(dbl_inner, sizeof(uint32_t), INDIRECT_PTRS, fp2);
            fclose(fp2);

            phys_block = dbl_inner[inner_slot];
        }

        if (phys_block == 0) 
            return -EIO;

        char block_buf[BLOCK_SIZE];
        FILE *fp = fopen(disk_path, "rb");
        if (!fp) 
            return -EIO;
        fseek(fp, (long)phys_block * BLOCK_SIZE, SEEK_SET);
        fread(block_buf, 1, BLOCK_SIZE, fp);
        fclose(fp);

        memcpy(buf + bytes_read, block_buf + block_off, to_copy);
        bytes_read += (size_t)to_copy;
    }

    return (int)bytes_read;
 }
 
 static struct fuse_operations fs_ops = {
     .getattr = cs1550_getattr,
     .open = cs1550_open,
     .read = cs1550_read
 };
 
 int main(int argc, char *argv[]) {
     return fuse_main(argc, argv, &fs_ops, NULL);
 }
 