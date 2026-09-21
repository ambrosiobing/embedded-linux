#!/bin/sh
#
# ab-bootscript-test.sh - run the real A/B boot script under real U-Boot.
#
# THE PROBLEM THIS SOLVES. boot.cmd.in is the most dangerous file in
# Project 19: it is on the shared FAT partition, it is in no bundle, and a
# broken copy takes out both slots at once, because the thing that would
# roll back is the thing that broke. It runs inside U-Boot, where none of
# this repository's test machinery reaches, and the only other way to try a
# change is to put it on the one card the board boots from.
#
# THE TRAP THIS AVOIDS, which is decision 98's shape. The tempting test is
# to reimplement the counter logic in shell and assert on that. It would
# pass while saying nothing about the file that actually runs. So this
# executes the real script text, in a real U-Boot, with its real hush
# parser, its real setexpr arithmetic and its real environment.
#
# WHAT IS SUBSTITUTED, AND IT IS NAMED RATHER THAN HIDDEN. Two things.
#
#   1. The @@TOKENS@@, exactly as rpi-u-boot-scr.bb substitutes them, so
#      the text under test is the text that reaches the board.
#   2. The two terminal actions, ext4load and the boot command, which need
#      an arm64 target and a real card. They become echo lines, so the
#      script's decision is observable and its last step is not taken.
#
# Everything that decides anything is untouched: the defaults, the loop
# over BOOT_ORDER, the comparisons, the setexpr decrements, the saveenv
# ordering and the exhausted-both-slots branch. The substitution is
# asserted below, so a future edit cannot silently widen it.
#
# WHAT THIS CANNOT TELL YOU. It does not prove the script boots a board. It
# does not exercise the FAT environment, the real partition numbers, or the
# handover to the kernel. Those need the second microSD card and the
# console, and that is what docs/BRINGUP.md is for.
#
#   sh tests/ab-bootscript-test.sh
#
# It needs a U-Boot sandbox binary, which is a host build and needs no
# board. Point BENCH_UBOOT_SANDBOX at it, or put a sandbox u-boot on PATH:
#
#   git clone --depth 1 https://source.denx.de/u-boot/u-boot.git
#   cd u-boot && make sandbox_defconfig && make -j"$(nproc)"
#   export BENCH_UBOOT_SANDBOX=$PWD/u-boot
#
# Without it this exits 0 and prints, loudly, the list of questions it was
# unable to ask. That is deliberate: a skip that looks like a pass is the
# failure this repository has shipped three times, so the skip says what
# went unchecked rather than staying quiet.
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BOOTCMD=$ROOT/meta-bench/recipes-bsp/rpi-u-boot-scr/files/boot.cmd.in

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
		fail=$((fail + 1))
		;;
	esac
}

[ -r "$BOOTCMD" ] || {
	echo "FAILED   no boot script at $BOOTCMD"
	echo
	echo "0 passed, 1 failed"
	exit 1
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The same three substitutions rpi-u-boot-scr.bb makes, with the values
# this project's machine produces: arm64, so the kernel is Image and the
# boot command is booti, from an SD card, so the media is mmc.
sed -e 's/@@KERNEL_IMAGETYPE@@/Image/' \
	-e 's/@@KERNEL_BOOTCMD@@/booti/' \
	-e 's/@@BOOT_MEDIA@@/mmc/' \
	"$BOOTCMD" >"$WORK/boot.cmd"

check "no unsubstituted tokens remain" \
	"$(grep -c '@@' "$WORK/boot.cmd" || true)" "0"

# The two hardware actions become observable no-ops. The names are printed
# so that a reader of this output knows exactly what was not executed.
sed -e 's/^\( *\)if ext4load .*/\1if echo "STUB-LOAD mmc 0:${rauc_part} \/boot\/Image"; then/' \
	-e 's/^\( *\)booti .*/\1echo "STUB-BOOT slot ${rauc_slot} part ${rauc_part}"/' \
	"$WORK/boot.cmd" >"$WORK/boot.sandbox.cmd"

# The substitution is asserted rather than trusted. If a future edit
# renames or moves either command, this fails instead of quietly testing a
# script with a real ext4load in it that can never succeed.
check "the kernel load was stubbed" \
	"$(grep -c 'STUB-LOAD' "$WORK/boot.sandbox.cmd")" "1"
check "the boot command was stubbed" \
	"$(grep -c 'STUB-BOOT' "$WORK/boot.sandbox.cmd")" "1"
# Anchored to command position, which took two attempts and both failures
# were the same family.
#
# The first version counted the words anywhere in the file, and boot.cmd.in
# explains at length why the kernel is loaded from the slot rather than
# from the FAT partition, so it counted its own comments.
#
# Stripping comments was not enough. The word "booti" is a substring of
# "rebooting", and the script says "Rebooting to try the other" in an echo
# on the failure path. A bare substring search reported two live commands
# where there were none.
#
# So the pattern asks the real question: is either name at the start of a
# line, in the position a command occupies, optionally after "if".
check "and no executable ext4load or booti survived" \
	"$(grep -v '^[[:space:]]*#' "$WORK/boot.sandbox.cmd" |
		grep -cE '^[[:space:]]*(if[[:space:]]+)?(ext4load|booti)[[:space:]]' ||
		true)" "0"

# TWO QUESTIONS, NOT ONE, AND THE FIRST VERSION ASKED ONLY THE SECOND.
#
# It compared the stubbed file against the pre-stub file, which catches a
# substitution that widened until it was testing a different script. It
# cannot catch anything missing from the source, because both sides are
# derived from the source and a deletion removes it from both. Deleting
# saveenv from boot.cmd.in left this suite green, which was found by
# deleting it and watching nothing happen.
#
# So each keyword is now asked about twice: does the script contain it at
# all, and did the substitution leave it alone.
for keyword in "setexpr BOOT_A_LEFT" "setexpr BOOT_B_LEFT" "^saveenv" \
	"BOOT_ORDER" "setenv rauc_part 2" "setenv rauc_part 3" "^reset"; do
	before=$(grep -c "$keyword" "$WORK/boot.cmd" | head -n 1)
	after=$(grep -c "$keyword" "$WORK/boot.sandbox.cmd" | head -n 1)
	check "the script contains $keyword at all" \
		"$(test "$before" -ge 1 && echo yes || echo no)" "yes"
	check "and the substitution left $keyword alone" "$after" "$before"
done

# ------------------------------------------- find a U-Boot to run it in

UBOOT=${BENCH_UBOOT_SANDBOX:-}
if [ -z "$UBOOT" ]; then
	UBOOT=$(command -v u-boot 2>/dev/null || true)
fi

if [ -z "$UBOOT" ] || [ ! -x "$UBOOT" ]; then
	echo
	echo "SKIPPED  no U-Boot sandbox binary, so the script was NOT executed."
	echo
	if [ "$fail" -eq 0 ]; then
		echo "         The static checks above passed."
	else
		echo "         $fail of the static checks above FAILED, and those are"
		echo "         about this test's own substitution rather than about"
		echo "         the boot script's behaviour. Fix them first."
	fi
	echo
	echo "         The questions below were not asked at all, and nothing"
	echo "         else in this repository asks them:"
	echo
	echo "           - does a fresh environment choose slot A and leave 2 attempts"
	echo "           - does an exhausted slot A fall through to slot B"
	echo "           - do two exhausted slots reset both counters and reboot"
	echo "           - does BOOT_ORDER actually decide the order"
	echo "           - does hush parse this file at all"
	echo
	echo "         Build one, which needs no board:"
	echo "           make sandbox_defconfig && make"
	echo "           export BENCH_UBOOT_SANDBOX=/path/to/u-boot"
	echo
	echo "$pass passed, $fail failed, execution skipped"
	[ "$fail" -eq 0 ]
	exit
fi

echo
echo "--- running the script in $UBOOT"

# Each scenario sets an environment, runs the whole script, and is read
# from what U-Boot printed. The script announces its decision on the
# console, which is the same line a person reads during bring-up, so the
# assertions here and the bring-up document check the same thing.
run_scenario() {
	# $1 is a semicolon-separated setenv prologue
	{
		printf '%s\n' "$1"
		cat "$WORK/boot.sandbox.cmd"
	} >"$WORK/run.cmd"
	"$UBOOT" -c "$(cat "$WORK/run.cmd")" 2>&1 || true
}

# A fresh card: no BOOT_ORDER, no counters. The script invents them.
out=$(run_scenario 'setenv BOOT_ORDER; setenv BOOT_A_LEFT; setenv BOOT_B_LEFT')
contains "a fresh environment chooses slot A" "$out" "Slot A chosen"
contains "and leaves two attempts after this one" "$out" "2 attempts left"
contains "and loads from partition 2" "$out" "STUB-LOAD mmc 0:2"

# Slot A has failed three times already.
out=$(run_scenario 'setenv BOOT_ORDER "A B"; setenv BOOT_A_LEFT 0; setenv BOOT_B_LEFT 3')
contains "an exhausted slot A is reported" "$out" "Slot A has no attempts left"
contains "and slot B is chosen instead" "$out" "Slot B chosen"
contains "and the load comes from partition 3" "$out" "STUB-LOAD mmc 0:3"

# Both slots exhausted: the board must not sit at a prompt.
out=$(run_scenario 'setenv BOOT_ORDER "A B"; setenv BOOT_A_LEFT 0; setenv BOOT_B_LEFT 0')
contains "two exhausted slots are reported" "$out" "No slot has attempts left"
contains "and the operator is pointed at the second card" "$out" "second microSD card"
check "and no kernel is loaded" \
	"$(printf '%s' "$out" | grep -c 'STUB-LOAD' || true)" "0"

# BOOT_ORDER decides, not the slot letters' alphabetical order. This is
# what RAUC rewrites when it installs, so if it were ignored an update
# would install correctly and never be booted.
out=$(run_scenario 'setenv BOOT_ORDER "B A"; setenv BOOT_A_LEFT 3; setenv BOOT_B_LEFT 3')
contains "BOOT_ORDER puts slot B first when it says so" "$out" "Slot B chosen"
check "and slot A is not also chosen" \
	"$(printf '%s' "$out" | grep -c 'Slot A chosen' || true)" "0"

# The counter must fall before the kernel is loaded, and the only way to
# see that from outside is that a slot chosen twice in a row reports one
# fewer attempt the second time. This is the ordering the whole design
# rests on.
out=$(run_scenario 'setenv BOOT_ORDER "A B"; setenv BOOT_A_LEFT 1; setenv BOOT_B_LEFT 3')
contains "a slot on its last attempt still boots" "$out" "Slot A chosen"
contains "and reports none left afterwards" "$out" "0 attempts left"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
