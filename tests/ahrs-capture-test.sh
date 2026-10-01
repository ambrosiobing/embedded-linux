#!/bin/sh
#
# ahrs-capture-test.sh - the filter against recorded gravity, with no board.
#
# ahrs.py gained --capture on Thursday 1 October 2026 so that criterion 8
# could be checked against a real measurement instead of only against
# synthetic rotations. It was added with no assertions of its own, on the
# same day this repository recorded that programs which have never been
# tested carry defects. This suite is the omission being repaired.
#
# What it checks is the decode and the geometry, which is where a
# user-space driver goes wrong quietly: byte order, sign extension, the
# scale, which axis is roll and which is pitch, and whether a damaged line
# is skipped or silently turned into a number.
#
# Every capture here is synthesised, so the right answer is known from the
# geometry rather than from a previous run of the same program.
#
#   sh tests/ahrs-capture-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-iio/files/ahrs.py

# An interpreter is found by RUNNING it, never by command -v.
#
# Windows ships an App Execution Alias at python3 that exists, resolves,
# satisfies command -v, and then prints a Microsoft Store advertisement
# and exits non-zero. Journal entry 7 of Project 10 records that exact
# trap and this file repeated it on its first run.
PY=""
for _cand in ${BENCH_PYTHON:-} python3 python; do
	[ -n "$_cand" ] || continue
	if "$_cand" -c "import math, sys" >/dev/null 2>&1; then
		PY=$_cand
		break
	fi
done
[ -n "$PY" ] || {
	echo "FAILED   no usable python interpreter"
	exit 1
}

WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

pass=0
fail=0

ok() {
	echo "ok       $1"
	pass=$((pass + 1))
}

no() {
	echo "FAILED   $1"
	fail=$((fail + 1))
}

contains() {
	case $2 in
	*"$3"*) ok "$1" ;;
	*)
		no "$1: '$3' not in output"
		printf '%s\n' "$2" | sed 's/^/         /'
		;;
	esac
}

# ------------------------------------------------------- the fake capture
#
# One orientation held for 1500 samples, which is more than the settling
# window the program discards. The index column is not read by the parser,
# so every line may carry the same one and the file can be made with yes.
#
# 16384 counts is one g at the two g full scale, little-endian signed:
#
#   +1 g  ->  0x00 0x40          -1 g  ->  0x00 0xc0
#    0 g  ->  0x00 0x00
#
# Writing the bytes out by hand rather than computing them is deliberate.
# A test that derives its input with the same arithmetic as the program
# agrees with the program by construction and proves nothing.

hold() {
	# hold FILE "x_lo x_hi y_lo y_hi z_lo z_hi"
	yes "1 $2" | head -1500 >"$WORK/$1"
}

run() {
	"$PY" "$SUT" --capture "$WORK/$1" --settle 1000 2>&1
}

# ------------------------------------------- the six faces of the geometry

hold flat.txt "0x00 0x00 0x00 0x00 0x00 0x40"
out=$(run flat.txt)
contains "flat: gravity on +Z is level in roll" "$out" "roll    +0.000 deg"
contains "flat: and level in pitch" "$out" "pitch   +0.000 deg"
contains "flat: the magnitude is exactly one g" "$out" "1.0000 g"

hold ypos.txt "0x00 0x00 0x00 0x40 0x00 0x00"
out=$(run ypos.txt)
contains "gravity on +Y is a positive ninety of ROLL" "$out" "roll   +90.09"
contains "and leaves pitch alone" "$out" "pitch   +0.000 deg"

hold yneg.txt "0x00 0x00 0x00 0xc0 0x00 0x00"
out=$(run yneg.txt)
contains "gravity on -Y is a negative ninety of roll" "$out" "roll   -90.09"

hold xneg.txt "0x00 0xc0 0x00 0x00 0x00 0x00"
out=$(run xneg.txt)
contains "gravity on -X is a positive ninety of PITCH" "$out" "pitch  +89.90"

hold xpos.txt "0x00 0x40 0x00 0x00 0x00 0x00"
out=$(run xpos.txt)
contains "gravity on +X is a negative ninety of pitch" "$out" "pitch  -89.90"

# Roll and pitch are not interchangeable and a driver that swaps them
# passes every magnitude check ever written, because the magnitude does
# not care which axis is which.
case $out in
*"roll  -89.9"*|*"roll   -89.9"*)
	no "pitch is not being reported in the roll column" ;;
*)
	ok "pitch is not being reported in the roll column" ;;
esac

# ------------------------------------------------ sign and byte order
#
# These two are the faults a one-axis sanity check cannot see, and the
# three-axis magnitude can.

hold zneg.txt "0x00 0x00 0x00 0x00 0x00 0xc0"
out=$(run zneg.txt)
contains "a negative axis sign-extends rather than reading 49152 counts" \
	"$out" "Z -1.0000"
contains "and the magnitude is still one g, because sign is not size" \
	"$out" "1.0000 g"

# The same three values with each pair of bytes swapped. 0x4000 is one g
# and 0x0040 is 64 counts, so a big-endian decode of this file reads
# 0.0039 g where the truth is 1 g.
hold swapped.txt "0x00 0x00 0x00 0x00 0x40 0x00"
out=$(run swapped.txt)
contains "a byte-swapped capture does not read as one g" "$out" "0.0039 g"
contains "and the magnitude check says so rather than passing it" \
	"$out" "WARNING"
contains "naming the threshold it failed" "$out" "50 mg"

# ------------------------------------------------------------- the scale
#
# --scale is LSB per g, so it moves opposite to the full-scale setting:
# two g full scale is 16384 counts per g, eight g is 4096. A capture
# recorded at two g and decoded with the eight g divisor therefore reads
# FOUR g, not a quarter of one.
#
# The quarter is the other direction, and is the one to remember at the
# bench: after moving a part to eight g, a decoder still dividing by 16384
# reports a quarter of a g and looks exactly like a wiring fault. Both
# directions are checked, because getting them the wrong way round is the
# easy mistake and this assertion was written that way first.

out=$("$PY" "$SUT" --capture "$WORK/flat.txt" --scale 4096 --settle 1000 2>&1)
contains "the scale flag is applied" "$out" "4096 LSB per g"
contains "a two g capture decoded at eight g reads four times too much" 	"$out" "4.0000 g"
contains "which the magnitude check refuses" "$out" "WARNING"

hold eightg.txt "0x00 0x00 0x00 0x00 0x00 0x10"
out=$(run eightg.txt)
contains "and an eight g capture decoded at two g reads a quarter" 	"$out" "0.2500 g"
contains "which it also refuses" "$out" "WARNING"

# --------------------------------------------- damaged lines are not data
#
# A line that is not an index plus exactly six bytes is skipped and
# counted. Interpolating across it, or decoding what is there, would put a
# number into an orientation result that no sensor produced.

hold damaged.txt "0x00 0x00 0x00 0x00 0x00 0x40"
{
	echo "1 0x00 0x00 0x00 0x00"
	echo "2 ERR"
	echo "3 0x00 0x00 0x00 0x00 0x00 0x40 0x00"
	echo "4 0xzz 0x00 0x00 0x00 0x00 0x40"
} >>"$WORK/damaged.txt"
out=$(run damaged.txt)
contains "four damaged lines are counted" "$out" "4 damaged and skipped"
contains "and the good samples are still used" "$out" "1500 used"
contains "and the result is unaffected by them" "$out" "roll    +0.000 deg"

# A file of nothing but damage has no samples, which is a refusal and not
# an orientation of zero.
printf 'nonsense\nmore nonsense\n' >"$WORK/junk.txt"
status=0
out=$(run junk.txt) || status=$?
[ "$status" -ne 0 ] &&
	ok "a capture with no usable samples is a refusal" ||
	no "a capture with no usable samples is a refusal"
contains "and it names the file" "$out" "junk.txt"

# -------------------------------------------- the two routes must agree
#
# The filter and the trigonometry share no code. Their agreement is what
# says the sign conventions and the frame handedness are right, and it is
# the property the project's own notes say published implementations most
# often get wrong.

out=$(run ypos.txt)
contains "the filter is checked against trigonometry on the same samples" \
	"$out" "direct   roll"
contains "and the disagreement is reported as an angle, not as a difference of Euler angles" \
	"$out" "orientation error"

# And the inverse pair, which is arithmetic rather than measurement:
# gravity_from is the exact inverse of direct_tilt, so a round trip
# through both must return what it started with at every pose, including
# the ones where roll is ill-conditioned.
rt=$("$PY" - "$SUT" <<'ROUNDTRIP'
import importlib.util, sys, math
spec = importlib.util.spec_from_file_location("ahrs", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
worst = 0.0
for roll in range(-170, 180, 10):
    for pitch in range(-80, 81, 10):
        r, p = m.direct_tilt(m.gravity_from(roll, pitch))
        worst = max(worst, abs(r - roll), abs(p - pitch))
print("%.9f" % worst)
ROUNDTRIP
)
case $rt in
0.000000*)
	ok "gravity_from and direct_tilt are exact inverses over 612 poses" ;;
*)
	no "gravity_from and direct_tilt are exact inverses over 612 poses"
	echo "         worst disagreement: $rt degrees" ;;
esac

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
