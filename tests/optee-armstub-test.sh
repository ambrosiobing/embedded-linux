#!/bin/sh
#
# optee-armstub-test.sh - what the installer says about a card, against
# whether that card can actually boot.
#
# This file exists because of one evening. On Thursday 1 October 2026
# "./go armstub status" reported armstub8.bin present at the right size,
# uboot.env present, config.txt booting the secure world and kernel8.img
# present. Every one of those was true. The board then stopped at the
# U-Boot prompt, because nothing in that environment patches the device
# tree the firmware hands over: it has no /psci node, so three of four
# cores time out, and no /firmware/optee node, so the driver this whole
# project exists for never probes. The status output was right about
# everything it looked at and silent about the one thing that decides
# whether the card boots unaided.
#
# So the new question is asserted in both directions, which is the only
# way to tell a working check from one that always passes: an environment
# that cannot boot alone has to be reported as such, and one that can has
# to not be. There is a third case between them, and it is the one worth
# the most here: an environment that creates a /psci node but never
# points the cpu nodes at it is still unbootable, so a reader matching
# the bare word "psci" would pass it. That case is asserted too.
#
# It needs no hardware, no Yocto, no network and no build. The fixtures
# are directories standing in for a mounted FAT partition, which is all
# the script ever sees of a card.
#
# What this does NOT check: the CRC32 at the front of a real uboot.env.
# Nothing in this repository validates it, the reader in the script
# deliberately steps over it, and a fixture with a wrong one is therefore
# indistinguishable from a good one here. Only U-Boot can reject it, and
# only on a board.
#
#   sh tests/optee-armstub-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT=$ROOT/scripts/optee-armstub.sh

pass=0
fail=0

contains() {
	case $2 in
	*"$3"*)
		echo "ok       $1"
		pass=$((pass + 1))
		;;
	*)
		echo "FAILED   $1: '$3' not found in the output"
		fail=$((fail + 1))
		;;
	esac
}

lacks() {
	case $2 in
	*"$3"*)
		echo "FAILED   $1: '$3' was in the output and should not be"
		fail=$((fail + 1))
		;;
	*)
		echo "ok       $1"
		pass=$((pass + 1))
		;;
	esac
}

exists() {
	if [ -e "$2" ]; then
		echo "ok       $1"
		pass=$((pass + 1))
	else
		echo "FAILED   $1: $2 does not exist"
		fail=$((fail + 1))
	fi
}

absent() {
	if [ -e "$2" ]; then
		echo "FAILED   $1: $2 exists and should not"
		fail=$((fail + 1))
	else
		echo "ok       $1"
		pass=$((pass + 1))
	fi
}

# An assertion about a missing script is an assertion about nothing, and
# an empty output compared against an empty output passes.
if [ ! -r "$SCRIPT" ]; then
	echo "FAILED   missing input: $SCRIPT"
	echo
	echo "0 passed, 1 failed"
	exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

# A uboot.env shaped the way mkenvimage writes one: four bytes standing
# in for the CRC32 that nothing here reads, then NUL-separated key=value
# pairs.
mkenv() {
	out=$1
	shift
	printf 'crc!' >"$out"
	for kv in "$@"; do
		printf '%s\000' "$kv" >>"$out"
	done
}

# Single quotes throughout: these strings carry literal ${...} the way a
# real U-Boot environment does, and the shell must not expand them. The
# fixture IS the text, so expanding it here would write an environment
# with empty addresses and then assert nothing about it. shellcheck cannot
# tell a fixture from an expression, and SC2016 is an info-level finding
# that still turns a run red, so the intent is stated here rather than
# left to be re-discovered in CI.
# shellcheck disable=SC2016
ENV_KERNEL='load_kernel=fatload mmc 0:1 ${kernel_addr_r} kernel8.img'
# shellcheck disable=SC2016
ENV_BOOTIT='boot_it=booti ${kernel_addr_r} - ${fdt_addr_r}'
ENV_MMCBOOT='mmcboot=run load_kernel; run set_bootargs_tty; run boot_it'
ENV_PSCINODE='fixup=fdt addr 0x4000000; fdt mknode / psci'
ENV_ENABLE='fixup=fdt set /cpus/cpu@0 enable-method psci'

newcard() {
	card=$1
	rm -rf "$card"
	mkdir -p "$card"
	{
		echo "# Fixture boot partition"
		echo "enable_uart=1"
		echo "dtparam=audio=on"
	} >"$card/config.txt"
	# Any size will do; status reports the byte count of the stub, not
	# of this, but the script refuses a card without a kernel.
	printf 'kernel8 fixture' >"$card/kernel8.img"
}

newsrc() {
	src=$1
	rm -rf "$src"
	mkdir -p "$src"
	printf 'armstub fixture bytes' >"$src/armstub8.bin"
}

# ------------------------------------------------ install onto a card

BOOT=$WORK/boot
SRC=$WORK/src
newcard "$BOOT"
newsrc "$SRC"
mkenv "$SRC/uboot.env" "$ENV_KERNEL" "$ENV_BOOTIT" "$ENV_MMCBOOT"

if out=$(sh "$SCRIPT" install "$BOOT" "$SRC" 2>&1); then
	echo "ok       install exits zero"
	pass=$((pass + 1))
else
	echo "FAILED   install exits zero: it did not"
	fail=$((fail + 1))
	out=""
fi

contains "install keeps the original config.txt" "$out" "config.txt.bench-orig"
contains "install copies uboot.env" "$out" "uboot.env installed"
contains "install rewrites config.txt" "$out" "boots the secure world first"
exists "the stub is on the card" "$BOOT/armstub8.bin"
exists "the original config.txt is kept" "$BOOT/config.txt.bench-orig"
exists "the environment is on the card" "$BOOT/uboot.env"

# ------------------- status on the environment that was really there

if out=$(sh "$SCRIPT" status "$BOOT" 2>&1); then
	echo "ok       status exits zero"
	pass=$((pass + 1))
else
	echo "FAILED   status exits zero: it did not"
	fail=$((fail + 1))
	out=""
fi

contains "status reports the stub and its size" "$out" "armstub8.bin present,"
contains "status reports the environment and its size" "$out" "uboot.env present,"
contains "status reports the config.txt block" "$out" "boots the secure world"
contains "status reports the kernel" "$out" "kernel8.img present"

# The whole point. This environment loads a kernel and patches nothing.
contains "an unpatched environment cannot boot alone" "$out" "cannot boot alone"
contains "the refusal names the missing psci node" "$out" "/psci"
contains "the refusal names the missing optee node" "$out" "/firmware/optee"
contains "the refusal names where the hand sequence is" "$out" "docs/BRINGUP.md"
lacks "and it does not claim an unaided boot" "$out" "boots without anyone"

# ------- a /psci node with no enable-method is still not bootable

mkenv "$BOOT/uboot.env" "$ENV_KERNEL" "$ENV_PSCINODE" "$ENV_BOOTIT"
out=$(sh "$SCRIPT" status "$BOOT" 2>&1)
contains "a psci node alone is not enough" "$out" "cannot boot alone"
lacks "and the bare word psci does not satisfy the check" \
	"$out" "boots without anyone"

# ------------------------- an environment that does patch the tree

mkenv "$BOOT/uboot.env" "$ENV_KERNEL" "$ENV_ENABLE" "$ENV_BOOTIT"
out=$(sh "$SCRIPT" status "$BOOT" 2>&1)
contains "a patched environment boots unaided" "$out" "boots without anyone"
lacks "and it is not reported as unbootable" "$out" "cannot boot alone"

# ------------------------------------- a card with no environment

rm -f "$BOOT/uboot.env"
out=$(sh "$SCRIPT" status "$BOOT" 2>&1)
contains "a missing environment is still reported" "$out" "uboot.env absent"
lacks "and nothing is claimed about what it patches" "$out" "cannot boot alone"

# ------------------------------------------------- remove restores

if out=$(sh "$SCRIPT" remove "$BOOT" 2>&1); then
	echo "ok       remove exits zero"
	pass=$((pass + 1))
else
	echo "FAILED   remove exits zero: it did not"
	fail=$((fail + 1))
	out=""
fi

contains "remove restores the kept config.txt" "$out" "config.txt restored"
contains "remove moves the stub aside" "$out" "armstub8.bin.off"
contains "remove leaves a card that still boots" "$out" "arm_64bit=1"
exists "the stub is kept under the inert name" "$BOOT/armstub8.bin.off"
absent "and is no longer under the name the firmware loads" "$BOOT/armstub8.bin"
contains "arm_64bit=1 is in the restored config.txt" \
	"$(cat "$BOOT/config.txt")" "arm_64bit=1"

out=$(sh "$SCRIPT" status "$BOOT" 2>&1)
contains "status explains a card that had the secure world removed" \
	"$out" "this card had the secure world and it was removed"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
