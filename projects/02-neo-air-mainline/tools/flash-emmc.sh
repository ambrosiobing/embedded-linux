#!/bin/sh
#
# flash-emmc.sh - copy the running SD system onto the eMMC.
#
# RUNS ON THE BOARD, booted from the microSD card. Not on the host.
#
#   sh flash-emmc.sh              provision the eMMC
#   sh flash-emmc.sh -n           print the plan, touch nothing
#
# A state machine with one function per state and a trap that names the
# state rather than the line. Every state is idempotent, so a failed run is
# recovered by rebooting from the SD card and running it again. Nothing
# here writes to the medium it booted from.
#
# THE THREE REFUSALS IN identify ARE THE SAFETY ARGUMENT:
#
#   no eMMC found                   nothing to do, and a guessed device is
#                                   the whole class of accident this
#                                   avoids
#   the target is mounted           writing a partition table under a
#                                   mounted filesystem corrupts it in a way
#                                   fsck reports and cannot explain
#   the target carries /            the specification's version omits this
#                                   one. On a board already booted from
#                                   eMMC the first two checks pass and the
#                                   script overwrites the system it is
#                                   running from
#
# The target is found by reading its type from sysfs, never by name. Block
# device names are assigned in probe order, so the eMMC is mmcblk1 on some
# kernels and mmcblk2 on others, and a script with a name in it eventually
# writes to the card it booted from.
#
# Testable without an eMMC: NEO_SYS, NEO_MOUNTS and NEO_ROOTDEV can be
# pointed at fixtures, and the target may be a loopback device. See
# tests/neo-air-flash-test.sh, which exercises all three refusals and the
# PARTUUID patching against loop devices.
#
# SPDX-License-Identifier: MIT

set -eu

SYS=${NEO_SYS:-/sys}
MOUNTS=${NEO_MOUNTS:-/proc/mounts}
BOOTLOADER=${NEO_BOOTLOADER:-/boot/u-boot-sunxi-with-spl.bin}
BOOTPART_MIB=${NEO_BOOTPART_MIB:-256}

# Where the new partitions are mounted while being filled. Overridable so
# that the copy, bootconfig and verify states can be exercised against a
# temporary directory instead of the real /mnt, which is the difference
# between a state machine that is tested and one that is read.
MNT1=${NEO_MNT1:-/mnt/e1}
MNT2=${NEO_MNT2:-/mnt/e2}

dry=no
case ${1:-} in
-n) dry=yes ;;
"") ;;
*)
	echo "usage: flash-emmc.sh [-n]" >&2
	exit 2
	;;
esac

STATE=start
# shellcheck disable=SC2154
# status is assigned at the head of this same trap body. shellcheck parses
# the quoted string without carrying the assignment across, so it reports
# a variable that is set one statement earlier.
trap 'status=$?; [ "$status" -eq 0 ] || echo "flash-emmc: failed in state $STATE" >&2' EXIT

die() {
	echo "flash-emmc: $1" >&2
	exit 1
}

note() {
	echo "--- $1"
}

# ----------------------------------------------------------- identify

identify() {
	STATE=identify

	EMMC=
	for block in "$SYS"/block/mmcblk*; do
		[ -r "$block/device/type" ] || continue
		[ "$(cat "$block/device/type")" = "MMC" ] || continue
		# More than one is not a situation to pick a winner in. The SD
		# card reports type SD, so two MMC devices means a board this
		# script was not written for.
		[ -z "$EMMC" ] || die "more than one MMC device: $EMMC and /dev/$(basename "$block").
       Refusing rather than choosing."
		EMMC=/dev/$(basename "$block")
	done

	[ -n "$EMMC" ] || die "no eMMC found under $SYS/block.
       Every mmcblk device there reports a type other than MMC, which is
       what an SD card reports. This board is booted from the card and
       has nothing else to provision."

	if grep -q "^$EMMC" "$MOUNTS"; then
		die "$EMMC is mounted:
$(grep "^$EMMC" "$MOUNTS" | sed 's/^/       /')
       Unmount it first. Writing a partition table under a mounted
       filesystem corrupts it in a way fsck reports and cannot explain."
	fi

	# The refusal the specification does not have. If this script is
	# somehow running on a system whose root is already on the eMMC, the
	# two checks above both pass, and the next state overwrites the
	# bootloader of the running system.
	rootdev=${NEO_ROOTDEV:-$(findmnt -n -o SOURCE / 2>/dev/null || echo "")}
	case $rootdev in
	"$EMMC"*)
		die "the running root is on $rootdev, which is this eMMC.
       This script copies the SD system to the eMMC and is being asked to
       copy the eMMC onto itself. Boot from the microSD card first."
		;;
	esac

	P1=${EMMC}p1
	P2=${EMMC}p2

	note "target     $EMMC  ($P1 boot, $P2 root)"
	note "root now   ${rootdev:-unknown}"
}

# --------------------------------------------------------- bootloader

bootloader() {
	STATE=bootloader
	[ -r "$BOOTLOADER" ] || die "no bootloader image at $BOOTLOADER.
       It is written to byte 8192 of the eMMC, which is where the SoC
       boot ROM looks for an eGON.BT0 header."
	note "bootloader $BOOTLOADER -> $EMMC at byte 8192"
	if [ "$dry" = yes ]; then
		return 0
	fi
	dd if="$BOOTLOADER" of="$EMMC" bs=1024 seek=8 conv=notrunc,fsync \
		status=none
}

# ---------------------------------------------------------- partition

partition() {
	STATE=partition
	# 2048 sectors is 1 MiB. The bootloader occupies byte 8192 onwards,
	# so anything starting below this overwrites it, and U-Boot then
	# overwrites the filesystem. The symptom is a board that stops after
	# the SPL banner, or a filesystem that will not mount.
	note "partition  p1 from sector 2048, ${BOOTPART_MIB} MiB, bootable; p2 the rest"
	if [ "$dry" = yes ]; then
		return 0
	fi
	printf 'label: dos\nstart=2048, size=%sMiB, type=83, bootable\nstart=, type=83\n' \
		"$BOOTPART_MIB" | sfdisk -q "$EMMC"
	# Give the kernel a moment to re-read the table before the next
	# state opens the partitions by name.
	partprobe "$EMMC" 2>/dev/null || true
	sync
}

# ------------------------------------------------------------- format

format() {
	STATE=format
	note "format     ext4 on $P1 (boot) and $P2 (root)"
	if [ "$dry" = yes ]; then
		return 0
	fi
	mkfs.ext4 -qF -L boot "$P1"
	mkfs.ext4 -qF -L root "$P2"
}

# --------------------------------------------------------------- copy

copy() {
	STATE=copy
	note "copy       / -> $P2 and /boot/ -> $P1"
	if [ "$dry" = yes ]; then
		return 0
	fi
	mkdir -p "$MNT1" "$MNT2"
	mount "$P1" "$MNT1"
	mount "$P2" "$MNT2"
	# --one-file-system, so /proc, /sys, /dev and the mounted target
	# itself are not copied into the copy.
	rsync -aHAX --one-file-system / "$MNT2/"
	rsync -a /boot/ "$MNT1/"
	sync
}

# --------------------------------------------------------- bootconfig

bootconfig() {
	STATE=bootconfig
	if [ "$dry" = yes ]; then
		note "bootconfig would patch extlinux.conf and fstab with the new PARTUUID"
		return 0
	fi

	id=$(blkid -s PARTUUID -o value "$P2")
	[ -n "$id" ] || die "no PARTUUID on $P2 after formatting it."
	note "bootconfig PARTUUID=$id"

	conf=$MNT1/extlinux/extlinux.conf
	[ -r "$conf" ] || die "no $conf on the new boot partition.
       It should have been copied from /boot by the previous state. The
       overlay ships it with the placeholder FILLED-BY-FLASH-EMMC, which
       is this state's job to replace."

	# Matches the placeholder and any previous value alike, so running
	# this script twice is not a special case.
	sed -i "s|root=PARTUUID=[^ ]*|root=PARTUUID=$id|" "$conf"
	grep -q "root=PARTUUID=$id" "$conf" ||
		die "patched $conf and the new PARTUUID is not in it."

	# Both fstab lines, each to its own eMMC partition. The tree copied from
	# the SD card carries the card's PARTUUIDs; left unpatched the eMMC would
	# mount the card's root and boot, which is the class of "boots the wrong
	# filesystem" that the impossible placeholder exists to prevent.
	bootid=$(blkid -s PARTUUID -o value "$P1")
	[ -n "$bootid" ] || die "no PARTUUID on $P1 after formatting it."
	note "bootconfig boot PARTUUID=$bootid"
	fstab=$MNT2/etc/fstab
	if [ -r "$fstab" ]; then
		sed -i "s|^PARTUUID=[^ ]*\( *\)/ |PARTUUID=$id\1/ |" "$fstab"
		sed -i "s|^PARTUUID=[^ ]*\( *\)/boot |PARTUUID=$bootid\1/boot |" "$fstab"
	fi
}

# ------------------------------------------------------------- verify

verify() {
	STATE=verify
	if [ "$dry" = yes ]; then
		return 0
	fi
	umount "$MNT1"
	umount "$MNT2"
	# -fn: force a check, answer no to every repair. This reports rather
	# than modifies, which is what a verification step should do.
	fsck.ext4 -fn "$P2" >/dev/null
	note "verify     fsck reports $P2 clean"
}

# --------------------------------------------------------------- main

identify
bootloader
partition
format
copy
bootconfig
verify

STATE="done"
trap - EXIT
if [ "$dry" = yes ]; then
	note "dry run, nothing written"
else
	note "eMMC provisioned. Power off, remove the SD card, power on."
	note "The boot ROM finds nothing on mmc0 and moves to mmc2."
fi
