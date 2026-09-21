#!/bin/sh
#
# hmi-metrics-test.sh - the dashboard's numbers, without a dashboard.
#
# Project 13 has almost nothing that runs on a laptop: the widgets need a
# compositor and the compositor needs a GPU. metrics.c is the exception,
# and it is the exception on purpose. Every function in it is a pure read
# of a file, and every path goes through a prefix that
# BENCH_METRICS_ROOT redirects, so a directory of fake files stands in
# for /proc, /sys and /run.
#
# THE CASE THIS SUITE EXISTS FOR is the memory bar. The obvious
# implementation reads MemFree, and on a healthy Linux system MemFree is
# small because the page cache is doing its job. A bar driven by MemFree
# sits near 100 percent on a completely idle board, which is the
# commonest way to ship a memory widget that is always alarming and never
# informative. The fake /proc/meminfo here has a deliberately tiny
# MemFree and a large MemAvailable, so an implementation that used the
# wrong field would read about 95 percent where the right one reads 25.
#
# The second case is failure reporting. Every reader returns -1 for a
# file it could not read, because three of the four have a plausible
# zero: load 0.00 is an idle board. A dashboard that printed 0.00 for a
# missing /proc/loadavg would not be degraded, it would be lying.
#
#   sh tests/hmi-metrics-test.sh
#
# NEEDS A C COMPILER. This suite compiles metrics.c against a small
# harness. The authoring laptop has no compiler, so it reports that and
# exits 0 rather than reporting a pass it did not earn; CI has one and
# runs it for real.
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/meta-bench/recipes-bench/bench-hmi/files
HARNESS=$ROOT/tests/hmi-metrics-harness.c

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

# ------------------------------------------------------- is there a compiler
CC=${CC:-}
if [ -z "$CC" ]; then
	for candidate in cc gcc clang; do
		if command -v "$candidate" >/dev/null 2>&1; then
			CC=$candidate
			break
		fi
	done
fi

if [ -z "$CC" ]; then
	echo "unasked  no C compiler on PATH (tried cc, gcc, clang)."
	echo "         metrics.c was NOT compiled and NOT exercised here."
	echo "         This is expected on the authoring laptop, which has"
	echo "         no compiler; CI runs this suite for real. Nothing"
	echo "         below this line ran, so treat this as 'not checked'"
	echo "         rather than as a pass."
	exit 0
fi

for f in "$SRC/metrics.c" "$SRC/metrics.h" "$HARNESS"; do
	if [ ! -f "$f" ]; then
		echo "FAILED   input missing: $f"
		exit 1
	fi
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

BIN=$WORK/harness
if ! "$CC" -std=c99 -Wall -Wextra -Werror \
	-I"$SRC" -o "$BIN" "$HARNESS" "$SRC/metrics.c" 2>"$WORK/cc.log"; then
	echo "FAILED   metrics.c did not compile with $CC"
	sed 's/^/           /' "$WORK/cc.log"
	exit 1
fi
echo "ok       metrics.c compiles clean with -Wall -Wextra -Werror"
pass=$((pass + 1))

# ------------------------------------------------------------- a fake board
# Written with printf rather than a heredoc: this repository has lost
# four edits to heredocs eating backslashes, and printf is explicit.
make_tree() {
	tree=$1
	state_word=$2

	rm -rf "$tree"
	mkdir -p "$tree/proc" "$tree/sys/class/thermal/thermal_zone0" \
		"$tree/run/bench"

	printf '0.42 0.31 0.18 1/123 4567\n' >"$tree/proc/loadavg"
	printf '48312\n' >"$tree/sys/class/thermal/thermal_zone0/temp"

	# MemFree is deliberately tiny and MemAvailable large: the page
	# cache is doing its job. Used = (Total - Available) / Total,
	# which is 25 percent here. An implementation reading MemFree
	# would report about 95 percent.
	{
		printf 'MemTotal:        4000000 kB\n'
		printf 'MemFree:          200000 kB\n'
		printf 'MemAvailable:    3000000 kB\n'
		printf 'Buffers:          100000 kB\n'
	} >"$tree/proc/meminfo"

	if [ -n "$state_word" ]; then
		printf '%s\n' "$state_word" >"$tree/run/bench/state"
	fi
}

run_harness() {
	BENCH_METRICS_ROOT="$1" "$BIN"
}

field() {
	printf '%s\n' "$2" | sed -n "s/^$1=//p"
}

# ------------------------------------------------------------- a healthy board
TREE=$WORK/ok
make_tree "$TREE" ok
out=$(run_harness "$TREE")

check "the load is the first field of /proc/loadavg" \
	"$(field load "$out")" "0.420"
check "millidegrees become degrees" \
	"$(field temp "$out")" "48.312"
check "memory used is computed from MemAvailable, not MemFree" \
	"$(field mem "$out")" "25.000"
check "the state word is read" "$(field word "$out")" "ok"
check "and classified" "$(field state "$out")" "OK"

# ---------------------------------------------- the three words bench-state writes
for word in starting failed; do
	TREE=$WORK/$word
	make_tree "$TREE" "$word"
	out=$(run_harness "$TREE")
	# Character classes, not ranges: shellcheck rejects a-z/A-Z
	# (SC2018, SC2019) because the mapping depends on the locale.
	upper=$(printf '%s' "$word" | tr '[:lower:]' '[:upper:]')
	check "'$word' is classified as $upper" "$(field state "$out")" "$upper"
	check "and '$word' is shown verbatim" "$(field word "$out")" "$word"
done

# A fourth word is unknown, not failed. bench-state may grow one, and a
# dashboard that painted every unrecognised word red would cry wolf.
TREE=$WORK/fourth
make_tree "$TREE" maintenance
out=$(run_harness "$TREE")
check "an unrecognised word is UNKNOWN, not FAILED" \
	"$(field state "$out")" "UNKNOWN"
check "but the word itself is still displayed" \
	"$(field word "$out")" "maintenance"

# ------------------------------------------------------------- missing files
TREE=$WORK/nostate
make_tree "$TREE" ""
out=$(run_harness "$TREE")
check "a missing state file reads as UNKNOWN" \
	"$(field state "$out")" "UNKNOWN"
check "and the word is the literal 'unknown'" \
	"$(field word "$out")" "unknown"

TREE=$WORK/empty
rm -rf "$TREE"
mkdir -p "$TREE"
out=$(run_harness "$TREE")
check "a missing loadavg is -1, not 0" "$(field load "$out")" "-1.000"
check "a missing thermal zone is -1, not 0" "$(field temp "$out")" "-1.000"
check "a missing meminfo is -1, not 0" "$(field mem "$out")" "-1.000"
check "a missing state file is still UNKNOWN" \
	"$(field state "$out")" "UNKNOWN"

# An empty state file is not the same as a missing one, and both are
# unknown rather than either being mistaken for a word.
TREE=$WORK/emptyword
make_tree "$TREE" ""
: >"$TREE/run/bench/state"
out=$(run_harness "$TREE")
check "an empty state file reads as UNKNOWN" \
	"$(field state "$out")" "UNKNOWN"

# ------------------------------------------------- meminfo without MemAvailable
# Pre-3.14 kernels have no MemAvailable. Reporting -1 is right: the
# alternative is silently substituting MemFree, which is the exact bug
# this module was written to avoid.
TREE=$WORK/noavail
make_tree "$TREE" ok
printf 'MemTotal:        4000000 kB\n' >"$TREE/proc/meminfo"
printf 'MemFree:          200000 kB\n' >>"$TREE/proc/meminfo"
out=$(run_harness "$TREE")
check "meminfo without MemAvailable reports -1, not a MemFree guess" \
	"$(field mem "$out")" "-1.000"

# ------------------------------------------------------- the root is announced
TREE=$WORK/ok
out=$(run_harness "$TREE")
check "the metrics root is reported so a test tree is never mistaken for a board" \
	"$(field root "$out")" "$TREE"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
