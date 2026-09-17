#!/bin/sh
#
# rt-plot-test.sh - the figure generator, against all three instrument
# formats and against the defect that the first render had.
#
# The fixtures here are copied from real output rather than invented. That
# rule exists because Project 8 shipped a cyclictest parser written against
# a remembered format: the stub emitted a "T: 0" line, the parser looked for
# one, both agreed, and the column was blank in every row ever written. A
# fixture written from memory records an assumption about a tool, and the
# assumption is the thing most likely to be wrong.
#
#   sh tests/rt-plot-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/scripts/rt-plot.py
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

# ------------------------------------------------------------- fixtures

# cyclictest -t 1 -h 400 -q, trimmed. Six-digit zero padding on both
# fields, comment lines above and below the data, which is what the board
# actually writes.
cat >"$WORK/cyclictest.txt" <<'EOF'
# /dev/cpu_dma_latency set to 0us
000004 000010
000011 004413
000012 001129
000044 000001
000100 000001
# Total: 000005554
# Min Latencies: 00004
# Avg Latencies: 00013
# Max Latencies: 00100
EOF

# rt-toggle's own file: five comment lines then plain integer pairs.
cat >"$WORK/toggle.txt" <<'EOF'
# rt-toggle
# chip /dev/gpiochip0 line 20 cpu 3 priority 80
# toggle_us 1000 edges 30000 overflow 0
# min_us 4.000 mean_us 12.340 max_us 44.500
# p99_us 21 p999_us 30
# bin_us count
7 120
8 900
44 1
EOF

# rt-analyze --hist: one decimal place, and bins either side of zero,
# because it histograms a deviation rather than a latency.
cat >"$WORK/external.txt" <<'EOF'
# deviation_us count
-4.0 12
-2.0 300
0.0 1400
2.0 280
30.0 1
EOF

# --------------------------------------------------------------- cases

out=$("$PYTHON" "$SUT" -o "$WORK/a.svg" "$WORK/cyclictest.txt:generic" 2>&1)
contains "cyclictest: counts every sample" "$out" "5554 samples"
contains "cyclictest: one series" "$out" "1 series"

out=$("$PYTHON" "$SUT" -o "$WORK/b.svg" "$WORK/toggle.txt" 2>&1)
contains "rt-toggle: comment header is skipped" "$out" "1021 samples"

out=$("$PYTHON" "$SUT" -o "$WORK/c.svg" "$WORK/external.txt" 2>&1)
contains "rt-analyze: negative bins are read" "$out" "1993 samples"

# A single series needs no legend; the title names it. Two series must
# carry one, so that identity is never colour alone.
"$PYTHON" "$SUT" -o "$WORK/one.svg" "$WORK/cyclictest.txt:generic" 2>/dev/null
svg=$(cat "$WORK/one.svg")
lacks "one series draws no legend swatch" "$svg" '<rect x="62.0"'

"$PYTHON" "$SUT" -o "$WORK/two.svg" \
	"$WORK/cyclictest.txt:generic" "$WORK/toggle.txt:real-time" 2>/dev/null
svg=$(cat "$WORK/two.svg")
contains "two series name the first" "$svg" ">generic<"
contains "two series name the second" "$svg" ">real-time<"
contains "two series use the second hue" "$svg" "#eb6834"

# ------------------------------------------- the defect the first render had
#
# log10(1) is 0, so the obvious mapping puts a one-sample bin at the same
# height as an empty one. The four tail bins of the first real histogram
# vanished that way, and those bins are the finding. Proving this needs a
# coordinate, not a prose assertion: the baseline is MARGIN_TOP plus the
# plot height, 42 + 266, so any drawn sample must sit above y=308.

cat >"$WORK/single.txt" <<'EOF'
# latency_us count
50 1
EOF
"$PYTHON" "$SUT" -o "$WORK/single.svg" "$WORK/single.txt" 2>/dev/null
top=$(sed -n 's/.*<polyline points="\([^"]*\)".*/\1/p' "$WORK/single.svg" |
	tr ' ' '\n' | awk -F, 'NF == 2 { if (min == "" || $2 < min) min = $2 }
		END { print min + 0 }')
verdict=$(awk -v y="$top" 'BEGIN { print (y < 300) ? "above" : "on" }')
check "a single sample is drawn above the baseline" "$verdict" "above"
check "and the baseline itself is where it should be" \
	"$(grep -c 'y2="308.0"' "$WORK/single.svg")" "1"

# ---------------------------------------------------------- refusals

rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" "$WORK/missing.txt" 2>&1) || rc=$?
check "a missing file is an error" "$rc" "1"

printf '# only a comment\n' >"$WORK/empty.txt"
rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" "$WORK/empty.txt" 2>&1) || rc=$?
check "a file with no bins is an error" "$rc" "1"
contains "and says so" "$out" "no occupied bins"

printf '# h\n11 notanumber\n' >"$WORK/bad.txt"
rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" "$WORK/bad.txt" 2>&1) || rc=$?
check "an unparseable line is an error, not a skip" "$rc" "1"
contains "and names the line number" "$out" "bad.txt:2"

printf '# h\n11\n' >"$WORK/short.txt"
rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" "$WORK/short.txt" 2>&1) || rc=$?
check "a one-field line is an error" "$rc" "1"

printf '# h\n11 -3\n' >"$WORK/negative.txt"
rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" "$WORK/negative.txt" 2>&1) || rc=$?
check "a negative count is an error" "$rc" "1"

rc=0
out=$("$PYTHON" "$SUT" -o "$WORK/x.svg" \
	"$WORK/toggle.txt:a" "$WORK/toggle.txt:b" "$WORK/toggle.txt:c" \
	"$WORK/toggle.txt:d" "$WORK/toggle.txt:e" 2>&1) || rc=$?
check "a fifth series is refused rather than given a new hue" "$rc" "1"
contains "and says to draw two figures" "$out" "two figures"

# ------------------------------------------------------------- labelling

"$PYTHON" "$SUT" -o "$WORK/n.svg" \
	"$WORK/toggle.txt" "$WORK/cyclictest.txt" 2>/dev/null
svg=$(cat "$WORK/n.svg")
contains "an unlabelled input is named by its basename" "$svg" ">toggle.txt<"

# A Windows path carries a colon that is not a label separator.
"$PYTHON" "$SUT" -o "$WORK/w.svg" "$WORK/toggle.txt:kept" 2>/dev/null
contains "an explicit label wins" "$(cat "$WORK/w.svg")" "kept"

# --------------------------------------------------------- determinism

"$PYTHON" "$SUT" -o "$WORK/d1.svg" "$WORK/cyclictest.txt:g" 2>/dev/null
"$PYTHON" "$SUT" -o "$WORK/d2.svg" "$WORK/cyclictest.txt:g" 2>/dev/null
if cmp -s "$WORK/d1.svg" "$WORK/d2.svg"; then
	echo "ok       the same input twice gives the same bytes"
	pass=$((pass + 1))
else
	echo "FAILED   regenerating a figure changes it"
	fail=$((fail + 1))
fi

lacks "and embeds no input path" "$(cat "$WORK/d1.svg")" "$WORK"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
