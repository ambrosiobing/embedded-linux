#!/bin/sh
#
# rt-matrix-test.sh - the paired-matrix figure, and the defect it had.
#
# The fixture is cut from the real results.csv rather than invented, the
# same rule rt-plot-test.sh follows: a fixture written from memory records
# an assumption about a format, and the assumption is the thing most likely
# to be wrong. The header here is the full 28 columns the board writes.
#
#   sh tests/rt-matrix-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/scripts/rt-matrix.py
PYTHON=${PYTHON:-python3}

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

# ------------------------------------------------------------- fixtures

HEADER='timestamp,label,image_build,kernel,kernel_version,realtime,isolated,affinity,governor,load,duration_s,toggle_us,ext_edges,ext_mean_us,ext_sd_us,ext_p999_us,ext_max_us,ext_ppm,ext_subsample,int_min_us,int_mean_us,int_max_us,int_p999_us,cyc_min_us,cyc_avg_us,cyc_max_us,throttled_before,throttled_after'

# Four rows: one configuration where the two kernels agree almost exactly,
# and one isolated configuration with a repeat on each arm. Between them
# they exercise the coincident case and the repeat case, which are the two
# the drawing has to get right.
row() {
	printf '2026-09-17T12:00:00Z,%s,20180309123456,6.12.93-v8,#1 SMP,%s,%s,no,performance,%s,60,1000,29995,1999.7,11.9,%s,809.7,-145.2,0.149,6.2,13.1,91.8,41,4,10,59,0x0,0x0\n' \
		"$1" "$2" "$3" "$4" "$5"
}

{
	echo "$HEADER"
	row generic-performance-load no no yes 100.419
	row rt-performance-load yes no yes 100.419
	row generic-iso-load no yes yes 119.158
	row generic-iso-load no yes yes 149.444
	row rt-iso-load yes yes yes 68.051
	row rt-iso-load yes yes yes 70.491
} >"$WORK/results.csv"

# --------------------------------------------------------------- cases

out=$("$PYTHON" "$SUT" -o "$WORK/a.svg" "$WORK/results.csv" 2>&1)
contains "the pairing counts configurations, not rows" "$out" "2 configurations"
contains "and reports every run" "$out" "6 runs"

svg=$(cat "$WORK/a.svg")
contains "the isolated band is captioned" "$svg" "CPU 3 isolated"
contains "the other band is captioned" "$svg" "general pool"
contains "both arms are named, so colour is never alone" "$svg" ">generic<"
contains "the real-time arm is named" "$svg" ">PREEMPT_RT<"
contains "a configuration is described by its knobs" "$svg" "iso, performance, load"

# Every run is a mark. Six runs, six circles: a figure that averaged the
# repeats away would draw four and look tidier for having lost the spread
# the project's main caution rests on.
check "every run is drawn, and no repeat is averaged away" \
	"$(grep -c '<circle ' "$WORK/a.svg")" "6"

# --------------------------------------- the defect the first render had
#
# Drawn on one centre line, two runs with the same value land on the same
# coordinate and the second covers the first. The rows where that happens
# are the rows where the two kernels agree, which is the finding, so the
# figure hid its own argument. Every assertion above passes on that layout,
# because each asks whether a mark is present and it was. This one asks a
# geometric question instead.
#
# The fixture's first configuration has both kernels at exactly 100.419.
# The two marks must share an x and differ in y.

coords=$(sed -n 's/.*<circle cx="\([0-9.]*\)" cy="\([0-9.]*\)".*/\1 \2/p' \
	"$WORK/a.svg")
verdict=$(printf '%s\n' "$coords" | awk '
	{ seen[$1] = seen[$1] " " $2; n[$1]++ }
	END {
		for (x in n) {
			if (n[x] == 2) {
				split(seen[x], ys, " ")
				print (ys[1] != ys[2]) ? "separated" : "overlapping"
				exit
			}
		}
		print "no coincident pair in the fixture"
	}')
check "two runs at the same value are both visible" "$verdict" "separated"

# ---------------------------------------------------------- refusals

rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" "$WORK/missing.csv" 2>&1) || rc=$?
check "a missing file is an error" "$rc" "1"

{
	echo "$HEADER"
	row generic-only no no yes 100.419
} >"$WORK/unpaired.csv"
rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" "$WORK/unpaired.csv" 2>&1) || rc=$?
check "a configuration with one arm is refused" "$rc" "1"
contains "and names the missing kernel" "$out" "no PREEMPT_RT run"
contains "and names the configuration" "$out" "performance, load"

rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" -m nosuchcolumn "$WORK/results.csv" \
	2>&1) || rc=$?
check "an unknown metric is an error" "$rc" "1"
contains "and lists what the header does have" "$out" "ext_p999_us"

# A column read by position rather than by name is the defect that already
# happened once here: a shipped results.csv was one column short of what
# the board writes, which shifts every column after the second. A header
# missing a required column must be a sentence, not a wrong figure.
{
	echo "timestamp,label,realtime,isolated,affinity,governor"
	echo "2026-09-17T12:00:00Z,x,no,no,no,performance"
} >"$WORK/short.csv"
rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" "$WORK/short.csv" 2>&1) || rc=$?
check "a header missing a column is an error" "$rc" "1"
contains "and names the column it wanted" "$out" "load"

{
	echo "$HEADER"
	row bad no no yes notanumber
	row bad-rt yes no yes 1.0
} >"$WORK/bad.csv"
rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" "$WORK/bad.csv" 2>&1) || rc=$?
check "an unparseable metric is an error, not a skip" "$rc" "1"
contains "and names the line number" "$out" "bad.csv:2"

{
	echo "$HEADER"
	row maybe perhaps no yes 1.0
	row maybe-rt yes no yes 1.0
} >"$WORK/yesno.csv"
rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" "$WORK/yesno.csv" 2>&1) || rc=$?
check "a flag that is neither yes nor no is an error" "$rc" "1"

echo "$HEADER" >"$WORK/headeronly.csv"
rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" "$WORK/headeronly.csv" 2>&1) || rc=$?
check "a file with no data rows is an error" "$rc" "1"

# A title pasted out of a document brings a typographic dash with it, which
# looks identical in a terminal. The figure is written as ASCII, so without
# this the failure is a UnicodeEncodeError naming a byte offset into a file
# that was never created. The repository's no-dash rule catches it later;
# this catches it at the moment it is typed.
emdash=$("$PYTHON" -c 'import sys; sys.stdout.write(chr(0x2014))')
rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" -t "p999${emdash}RT" \
	"$WORK/results.csv" 2>&1) || rc=$?
check "a non-ASCII title is refused" "$rc" "1"
contains "and says so in a sentence, not a traceback" "$out" "written as"
case $out in
*Traceback*)
	echo "FAILED   the refusal is a traceback"
	fail=$((fail + 1))
	;;
*)
	echo "ok       and no traceback reaches the user"
	pass=$((pass + 1))
	;;
esac

# --------------------------------------------------------- determinism

"$PYTHON" "$SUT" -o "$WORK/d1.svg" "$WORK/results.csv" 2>/dev/null
"$PYTHON" "$SUT" -o "$WORK/d2.svg" "$WORK/results.csv" 2>/dev/null
if cmp -s "$WORK/d1.svg" "$WORK/d2.svg"; then
	echo "ok       the same input twice gives the same bytes"
	pass=$((pass + 1))
else
	echo "FAILED   regenerating a figure changes it"
	fail=$((fail + 1))
fi

case $(cat "$WORK/d1.svg") in
*"$WORK"*)
	echo "FAILED   the figure embeds the input path"
	fail=$((fail + 1))
	;;
*)
	echo "ok       and embeds no input path"
	pass=$((pass + 1))
	;;
esac

# ------------------------------------------------- the shipped results
#
# The figure in the repository has to be the one this tool draws from the
# file beside it, which is decision 86. If results.csv changes and the
# committed SVG is not regenerated, this fails.

SHIPPED=$ROOT/projects/08-preempt-rt/results
if [ -f "$SHIPPED/results.csv" ] && [ -f "$SHIPPED/ext-p999-matrix.svg" ]; then
	"$PYTHON" "$SUT" -o "$WORK/shipped.svg" "$SHIPPED/results.csv" \
		2>/dev/null
	if cmp -s "$WORK/shipped.svg" "$SHIPPED/ext-p999-matrix.svg"; then
		echo "ok       the committed figure matches the committed results"
		pass=$((pass + 1))
	else
		echo "FAILED   the committed figure is stale: regenerate it with"
		echo "           ./go matrix -o projects/08-preempt-rt/results/ext-p999-matrix.svg \\"
		echo "               projects/08-preempt-rt/results/results.csv"
		fail=$((fail + 1))
	fi
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
