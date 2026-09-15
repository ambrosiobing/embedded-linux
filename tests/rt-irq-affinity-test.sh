#!/bin/sh
#
# rt-irq-affinity-test.sh - interrupt affinity, without interrupts.
#
# The script reaches the kernel only through files under $RT_ROOT, which is
# what makes this file possible: a directory tree that looks like /proc/irq
# stands in for the real one, and the whole thing runs on a laptop.
#
# The case worth building a fake tree for is the one that is easy to get
# wrong. Per-CPU timers and IPIs list every CPU and refuse to be moved, so
# a naive check reports them as failures on every board, everybody learns
# to ignore the output, and the day a real device interrupt lands on the
# isolated core nobody notices. Here the two are distinguished by whether
# the write succeeds, and both halves of that are exercised.
#
# A read-only file stands in for an interrupt the kernel owns. That works
# because the tests run as an ordinary user; as root the permission bits
# mean nothing and the case would silently pass, so the test refuses to run
# as root rather than reporting a result it did not measure.
#
#   sh tests/rt-irq-affinity-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-rt/files/rt-irq-affinity

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

if [ "$(id -u)" -eq 0 ]; then
	echo "FAILED   this test must not run as root: it distinguishes a"
	echo "         movable interrupt from a kernel-owned one by file"
	echo "         permissions, and root ignores those."
	exit 1
fi

# ------------------------------------------------------------- the tree
#
#   irq 24  mmc1        movable, currently on all four CPUs
#   irq 27  eth0        movable, already confined to 0-2
#   irq 11  arch_timer  read-only, lists every CPU: a per-CPU interrupt
#   irq 33  (no subdir) movable, named through /proc/interrupts instead

build_tree() {
	rm -rf "$WORK/proc"
	mkdir -p "$WORK/proc/irq/24/mmc1" "$WORK/proc/irq/27/eth0" \
		"$WORK/proc/irq/11/arch_timer" "$WORK/proc/irq/33"
	echo "0-3" >"$WORK/proc/irq/24/smp_affinity_list"
	echo "0-2" >"$WORK/proc/irq/27/smp_affinity_list"
	echo "0-3" >"$WORK/proc/irq/11/smp_affinity_list"
	echo "0-3" >"$WORK/proc/irq/33/smp_affinity_list"
	chmod 0444 "$WORK/proc/irq/11/smp_affinity_list"

	# default_smp_affinity sits in /proc/irq next to the numbered
	# directories and is not an interrupt. Skipping it is not cosmetic:
	# it is a file, not a directory, and basename of it is not a number.
	echo "0-3" >"$WORK/proc/irq/default_smp_affinity"

	printf '%s\n' \
		"           CPU0       CPU1       CPU2       CPU3" \
		" 33:          4          0          0          0  bcm2835-spi" \
		>"$WORK/proc/interrupts"
}

cat >"$WORK/rt.conf" <<'CONF'
RT_CPU=3
RT_HOUSEKEEPING=0-2
CONF

export RT_ROOT=$WORK
export RT_CONF=$WORK/rt.conf

# ------------------------------------------------------------- set

build_tree
out=$(sh "$SUT" set 2>&1)
contains "set reports the three it could move" "$out" "moved 3 interrupts"
contains "set names the one it could not" "$out" "11(arch_timer)"
check "movable interrupt was confined" \
	"$(cat "$WORK/proc/irq/24/smp_affinity_list")" "0-2"
check "kernel-owned interrupt was left alone" \
	"$(cat "$WORK/proc/irq/11/smp_affinity_list")" "0-3"

# ------------------------------------------------------------- check

# After set, nothing movable reaches CPU 3, and the one that still lists it
# is reported as expected rather than as a failure.
rc=0
out=$(sh "$SUT" check 2>&1) || rc=$?
check "check passes once the movable ones are moved" "$rc" "0"
contains "check counts the kernel-owned one" "$out" "1 kernel-owned"

# One movable interrupt put back on all four cores is a real finding.
echo "0-3" >"$WORK/proc/irq/27/smp_affinity_list"
rc=0
out=$(sh "$SUT" check 2>&1) || rc=$?
check "check fails when a movable interrupt reaches the isolated core" \
	"$rc" "1"
contains "and names it" "$out" "irq 27 (eth0)"

# A range that contains the CPU has to be read as containing it. "2-3"
# would look like "not 3" to anything matching on commas alone.
build_tree
echo "2-3" >"$WORK/proc/irq/24/smp_affinity_list"
rc=0
out=$(sh "$SUT" check 2>&1) || rc=$?
check "a range is expanded, not string-matched" "$rc" "1"
contains "the range is reported verbatim" "$out" "irq 24 (mmc1) -> 2-3"

# ------------------------------------------------------------- show

build_tree
out=$(sh "$SUT" show 2>&1)
contains "show names an interrupt from its subdirectory" "$out" "mmc1"
contains "show falls back to /proc/interrupts" "$out" "bcm2835-spi"
contains "show lists the affinity" "$out" "0-2"

# An unknown subcommand is a usage error, not a silent success.
rc=0
sh "$SUT" frobnicate >/dev/null 2>&1 || rc=$?
check "an unknown subcommand exits 2" "$rc" "2"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
