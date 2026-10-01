# Makefile for CS 1550 Hybrid Block Filesystem Project

OBJS := cs1550_fs_main initdisk
MNTPNT := testmount
CFLAGS := -g3 -O0 -Wall -Wextra -Wno-unused-parameter $(shell pkg-config --cflags fuse)
LIBS := $(shell pkg-config --libs fuse)
USER := $(shell whoami)
DISK := mydisk.img

.PHONY: all clean unmount test run-tests

all: myfs $(DISK)

clean: unmount
	rm -rf myfs initdisk *.d $(DISK) $(MNTPNT)

$(DISK): initdisk
	./initdisk

unmount:
	-! pgrep myfs || killall -s 9 myfs
	-! fusermount -uz -o nonempty $(MNTPNT)

myfs: $(OBJS)
	$(CC) -o myfs cs1550_fs_main.c $(CFLAGS) $(LIBS)

run: myfs $(MNTPNT)
	./myfs -d $(MNTPNT)

run-tests: myfs $(MNTPNT)
	@chmod +x run_all_tests.sh
	@./run_all_tests.sh

-include $(OBJS:=.d)

$(MNTPNT):
	-mkdir $(MNTPNT)

%: %.c
	$(CC) $< $(CFLAGS) $(LIBS) -MMD -o $@
