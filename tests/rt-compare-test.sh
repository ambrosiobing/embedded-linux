#!/bin/sh
#
# rt-compare-test.sh - the relationship between the two instruments,
# against data whose answer is known before the program runs.
#
# The comparison this project exists to make is easy to state wrongly, and
# this repository stated it wrongly in three documents: that the difference
# between the external and internal maxima is the cost of the GPIO write.
# It is not. The external instrument measures the interval between two
# edges, so a constant cost appears in both and subtracts out.
#
# What the algebra says, and what this test checks against a simulation:
#
#   P_i = T + (L_i+1 - L_i) + (S_i+1 - S_i)
#
#   mean(P)   = T exactly, whatever S is
#   sd(P)     = sqrt(2) * sd(L)        when S is constant and L independent
#   var(P)    = 2 var(L) + 2 var(S)    in general
#   max|dev P| tracks max(L) above its mean
#
# The generator builds a latency series, derives the periods from it, and
# writes all three files in the formats the board produces: rt-toggle's
# microsecond histogram, cyclictest's -h output with its index column, and
# rt-analyze's signed 2 us bins labelled by their left edge. So the test
# exercises the parsing of three different file shapes as well as the
# arithmetic.
#
# Standard library only, no numpy, because the program under test needs
# none and the test should not need more than the program.
#
#   sh tests/rt-compare-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-rt/files/rt-compare
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

between() {
	label=$1
	value=$2
	low=$3
	high=$4
	verdict=$(awk -v v="$value" -v l="$low" -v h="$high" \
		'BEGIN { print (v >= l && v <= h) ? "yes" : "no" }')
	if [ "$verdict" = yes ]; then
		echo "ok       $label ($value in [$low, $high])"
		pass=$((pass + 1))
	else
		echo "FAILED   $label: $value not in [$low, $high]"
		fail=$((fail + 1))
	fi
}

field() {
	"$PYTHON" -c "import json,sys; print(json.load(sys.stdin)['$1'])"
}

# ------------------------------------------------------------ generator

cat >"$WORK/make_run.py" <<'PYTHON'
"""Write one run's three files from a known latency series.

    make_run.py DIR LABEL WRITE_JITTER_US [SPIKE_US]

WRITE_JITTER_US is the standard deviation of the GPIO write cost. The
constant part of that cost is deliberately large and deliberately
irrelevant: if it showed up anywhere in the output, the model would be
wrong.
"""
import math
import os
import random
import sys

directory, label = sys.argv[1], sys.argv[2]
write_jitter = float(sys.argv[3])
spike = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0
# Lag-one correlation of the latency series. Under load, late wake-ups
# arrive in bursts rather than independently, and for an AR(1) series the
# ratio the program reports falls to sqrt(2 (1 - rho)), exactly.
rho = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0

N = 120000
PERIOD_US = 2000.0
WRITE_CONST_US = 6.0

random.seed(20260916)

# A one-sided latency distribution, the shape a scheduler actually makes.
latency = [random.gammavariate(2.0, 2.0) for _ in range(N)]
if rho > 0:
    smoothed = [latency[0]]
    for raw in latency[1:]:
        smoothed.append(rho * smoothed[-1] + math.sqrt(1 - rho * rho) * raw)
    latency = smoothed
if spike > 0:
    latency[N // 3] += spike

write = [WRITE_CONST_US + random.gauss(0.0, write_jitter) for _ in range(N)]
edge = [i * PERIOD_US + latency[i] + write[i] for i in range(N)]
period = [edge[i + 1] - edge[i] for i in range(N - 1)]

mean_period = sum(period) / len(period)
deviation = [p - mean_period for p in period]


def write_histogram(path, values, width, header, signed):
    counts = {}
    for v in values:
        b = math.floor(v / width) * width
        counts[b] = counts.get(b, 0) + 1
    with open(path, "w", encoding="ascii") as handle:
        handle.write(header)
        for b in sorted(counts):
            handle.write("%d %d\n" % (b, counts[b]) if not signed
                         else "%.1f %d\n" % (b, counts[b]))


# rt-toggle: microsecond bins, comment header carrying its own summary.
write_histogram(
    os.path.join(directory, label + "-toggle.txt"), latency, 1.0,
    "# rt-toggle\n# chip /dev/gpiochip0 line 20 cpu 3 priority 80\n"
    "# bin_us count\n", False)

# rt-analyze: signed deviation, 2 us bins labelled by their left edge.
write_histogram(
    os.path.join(directory, label + "-external-hist.txt"), deviation, 2.0,
    "# deviation_us count\n", True)

# cyclictest -h: an index column, one count column per thread, and a
# trailing comment block that must not be read as data.
counts = {}
for v in latency:
    b = int(v)
    counts[b] = counts.get(b, 0) + 1
with open(os.path.join(directory, label + "-cyclictest.txt"), "w",
          encoding="ascii") as handle:
    handle.write("# /dev/cpu_dma_latency set to 0us\n")
    handle.write("# Histogram\n")
    for b in range(0, max(counts) + 1):
        handle.write("%06d %06d\n" % (b, counts.get(b, 0)))
    handle.write("# Total: %06d\n" % len(latency))
    handle.write("# Min Latencies: %05d\n" % min(int(v) for v in latency))
    handle.write("# Max Latencies: %05d\n" % max(int(v) for v in latency))

# And the truth, for the test to compare against.
mean_l = sum(latency) / len(latency)
var_l = sum((v - mean_l) ** 2 for v in latency) / len(latency)
var_p = sum(d * d for d in deviation) / len(deviation)
with open(os.path.join(directory, label + ".truth"), "w",
          encoding="ascii") as handle:
    handle.write("sd_latency=%.4f sd_period=%.4f mean_period=%.4f "
                 "ratio=%.4f max_latency=%.4f\n"
                 % (math.sqrt(var_l), math.sqrt(var_p), mean_period,
                    math.sqrt(var_p) / math.sqrt(var_l), max(latency)))
PYTHON

truth() {
	sed -n "s/.*$2=\([0-9.]*\).*/\1/p" "$WORK/$1.truth"
}

# ------------------------------- a constant write cost is invisible

"$PYTHON" "$WORK/make_run.py" "$WORK" steady 0.0
out=$("$PYTHON" "$SUT" --results "$WORK" --json steady)

# The simulation put a 6 us constant write cost in. If any of it reached
# the output, the model this project rests on would be wrong.
between "the two instruments agree to within a few percent of sqrt(2)" \
	"$(printf '%s' "$out" | field sd_ratio)" 1.39 1.44
between "and no write-path variation is invented from a constant cost" \
	"$(printf '%s' "$out" | field write_path_sd_us)" 0.0 0.35

want_sd=$(truth steady sd_latency)
lo=$(awk -v s="$want_sd" 'BEGIN { print s - 0.2 }')
hi=$(awk -v s="$want_sd" 'BEGIN { print s + 0.2 }')
between "the internal spread is recovered from its histogram" \
	"$(printf '%s' "$out" | field int_sd_us)" "$lo" "$hi"

want_ratio=$(truth steady ratio)
lo=$(awk -v s="$want_ratio" 'BEGIN { print s - 0.05 }')
hi=$(awk -v s="$want_ratio" 'BEGIN { print s + 0.05 }')
between "and the ratio matches the one the simulation produced" \
	"$(printf '%s' "$out" | field sd_ratio)" "$lo" "$hi"

# -------------------------------- a varying write cost is what shows up

"$PYTHON" "$WORK/make_run.py" "$WORK" jittery 2.0
out=$("$PYTHON" "$SUT" --results "$WORK" --json jittery)
between "2 us of write jitter is recovered as write-path variation" \
	"$(printf '%s' "$out" | field write_path_sd_us)" 1.6 2.4
between "and it pushes the ratio above sqrt(2)" \
	"$(printf '%s' "$out" | field sd_ratio)" 1.45 1.9

# --------------------------------------------- one isolated late wake-up

"$PYTHON" "$WORK/make_run.py" "$WORK" spike 0.0 150
out=$("$PYTHON" "$SUT" --results "$WORK" --json spike)
between "a 150 us spike reaches the internal maximum" \
	"$(printf '%s' "$out" | field int_max_us)" 150 165
between "and the external maximum tracks it" \
	"$(printf '%s' "$out" | field ext_max_abs_us)" 145 165
between "so the two maxima agree to within a couple of bins" \
	"$(printf '%s' "$out" | field max_agreement_us)" -4 4

# ------------------------------------------ the cyclictest file is read

between "cyclictest's own histogram is parsed" \
	"$(printf '%s' "$out" | field cyc_count)" 119999 120001
want_max=$(truth spike max_latency)
lo=$(awk -v s="$want_max" 'BEGIN { print s - 2 }')
hi=$(awk -v s="$want_max" 'BEGIN { print s + 2 }')
between "and its maximum agrees with the toggler's" \
	"$(printf '%s' "$out" | field cyc_max_us)" "$lo" "$hi"

# The trailing "# Total:" and "# Max Latencies:" lines are comments, and
# reading either as a data row would add a bin of 60000 counts at 0.
between "the trailing comment block is not read as data" \
	"$(printf '%s' "$out" | field cyc_count)" 119999 120001

# ------------------------------------------------- what it says in prose

text=$("$PYTHON" "$SUT" --results "$WORK" steady)
contains "the human output names the expected ratio" "$text" "sqrt(2)"
contains "and reports the write-path figure" "$text" "write-path variation"

# ------------------------------------- correlated latencies, under load

# An AR(1) series with rho = 0.7 has a lag-one correlation of 0.7, so the
# ratio falls to sqrt(2 (1 - rho)) = 0.775. This is the case the program
# has to refuse to interpret: the spread looks better than sqrt(2) would
# predict, and that says the wake-ups arrived in bursts, not that the GPIO
# write is free.
"$PYTHON" "$WORK/make_run.py" "$WORK" bursty 0.0 0 0.7
out=$("$PYTHON" "$SUT" --results "$WORK" --json bursty)
between "correlated latencies drop the ratio to sqrt(2(1-rho))" \
	"$(printf '%s' "$out" | field sd_ratio)" 0.72 0.83
between "and no write-path variation is claimed from them" \
	"$(printf '%s' "$out" | field write_path_sd_us)" 0.0 0.05

text=$("$PYTHON" "$SUT" --results "$WORK" bursty)
contains "and the program says why rather than asserting a cost" "$text" \
	"statement about correlation"

# ------------------------------------------------------------- errors

rc=0
out=$("$PYTHON" "$SUT" --results "$WORK" nosuchrun 2>&1) || rc=$?
check "a label with no files is an error" "$rc" "1"
contains "and says which file" "$out" "nosuchrun-toggle.txt"

rc=0
out=$("$PYTHON" "$SUT" 2>&1) || rc=$?
check "no label and no overrides is a usage error" "$rc" "2"

# A run whose cyclictest file is absent is still worth comparing: the two
# instruments that matter are the toggler and the wire.
rm -f "$WORK/steady-cyclictest.txt"
rc=0
out=$("$PYTHON" "$SUT" --results "$WORK" --json steady 2>&1) || rc=$?
check "a missing cyclictest file does not stop the comparison" "$rc" "0"
case $out in
*cyc_count*)
	echo "FAILED   and its columns are left out"
	fail=$((fail + 1))
	;;
*)
	echo "ok       and its columns are left out"
	pass=$((pass + 1))
	;;
esac

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
