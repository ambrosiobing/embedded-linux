#!/bin/sh
#
# neo-air-extra-fragment-test.sh - the second fragment both of Project 2's
# build scripts accept, so another project can vary this configuration
# without editing them.
#
# Project 3 measures what each change to the boot costs in time and
# energy, and every one of its variants is one such fragment: kernel
# trimming, three compression choices, and a U-Boot fragment holding the
# preboot marker and the probes it turns off. Before NEO_EXTRA_FRAGMENT
# existed, both scripts took exactly one hardcoded path and died without
# it, so that whole plan had no way in and nothing said so.
#
# None of this needs a toolchain. The configuration guards run before the
# environment probing, on purpose and in that order, so the refusal is
# reachable on a laptop with no cross compiler. What is NOT reachable here
# is a real merge, and the assertions below say so rather than implying
# otherwise.
#
#   sh tests/neo-air-extra-fragment-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL=$ROOT/projects/02-neo-air-mainline/kernel/build.sh
UBOOT=$ROOT/projects/02-neo-air-mainline/uboot/build.sh

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

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

lacks() {
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

# NEO_SRC points outside the checkout, which is what the script requires,
# and nothing is ever written there: every run below stops at a guard.
#
# CROSS_COMPILE is set to a prefix that does not exist, because these
# scripts run under "set -u" and toolchain.env is what normally provides
# it. Unset, the run dies on an unbound variable before reaching the guard
# this test wants to observe, which is a different failure wearing the
# same exit code.
run() {
	_script=$1
	_extra=${2-}
	NEO_ENV=1 NEO_SRC=$WORK/src CROSS_COMPILE=bench-no-such-cross- \
		NEO_EXTRA_FRAGMENT="$_extra" sh "$_script" 2>&1
}

# ------------------------------------------- a path that cannot be read

# Set and unreadable is a mistake, not an absence. A variant whose
# fragment was silently skipped would be BUILT as the baseline and then
# recorded as a change, and the two rows would differ by nothing with
# nothing to say why. That is the failure this refusal exists for.
for name in kernel uboot; do
	case $name in
	kernel) script=$KERNEL ;;
	uboot) script=$UBOOT ;;
	esac

	rc=0
	out=$(run "$script" "$WORK/no-such-fragment.cfg") || rc=$?
	check "$name: an unreadable extra fragment is refused" "$rc" "1"
	contains "$name: and the refusal names the variable" "$out" \
		"NEO_EXTRA_FRAGMENT"
	contains "$name: and the path it could not read" "$out" \
		"no-such-fragment.cfg"
	contains "$name: and says how to build the baseline instead" "$out" \
		"Unset it"
done

# ------------------------------------ unset is the baseline, and is quiet

# The mechanism must be invisible when it is not used. If an unset
# variable produced the extra-fragment refusal, every existing build on
# this project would have stopped at a guard that has nothing to do with
# it.
for name in kernel uboot; do
	case $name in
	kernel) script=$KERNEL ;;
	uboot) script=$UBOOT ;;
	esac

	rc=0
	out=$(run "$script") || rc=$?
	lacks "$name: an unset extra fragment says nothing about itself" \
		"$out" "NEO_EXTRA_FRAGMENT"
	# It still stops, further down, for want of a cross compiler. That is
	# the next guard and not this one, and asserting on it here is what
	# distinguishes "got past the fragment check" from "never reached it".
	contains "$name: and the run reaches the toolchain guard instead" \
		"$out" "gcc"
done

# ------------------------------------- an empty file is a readable file

# Zero options is a legitimate variant: the baseline measured again under
# the same machinery, which is how a repeat is taken. An empty fragment
# must therefore be accepted rather than treated as absent.
: >"$WORK/empty.cfg"
for name in kernel uboot; do
	case $name in
	kernel) script=$KERNEL ;;
	uboot) script=$UBOOT ;;
	esac

	rc=0
	out=$(run "$script" "$WORK/empty.cfg") || rc=$?
	lacks "$name: an empty but readable fragment is not refused" \
		"$out" "NEO_EXTRA_FRAGMENT"
done

# ------------------------------------------ what this test cannot reach

# Stated rather than left for someone to discover: no merge happens here,
# so nothing below asserts that an option in the extra fragment arrives in
# .config. That needs a kernel tree and a cross compiler, which means the
# wsl laptop. The scripts check it themselves, on both fragments, and the
# check is the one that catches a dropped option.
#
# It cannot see an option a fragment turns OFF. A "# CONFIG_X is not set"
# line is skipped as a comment by that loop, so it is merged and never
# verified, and Project 3's U-Boot variant is almost entirely such lines.
echo "note     no merge is exercised here; that needs a tree and a cross"
echo "note     compiler, and the scripts verify both fragments themselves"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
