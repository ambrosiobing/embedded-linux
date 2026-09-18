#!/bin/sh
#
# sdcard.sh - write the development medium: bootloader, kernel, dtb,
# extlinux and the root filesystem onto a microSD card.
#
# RUNS ON THE HOST, with the card in a reader. Not on the board.
#
#   . projects/02-neo-air-mainline/toolchain.env
#   sudo -E sh projects/02-neo-air-mainline/tools/sdcard.sh /dev/sdX
#   sudo -E sh projects/02-neo-air-mainline/tools/sdcard.sh -n /dev/sdX
#
# THE DEVICE IS NEVER GUESSED. It is an argument, it is checked against a
# list of things that are almost certainly not a card, and the operator
# types it a second time to confirm. That last step exists because the
# first thing anyone does after "it did not work" is press the up arrow,
# and the up arrow is how the wrong device gets written twice.
#
# The layout, and the two numbers that matter:
#
#   byte 8192      u-boot-sunxi-with-spl.bin      where the SoC boot ROM
#                                                 looks for eGON.BT0
#   sector 2048    partition 1, 256 MiB, ext4     1 MiB in, clear of the
#                  label boot: zImage, dtb,       bootloader by a wide
#                  extlinux/extlinux.conf         margin
#   after that     partition 2, ext4, label root  the Debian system
#
# A partition starting below sector 2048 overwrites U-Boot, and U-Boot
# overwrites the partition. The symptom is not an error message: the board
# stops after the SPL banner, or the filesystem will not mount.
#
# SPDX-License-Identifier: MIT

set -eu

SYS=${NEO_SYS:-/sys}
BOOTPART_MIB=${NEO_BOOTPART_MIB:-256}
MNT1=${NEO_MNT1:-/mnt/sd1}
MNT2=${NEO_MNT2:-/mnt/sd2}

die() {
	echo "sdcard: $1" >&2
	exit 1
}

note() {
	echo "--- $1"
}

dry=no
case ${1:-} in
-n)
	dry=yes
	shift
	;;
esac

DEV=${1:-}
[ -n "$DEV" ] || die "usage: sdcard.sh [-n] /dev/sdX
       lsblk lists the candidates. The device is never guessed."

[ "${NEO_ENV:-}" = 1 ] || die "toolchain.env has not been sourced.
       . projects/02-neo-air-mainline/toolchain.env
       sudo keeps its own environment, so use sudo -E."

# ------------------------------------------------------- what it refuses

case $DEV in
/dev/sda | /dev/nvme0n1 | /dev/vda | /dev/mmcblk0)
	die "$DEV is very likely the system disk. Refusing."
	;;
/dev/*) ;;
*)
	die "$DEV does not look like a device path."
	;;
esac

# Removable, according to the kernel rather than according to the name. A
# card reader reports 1 here and an internal disk reports 0, which is a
# better question than "does the name start with sd".
base=$(basename "$DEV")
removable=$SYS/block/$base/removable
if [ -r "$removable" ] && [ "$(cat "$removable")" != "1" ]; then
	die "$DEV reports removable=0 in $removable, so it is not a card
       reader. Refusing rather than asking you to be sure."
fi

if [ "${NEO_SKIP_BLOCK_CHECK:-}" != 1 ]; then
	[ -b "$DEV" ] || die "$DEV is not a block device."
fi

# ------------------------------------------------------------- the parts

for f in u-boot-sunxi-with-spl.bin zImage "$BOARD_DTB"; do
	[ -r "$NEO_OUT/$f" ] || die "missing $NEO_OUT/$f
       Run the build scripts first: uboot/build.sh and kernel/build.sh."
done

ROOTFS=${NEO_ROOTFS:-$NEO_OUT/rootfs.tar}
[ -r "$ROOTFS" ] || die "missing $ROOTFS
       Run rootfs/mkrootfs.sh first."

HERE=$(cd "$(dirname "$0")" && pwd)
EXTLINUX=$HERE/../rootfs/overlay/boot/extlinux/extlinux.conf
[ -r "$EXTLINUX" ] || die "missing $EXTLINUX"

note "device     $DEV"
note "bootloader $NEO_OUT/u-boot-sunxi-with-spl.bin -> byte 8192"
note "partition  p1 at sector 2048, ${BOOTPART_MIB} MiB; p2 the rest"
note "rootfs     $ROOTFS"

if [ "$dry" = yes ]; then
	note "dry run, nothing written"
	exit 0
fi

# ------------------------------------------------------ the confirmation

printf 'Everything on %s will be erased. Type the device path to continue: ' "$DEV"
read -r answer
[ "$answer" = "$DEV" ] || die "you typed '$answer', not '$DEV'. Nothing written."

# --------------------------------------------------------------- write

note "clearing the first megabyte, which holds any old partition table"
dd if=/dev/zero of="$DEV" bs=1M count=1 conv=fsync status=none

note "partitioning"
printf 'label: dos\nstart=2048, size=%sMiB, type=83, bootable\nstart=, type=83\n' \
	"$BOOTPART_MIB" | sfdisk -q "$DEV"
partprobe "$DEV" 2>/dev/null || true
sync

# The bootloader goes on AFTER the partition table, not before. sfdisk
# writes the first sector, and a bootloader written first would lose its
# first 512 bytes to it. The eGON.BT0 header lives at byte 8192 and
# survives either order, but the SPL that follows does not.
note "writing the bootloader at byte 8192"
dd if="$NEO_OUT/u-boot-sunxi-with-spl.bin" of="$DEV" bs=1024 seek=8 \
	conv=notrunc,fsync status=none

# Partition device names: /dev/sdb1, but /dev/mmcblk0p1. Derive rather
# than assume, because a reader that enumerates as an mmcblk device is
# ordinary on a laptop with a built-in slot.
case $DEV in
*[0-9]) P1=${DEV}p1; P2=${DEV}p2 ;;
*) P1=${DEV}1; P2=${DEV}2 ;;
esac

note "formatting $P1 and $P2"
mkfs.ext4 -qF -L boot "$P1"
mkfs.ext4 -qF -L root "$P2"

note "filling"
mkdir -p "$MNT1" "$MNT2"
mount "$P1" "$MNT1"
mount "$P2" "$MNT2"

mkdir -p "$MNT1/extlinux"
cp "$NEO_OUT/zImage" "$MNT1/"
cp "$NEO_OUT/$BOARD_DTB" "$MNT1/"
cp "$EXTLINUX" "$MNT1/extlinux/extlinux.conf"
# The board is provisioned from this card, so the bootloader image has to
# travel on it: flash-emmc.sh reads it from /boot.
cp "$NEO_OUT/u-boot-sunxi-with-spl.bin" "$MNT1/"

tar -xf "$ROOTFS" -C "$MNT2"

# The SD card's own PARTUUID, so this card boots before anything has run
# flash-emmc.sh. The overlay's placeholder is for the eMMC copy; this is
# the same substitution done here for the card itself.
id=$(blkid -s PARTUUID -o value "$P2")
[ -n "$id" ] || die "no PARTUUID on $P2 after formatting it."
sed -i "s|root=PARTUUID=[^ ]*|root=PARTUUID=$id|" "$MNT1/extlinux/extlinux.conf"
grep -q "root=PARTUUID=$id" "$MNT1/extlinux/extlinux.conf" ||
	die "patched extlinux.conf and the new PARTUUID is not in it."
note "root       PARTUUID=$id"

sync
umount "$MNT1"
umount "$MNT2"

note "done. Insert the card, attach the console cable, start picocom, then power on."
note "  picocom -b 115200 /dev/ttyUSB0"
note "The first thing on the console is 'U-Boot SPL', within about a second."
