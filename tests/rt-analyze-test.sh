#!/bin/sh
#
# rt-analyze-test.sh - the external instrument's arithmetic, without the
# instrument.
#
# A square wave with known edge times is synthesised, saved in the format
# the MCC 118 capture produces, and handed to the analysis. Because the
# answer is known before the program runs, this is the one part of Project
# 8 that can be proven correct rather than merely exercised.
#
# The case that matters most is the one the usual recipe glosses over. Linear
# interpolation of a threshold crossing recovers sub-sample timing only
# when the edge is slower than the sample period. A 3.3 V logic edge is
# not: the sample before every crossing sits at 0 V and the one after it at
# 3.3 V, the interpolated fraction is one half every time, and the
# resolution is exactly one sample period however the arithmetic is
# dressed up. Both regimes are generated here, and the test asserts the
# difference between them in microseconds rather than in prose.
#
#   sh tests/rt-analyze-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-rt/files/rt-analyze
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

# Numeric assertions go through awk, because sh has no floating point and
# every one of these is a measurement with a tolerance rather than a value
# with an equality.
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
	printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1
}

if ! "$PYTHON" -c "import numpy" 2>/dev/null; then
	echo "FAILED   numpy is not installed, and this test is arithmetic."
	echo "         Run scripts/host-setup.sh, or:"
	echo "         sudo apt-get install -y python3-numpy"
	exit 1
fi

# ------------------------------------------------------------ generator
#
# One model, two regimes, selected by the width of the edge:
#
#   width 0 us   an ideal logic edge, one sample low and the next high
#   width 30 us  an edge deliberately slowed by a series RC, spanning
#                three samples, which is what makes interpolation mean
#                something
#
# The jitter is applied to the commanded toggle times, so the true period
# deviations are known exactly and are written out next to the samples.

cat >"$WORK/make_wave.py" <<'PYTHON'
import sys

import numpy as np

out = sys.argv[1]
width_us = float(sys.argv[2])
seconds = float(sys.argv[3])
jitter_us = float(sys.argv[4])
late_edge = int(sys.argv[5]) if len(sys.argv) > 5 else -1

# The DAQ clock is not the Pi's clock. Fifty parts per million is an
# ordinary difference between two crystals, and it matters here for a
# reason beyond the offset column: it makes the sample grid drift through
# the toggle grid, so the quantisation residual of an unresolved edge
# sweeps the whole sample interval instead of sitting at one value. A
# generator with both clocks exactly commensurate would hide the effect
# this test exists to measure.
SKEW_PPM = 50.0

FS = 100000.0
TOGGLE_US = 1000.0
HIGH = 3.3

rng = np.random.default_rng(20260915)
n_toggle = int(seconds * 1e6 / TOGGLE_US)

nominal = np.arange(n_toggle) * TOGGLE_US * 1e-6
jitter = rng.uniform(0.0, jitter_us, n_toggle) * 1e-6
if late_edge >= 0:
    # One rising edge arrives 60 us late. Rising edges are the even ones:
    # the line starts low and the first toggle takes it high.
    jitter[2 * late_edge] += 60e-6
edges = nominal + jitter

# The level established by toggle i. Even toggles drive the line high.
levels = np.where(np.arange(n_toggle) % 2 == 0, HIGH, 0.0)

t = np.arange(int(seconds * FS)) / (FS * (1.0 + SKEW_PPM * 1e-6))
k = np.searchsorted(edges, t, side="right") - 1
k_clipped = np.clip(k, 0, n_toggle - 1)

after = np.where(k >= 0, levels[k_clipped], 0.0)
before = np.where(k >= 1, levels[np.clip(k - 1, 0, None)], 0.0)

if width_us <= 0:
    samples = after
else:
    ramp = np.clip((t - edges[k_clipped]) / (width_us * 1e-6), 0.0, 1.0)
    ramp = np.where(k >= 0, ramp, 1.0)
    samples = before + (after - before) * ramp

np.save(out, samples.astype(np.float32))

# The truth, for the test to compare against: periods between rising edges.
rising = edges[::2]
periods_us = np.diff(rising) * 1e6
deviation = periods_us - periods_us.mean()
with open(out + ".truth", "w", encoding="ascii") as handle:
    handle.write("rising=%d mean_us=%.4f sd_us=%.4f max_abs_us=%.4f\n"
                 % (rising.size, periods_us.mean(), deviation.std(),
                    np.abs(deviation).max()))
PYTHON

# What the generator commanded, as opposed to what the analysis recovered.
truth() {
	sed -n "s/.*$2=\([0-9.]*\).*/\1/p" "$1.npy.truth"
}

# ------------------------------------------- an ideal edge cannot be read
# below one sample period

"$PYTHON" "$WORK/make_wave.py" "$WORK/ideal.npy" 0 4 5
ideal=$("$PYTHON" "$SUT" --toggle-us 1000 "$WORK/ideal.npy" 2>"$WORK/ideal.err")

check "every rising edge is found" "$(field "$ideal" edges)" \
	"$(truth "$WORK/ideal" rising)"
between "the mean period survives quantisation" \
	"$(field "$ideal" mean_us)" 1999.5 2000.5
between "and so does the clock offset" \
	"$(field "$ideal" clock_offset_ppm)" -250 250
between "but nothing was interpolated" \
	"$(field "$ideal" subsample_fraction)" 0.0 0.05
contains "and the program says so" "$(cat "$WORK/ideal.err")" \
	"per-edge resolution of this capture is one sample period, 10.0 us"

# The spread that comes back is not the spread that went in. Every edge is
# rounded up to the next sample, so every period carries the difference of
# two rounding residuals, and the reported spread is roughly twice the one
# that was injected. A reader taking that number for jitter would be
# reading the sample clock of the instrument.
want_ideal=$(truth "$WORK/ideal" sd_us)
between "about 2 us of spread was injected" "$want_ideal" 1.8 2.3
between "and the unresolved edge reports over twice that" \
	"$(field "$ideal" sd_us)" 3.5 5.5

# ---------------------------------------------- a slowed edge can be read

"$PYTHON" "$WORK/make_wave.py" "$WORK/ramp.npy" 30 4 5
ramp=$("$PYTHON" "$SUT" --toggle-us 1000 "$WORK/ramp.npy" 2>"$WORK/ramp.err")

between "every crossing is interpolated" \
	"$(field "$ramp" subsample_fraction)" 0.95 1.0
check "and no warning is printed" "$(wc -c <"$WORK/ramp.err" | tr -d ' ')" "0"
between "the mean period is right" "$(field "$ramp" mean_us)" 1999.9 2000.1

# This is the whole claim of the method: the recovered spread matches the
# spread that was put in, to a fraction of a microsecond, using an
# instrument whose samples are 10 us apart.
want_sd=$(truth "$WORK/ramp" sd_us)
low=$(awk -v s="$want_sd" 'BEGIN { print s - 0.3 }')
high=$(awk -v s="$want_sd" 'BEGIN { print s + 0.3 }')
between "the recovered spread matches the injected one" \
	"$(field "$ramp" sd_us)" "$low" "$high"

# ------------------------------------------------- one late edge is found

"$PYTHON" "$WORK/make_wave.py" "$WORK/late.npy" 30 4 5 900
late=$("$PYTHON" "$SUT" --toggle-us 1000 "$WORK/late.npy" 2>/dev/null)
between "a single 60 us late edge sets the maximum" \
	"$(field "$late" max_abs_us)" 55 66
between "and leaves the 99th percentile alone" \
	"$(field "$late" p99_us)" 0 12

# --------------------------------------------- the clock offset is not jitter

# Analysing the same capture at a rate 1000 ppm off is what a DAQ clock
# that differs from the Pi's by 1000 ppm looks like. It has to appear in
# the offset column and not in the spread.
skewed=$("$PYTHON" "$SUT" --rate 100100 --toggle-us 1000 "$WORK/ramp.npy" 2>/dev/null)
between "a clock difference lands in the offset column" \
	"$(field "$skewed" clock_offset_ppm)" -1100 -900
between "and not in the spread" "$(field "$skewed" sd_us)" 0 3

# ------------------------------------------------------- outputs and errors

hist=$(field "$ramp" histogram)
check "the histogram was written next to the capture" \
	"$(basename "$hist")" "ramp_hist.txt"
contains "and is labelled" "$(head -1 "$hist")" "deviation_us count"
between "and holds every period" \
	"$(awk 'NR > 1 { n += $2 } END { print n }' "$hist")" 1990 2000

json=$("$PYTHON" "$SUT" --json --toggle-us 1000 "$WORK/ramp.npy" 2>/dev/null)
same=$("$PYTHON" -c "import json,sys; d=json.loads(sys.stdin.read()); print('%.3f' % d['mean_us'])" <<EOF
$json
EOF
)
check "the JSON form agrees with the line form" "$same" \
	"$(field "$ramp" mean_us)"

# The path goes in as an argument rather than inside the program text.
# Under Git Bash on Windows an argument that looks like a path is
# translated for the native interpreter and a string inside -c is not, so
# the other form works everywhere except on the laptop this was written on.
"$PYTHON" -c \
	"import sys, numpy as np; np.save(sys.argv[1], np.zeros(1000, 'f4'))" \
	"$WORK/flat.npy"
rc=0
out=$("$PYTHON" "$SUT" "$WORK/flat.npy" 2>&1) || rc=$?
check "a capture with no edges is an error" "$rc" "1"
contains "and explains what to check" "$out" "jumper from header pin 38"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
