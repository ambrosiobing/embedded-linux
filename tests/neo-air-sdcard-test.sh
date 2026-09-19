#!/bin/sh
#
# neo-air-sdcard-test.sh - writing the development medium, without a card.
#
# sdcard.sh is the host half of the pair that can erase the wrong device.
# flash-emmc.sh runs on the board and can only reach the eMMC; this one
# runs on a laptop with a system disk in it, which makes it the more
# dangerous of the two.
#
# Everything destructive is a stub that records instead of writing, and the
# device is an ordinary file, so this runs anywhere.
#
# THE ORDER ASSERTION IS THE ONE WORTH HAVING. sfdisk writes sector 0, so
# a bootloader written before the partition table loses its first 512
# bytes to it. The eGON.BT0 header at byte 8192 survives either order and
# the SPL that follows does not, which means the wrong order produces a
# board that reads its header, starts, and dies without a message.
#
#   sh tests/neo-air-sdcard-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROJ=$ROOT/projects/02-neo-air-mainline
SUT=$PROJ/tools/sdcard.sh

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

CALLS=$WORK/calls
mkdir -p "$WORK/bin"
PATH=$WORK/bin:$PATH
export PATH

pass=0
fail=0

check() {
	if [ "$2" = "$3" ]; then
		echo "ok       $1"
		pass=$((pass + 1))
	else
		echo "FAILED   $1: wanted '$3', got '$2'"
		fail=$((fail + 1))
	fi
}

contains() {
	case $2 in
	*"$3"*)
		echo "ok       $1"
		pass=$((pass + 1))
		;;
	*)
		echo "FAILED   $1: '$3' not in output"
		echo "$2" | sed 's/^/           /'
		fail=$((fail + 1))
		;;
	esac
}

has_file() {
	if [ -f "$2" ]; then
		echo "ok       $1"
		pass=$((pass + 1))
	else
		echo "FAILED   $1: $2 does not exist"
		fail=$((fail + 1))
	fi
}

for tool in dd mkfs.ext4 partprobe mount umount sync; do
	cat >"$WORK/bin/$tool" <<EOF
#!/bin/sh
echo "$tool \$*" >>"$CALLS"
exit 0
EOF
	chmod +x "$WORK/bin/$tool"
done

# tar is not a pure no-op: sdcard.sh patches /etc/fstab inside the extracted
# tree, and a stub that extracts nothing would let that patch be tested
# against a file that is not there, which is a check passing on absence
# rather than on the fix. So the stub lays down the one file the script
# then edits, with the placeholder the overlay really ships.
cat >"$WORK/bin/tar" <<EOF
#!/bin/sh
echo "tar \$*" >>"$CALLS"
dest=
while [ \$# -gt 0 ]; do
	case \$1 in -C) dest=\$2; shift 2 ;; *) shift ;; esac
done
if [ -n "\$dest" ]; then
	mkdir -p "\$dest/etc"
	printf 'PARTUUID=FILLED-BY-FLASH-EMMC / ext4 defaults,noatime 0 1\n' \
		>"\$dest/etc/fstab"
fi
exit 0
EOF
chmod +x "$WORK/bin/tar"

cat >"$WORK/bin/sfdisk" <<EOF
#!/bin/sh
echo "sfdisk \$*" >>"$CALLS"
sed 's/^/sfdisk-stdin: /' >>"$CALLS"
exit 0
EOF
chmod +x "$WORK/bin/sfdisk"

cat >"$WORK/bin/blkid" <<EOF
#!/bin/sh
echo "blkid \$*" >>"$CALLS"
echo "11223344-02"
EOF
chmod +x "$WORK/bin/blkid"

# ---------------------------------------------------------- the fixtures

OUT=$WORK/out
build_out() {
	rm -rf "$OUT"
	mkdir -p "$OUT"
	for f in u-boot-sunxi-with-spl.bin zImage sun8i-h3-nanopi-neo-air.dtb; do
		printf 'placeholder\n' >"$OUT/$f"
	done
	printf 'placeholder\n' >"$OUT/rootfs.tar"
}

reset() {
	: >"$CALLS"
	build_out
	rm -rf "$WORK/sys" "$WORK/mnt1" "$WORK/mnt2"
	mkdir -p "$WORK/sys/block/sdz" "$WORK/mnt1" "$WORK/mnt2"
	printf '1\n' >"$WORK/sys/block/sdz/removable"
	printf 'device\n' >"$WORK/sdz"
}

run() {
	dev=$1
	shift
	NEO_ENV=1 \
		NEO_OUT=$OUT \
		NEO_SYS=$WORK/sys \
		NEO_MNT1=$WORK/mnt1 \
		NEO_MNT2=$WORK/mnt2 \
		NEO_SKIP_BLOCK_CHECK=1 \
		BOARD_DTB=sun8i-h3-nanopi-neo-air.dtb \
		sh "$SUT" "$@" "$dev" 2>&1
}

# ------------------------------------------------------- the refusals

reset
rc=0
out=$(NEO_ENV=1 sh "$SUT" 2>&1) || rc=$?
check "no device is a refusal" "$rc" "1"
contains "and says the device is never guessed" "$out" "never guessed"

reset
rc=0
out=$(run /dev/sda) || rc=$?
check "the system disk is refused by name" "$rc" "1"
contains "and says so plainly" "$out" "very likely the system disk"

reset
rc=0
out=$(NEO_OUT=$OUT sh "$SUT" /dev/sdz 2>&1) || rc=$?
check "an unsourced toolchain.env is a refusal" "$rc" "1"
contains "and names the entry point that sources it" "$out" "./go neo-air card"

# The kernel's own answer, not the name's. An internal disk reports 0 here
# and a card reader reports 1, which is a better question than whether the
# path begins with sd.
reset
printf '0\n' >"$WORK/sys/block/sdz/removable"
rc=0
out=$(run /dev/sdz) || rc=$?
check "removable=0 is a refusal" "$rc" "1"
contains "and quotes the file it read" "$out" "removable=0"

reset
rm -f "$OUT/zImage"
rc=0
out=$(run /dev/sdz) || rc=$?
check "a missing kernel is a refusal" "$rc" "1"
contains "and names the script that makes it" "$out" "kernel/build.sh"

reset
rm -f "$OUT/rootfs.tar"
rc=0
out=$(run /dev/sdz) || rc=$?
check "a missing rootfs is a refusal" "$rc" "1"
contains "and names mkrootfs.sh" "$out" "mkrootfs.sh"

# --------------------------------------------------------- the dry run

reset
out=$(run /dev/sdz -n)
contains "the dry run reports the layout" "$out" "byte 8192"
contains "and the start sector" "$out" "sector 2048"
check "and writes nothing" "$(wc -l <"$CALLS" | tr -d ' ')" "0"

# ---------------------------------------------------- the confirmation

reset
rc=0
out=$(printf 'yes\n' | run /dev/sdz) || rc=$?
check "a confirmation that is not the device path stops it" "$rc" "1"
contains "and says what was typed" "$out" "you typed 'yes'"
check "and nothing was written" "$(wc -l <"$CALLS" | tr -d ' ')" "0"

# ------------------------------------------------------- the real path

reset
out=$(printf '/dev/sdz\n' | run /dev/sdz)
calls=$(cat "$CALLS")

contains "the first megabyte is cleared" "$calls" "of=/dev/sdz bs=1M count=1"
contains "the table starts the first partition at sector 2048" \
	"$calls" "sfdisk-stdin: start=2048"
contains "the bootloader lands at byte 8192" "$calls" "seek=8"
contains "with a 1024 byte block" "$calls" "bs=1024"

# The ordering. sfdisk writes sector 0; a bootloader written first would
# lose its first 512 bytes to it.
# Anchored on the command name, not on a guess at its arguments. The first
# version of this matched "sfdisk /dev/sdz" and the stub records
# "sfdisk -q /dev/sdz", so the pattern found nothing, the comparison ran
# against one line number and the assertion failed on a script that was
# doing exactly the right thing.
sfdisk_line=$(grep -n '^sfdisk ' "$CALLS" | head -n 1 | cut -d: -f1)
spl_line=$(grep -n 'seek=8' "$CALLS" | head -n 1 | cut -d: -f1)
order="sfdisk at $sfdisk_line, bootloader at $spl_line"
if [ -n "$sfdisk_line" ] && [ -n "$spl_line" ] &&
	[ "$sfdisk_line" -lt "$spl_line" ]; then
	echo "ok       the partition table is written BEFORE the bootloader"
	pass=$((pass + 1))
else
	echo "FAILED   the partition table is written BEFORE the bootloader"
	echo "         sfdisk writes sector 0, so a bootloader written first"
	echo "         loses its first 512 bytes and the board dies after"
	echo "         reading its header. call order was: $order"
	fail=$((fail + 1))
fi

# Partition naming. /dev/sdb1 but /dev/mmcblk0p1, and a laptop with a
# built-in slot enumerates its reader as an mmcblk device.
contains "a plain device gets numbered partitions" "$calls" "mkfs.ext4 -qF -L boot /dev/sdz1"

reset
mkdir -p "$WORK/sys/block/mmcblk9"
printf '1\n' >"$WORK/sys/block/mmcblk9/removable"
out=$(printf '/dev/mmcblk9\n' | run /dev/mmcblk9)
contains "a device ending in a digit gets p-numbered partitions" \
	"$(cat "$CALLS")" "mkfs.ext4 -qF -L boot /dev/mmcblk9p1"

# --------------------------------------------------- what landed on p1

reset
out=$(printf '/dev/sdz\n' | run /dev/sdz)
conf=$WORK/mnt1/extlinux/extlinux.conf
has_file "extlinux.conf is on the boot partition" 	"$WORK/mnt1/extlinux/extlinux.conf"
contains "and carries the card's own PARTUUID, not the placeholder" \
	"$(cat "$conf")" "root=PARTUUID=11223344-02"
has_file "the bootloader travels on the card for flash-emmc.sh to read" \
	"$WORK/mnt1/u-boot-sunxi-with-spl.bin"
has_file "so does the dtb" "$WORK/mnt1/sun8i-h3-nanopi-neo-air.dtb"

# /etc/fstab in the extracted rootfs gets the same PARTUUID as extlinux.conf.
# This is the fix for a real failure: the placeholder was patched in
# extlinux.conf and left in fstab, so the first boot reached userspace and
# then systemd-remount-fs.service failed on a root whose PARTUUID does not
# exist. The stub laid down the placeholder; the script must have replaced it.
fstab=$WORK/mnt2/etc/fstab
has_file "fstab is in the extracted rootfs" "$fstab"
contains "and carries the card's PARTUUID, not the placeholder" \
	"$(cat "$fstab")" "PARTUUID=11223344-02"
absent=$(grep -c 'FILLED-BY-FLASH-EMMC' "$fstab" || true)
check "the fstab placeholder is gone" "$absent" "0"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
