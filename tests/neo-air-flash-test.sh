#!/bin/sh
#
# neo-air-flash-test.sh - the eMMC provisioning state machine, without an
# eMMC.
#
# flash-emmc.sh is the one program in Project 2 that can destroy the system
# it is running on. It runs on the board exactly twice in the project's
# life, once to provision and once to prove it is idempotent, and both
# times it is being trusted rather than tested.
#
# So it is tested here instead, and everything it needs is replaceable:
#
#   NEO_SYS        a fake /sys/block tree, so the target is discovered the
#                  way the real one is, by reading device/type
#   NEO_MOUNTS     a fake /proc/mounts
#   NEO_ROOTDEV    what findmnt would have said
#   NEO_MNT1/2     a temporary directory instead of /mnt
#   PATH           stubs that record their arguments instead of writing to
#                  a block device
#
# No root, no loop devices, no board. Runs anywhere with a POSIX shell.
#
#   sh tests/neo-air-flash-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/projects/02-neo-air-mainline/tools/flash-emmc.sh

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

absent() {
	case $2 in
	*"$3"*)
		echo "FAILED   $1: '$3' is in the output and should not be"
		fail=$((fail + 1))
		;;
	*)
		echo "ok       $1"
		pass=$((pass + 1))
		;;
	esac
}

# ------------------------------------------------------------- the stubs
#
# Each records its whole argument list and succeeds. dd is special: it can
# be made to fail, so that the trap's state reporting can be checked.

for tool in dd mkfs.ext4 partprobe mount umount rsync fsck.ext4 sync; do
	cat >"$WORK/bin/$tool" <<EOF
#!/bin/sh
echo "$tool \$*" >>"$CALLS"
if [ -n "\${FAIL_$(printf '%s' "$tool" | tr -c 'A-Za-z0-9' '_'):-}" ]; then
	exit 1
fi
exit 0
EOF
	chmod +x "$WORK/bin/$tool"
done

# sfdisk gets its own stub, because it is configured through stdin rather
# than through its arguments. The partition table is piped to it, so the
# single most important number in this project, the start sector 2048 that
# keeps the first partition clear of the bootloader at byte 8192, is
# invisible to a stub that records only argv.
#
# The first version of this file used the generic stub and the assertion
# for sector 2048 failed while the script was doing exactly the right
# thing. A stub that captures less than the program consumes will report a
# correct program as broken, and on the next reading somebody weakens the
# assertion rather than the stub.
cat >"$WORK/bin/sfdisk" <<EOF
#!/bin/sh
echo "sfdisk \$*" >>"$CALLS"
sed 's/^/sfdisk-stdin: /' >>"$CALLS"
if [ -n "\${FAIL_sfdisk:-}" ]; then
	exit 1
fi
exit 0
EOF
chmod +x "$WORK/bin/sfdisk"

# blkid has to answer, not just record: bootconfig reads its output.
cat >"$WORK/bin/blkid" <<EOF
#!/bin/sh
echo "blkid \$*" >>"$CALLS"
case \$* in
*p1) echo "aabbccdd-01" ;;
*)   echo "aabbccdd-02" ;;
esac
EOF
chmod +x "$WORK/bin/blkid"

# ---------------------------------------------------------- the fixtures

# card_and_emmc SD_TYPE EMMC_TYPE
# Builds a fake /sys/block with two devices. The real board reports SD for
# the card and MMC for the eMMC, and the script picks by that and never by
# name, because names are assigned in probe order.
build_sys() {
	rm -rf "$WORK/sys"
	mkdir -p "$WORK/sys/block/mmcblk0/device" "$WORK/sys/block/mmcblk1/device"
	printf '%s\n' "${1:-SD}" >"$WORK/sys/block/mmcblk0/device/type"
	printf '%s\n' "${2:-MMC}" >"$WORK/sys/block/mmcblk1/device/type"
}

build_boot() {
	rm -rf "$WORK/mnt1" "$WORK/mnt2"
	mkdir -p "$WORK/mnt1/extlinux" "$WORK/mnt2/etc"
	# What the overlay ships: a placeholder that cannot boot, on purpose.
	cat >"$WORK/mnt1/extlinux/extlinux.conf" <<'EOF'
default mainline
timeout 1
label mainline
    kernel /zImage
    fdt /sun8i-h3-nanopi-neo-air.dtb
    append console=ttyS0,115200 root=PARTUUID=FILLED-BY-FLASH-EMMC rootwait rw
EOF
	printf 'PARTUUID=old-value / ext4 defaults 0 1\n' >"$WORK/mnt2/etc/fstab"
	printf 'PARTUUID=old-boot /boot ext4 defaults 0 2\n' >>"$WORK/mnt2/etc/fstab"
}

reset() {
	: >"$CALLS"
	build_sys "${1:-SD}" "${2:-MMC}"
	build_boot
	printf 'PLACEHOLDER BOOTLOADER\n' >"$WORK/u-boot.bin"
	printf '/dev/mmcblk0p2 / ext4 rw 0 0\n' >"$WORK/mounts"
}

run() {
	NEO_SYS=$WORK/sys \
		NEO_MOUNTS=$WORK/mounts \
		NEO_ROOTDEV=${ROOTDEV:-/dev/mmcblk0p2} \
		NEO_BOOTLOADER=$WORK/u-boot.bin \
		NEO_MNT1=$WORK/mnt1 \
		NEO_MNT2=$WORK/mnt2 \
		sh "$SUT" "$@" 2>&1
}

# ------------------------------------------------------- the refusals

reset SD SD
rc=0
out=$(run -n) || rc=$?
check "no eMMC is a refusal" "$rc" "1"
contains "and says what it looked at" "$out" "no eMMC found under"

reset MMC MMC
rc=0
out=$(run -n) || rc=$?
check "two MMC devices is a refusal, not a choice" "$rc" "1"
contains "and names both" "$out" "more than one MMC device"

reset
printf '/dev/mmcblk1p1 /boot ext4 rw 0 0\n' >>"$WORK/mounts"
rc=0
out=$(run -n) || rc=$?
check "a mounted target is a refusal" "$rc" "1"
contains "and shows the mount it found" "$out" "/dev/mmcblk1p1 /boot"

# The refusal the specification does not have, on a board booted from the
# eMMC. The fixture describes a state that can actually exist: if root is on
# the eMMC then /proc/mounts says so too, and /boot is mounted from it as
# well. The earlier version of this test set NEO_ROOTDEV to the eMMC while
# leaving /proc/mounts pointing at the card, which is impossible, and it was
# the only way the guard was ever reached. On real hardware the mount check
# fired first and told the operator to unmount, which is wrong advice.
reset
printf '/dev/mmcblk1p2 / ext4 rw 0 0\n' >"$WORK/mounts"
printf '/dev/mmcblk1p1 /boot ext4 rw,noatime 0 0\n' >>"$WORK/mounts"
ROOTDEV=/dev/mmcblk1p2
rc=0
out=$(run -n) || rc=$?
ROOTDEV=
check "running root on the target is a refusal" "$rc" "1"
contains "and says to boot from the card first" "$out" "Boot from the microSD card first"
absent "and does not tell the operator to unmount anything" "$out" "Unmount it first"

reset
rm -f "$WORK/u-boot.bin"
rc=0
out=$(run) || rc=$?
check "a missing bootloader image is a refusal" "$rc" "1"
contains "and says where the boot ROM looks" "$out" "byte 8192"

# --------------------------------------------------------- the dry run

reset
out=$(run -n)
contains "the dry run names the target it discovered" "$out" "/dev/mmcblk1"
contains "and says nothing was written" "$out" "dry run, nothing written"
# grep -c prints 0 AND exits 1 when nothing matches, so "|| echo 0"
# would append a second line. wc has no such opinion.
check "and wrote nothing at all" "$(wc -l <"$CALLS" | tr -d " ")" "0"

# ------------------------------------------------------- the real path

reset
out=$(run)
calls=$(cat "$CALLS")

contains "the bootloader goes to byte 8192" "$calls" "seek=8"
contains "written with a 1024 byte block, so seek=8 is 8 KiB" "$calls" "bs=1024"
contains "and without truncating the rest of the device" "$calls" "conv=notrunc,fsync"

# The number that matters most in the whole project. 2048 sectors is 1 MiB,
# and anything below it puts a filesystem on top of U-Boot.
contains "the first partition starts at sector 2048" 	"$calls" "sfdisk-stdin: start=2048"
contains "the boot partition is bootable" "$calls" "bootable"
contains "and a second partition takes the rest" "$calls" "sfdisk-stdin: start=, type=83"
contains "both partitions are formatted" "$calls" "mkfs.ext4 -qF -L boot"
contains "and the root one too" "$calls" "mkfs.ext4 -qF -L root"
contains "the copy excludes other filesystems" "$calls" "--one-file-system"
contains "and fsck reports rather than repairs" "$calls" "fsck.ext4 -fn"

# ------------------------------------------------ what bootconfig wrote

conf=$WORK/mnt1/extlinux/extlinux.conf
contains "the placeholder is replaced with the real PARTUUID" \
	"$(cat "$conf")" "root=PARTUUID=aabbccdd-02"
absent "and the placeholder is gone" "$(cat "$conf")" "FILLED-BY-FLASH-EMMC"
contains "the rest of the append line is untouched" \
	"$(cat "$conf")" "console=ttyS0,115200"
contains "fstab root line carries the new root PARTUUID" \
	"$(cat "$WORK/mnt2/etc/fstab")" "PARTUUID=aabbccdd-02 / ext4"
contains "fstab boot line carries the new boot PARTUUID" \
	"$(cat "$WORK/mnt2/etc/fstab")" "PARTUUID=aabbccdd-01 /boot ext4"

# Idempotent: the second run patches a real value rather than the
# placeholder, which is a different sed match and the reason the pattern is
# written to accept both.
out=$(run)
contains "a second run still ends with the right PARTUUID" \
	"$(cat "$conf")" "root=PARTUUID=aabbccdd-02"
check "and only one root= remains" \
	"$(grep -c -o 'root=PARTUUID=' "$conf")" "1"

# ------------------------------------------------ the trap names a state

reset
FAIL_dd=1
export FAIL_dd
rc=0
out=$(run) || rc=$?
unset FAIL_dd
check "a failing state is a failure" "$rc" "1"
contains "and the trap names the state, not the line" "$out" "failed in state bootloader"

reset
FAIL_mkfs_ext4=1
export FAIL_mkfs_ext4
rc=0
out=$(run) || rc=$?
unset FAIL_mkfs_ext4
contains "a later state is named correctly too" "$out" "failed in state format"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
