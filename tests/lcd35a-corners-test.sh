#!/bin/sh
#
# lcd35a-corners-test.sh - the calibration arithmetic, which is the one
# piece of Project 7 that is pure computation and therefore fully testable
# with no panel, no finger and no kernel.
#
# Everything else in this project needs hardware to be sure of. This does
# not, so it is checked properly: the identity case, a real measured case,
# the refusals, and the warning that fires when the matrix comes out far
# enough from the identity to mean the overlay's clip limits are wrong.
#
# The warning is worth a test of its own. It is advice about a DIFFERENT
# file, and advice that never fires is indistinguishable from advice that
# is never right.
#
#   sh tests/lcd35a-corners-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT=$ROOT/meta-bench/recipes-bench/bench-lcd35a/files/lcd35a-corners

pass=0
fail=0

ok() {
	echo "ok       $1"
	pass=$((pass + 1))
}

no() {
	echo "FAILED   $1"
	fail=$((fail + 1))
	[ $# -gt 1 ] && printf '         %s\n' "$2"
	return 0
}

run() {
	# run ARGS...  -> stdout+stderr in $out, status in $status
	set +e
	out=$(sh "$SCRIPT" "$@" 2>&1)
	status=$?
	set -e
}

[ -f "$SCRIPT" ] || {
	echo "FAILED   missing: $SCRIPT"
	exit 1
}

echo "--- syntax"
if sh -n "$SCRIPT"; then
	ok "the script parses"
else
	no "the script does not parse"
	exit 1
fi

echo
echo "--- the identity case"

# A panel whose raw range is the full converter range needs no correction,
# so the matrix is 1 0 0 0 1 0. This is the case most likely to come out
# with a negative zero in it, which is why it is first.
run 0 4095 0 4095
if [ "$status" -ne 0 ]; then
	no "full range exited $status" "$out"
elif echo "$out" | grep -q 'MATRIX="1.000000 0 0.000000 0 1.000000 0.000000"'; then
	ok "full raw range gives the identity matrix"
else
	no "full raw range did not give the identity" \
		"$(echo "$out" | grep MATRIX || echo 'no MATRIX line at all')"
fi

if echo "$out" | grep -q -- '-0.000000'; then
	no "the output contains a negative zero" \
		"correct arithmetic, and it reads like a mistake"
else
	ok "no negative zero in the output"
fi

echo
echo "--- the case the overlay is actually written for"

# ti,x-min = 200 and ti,x-max = 3900 in bench-lcd35a-overlay.dts, so a
# panel that matches its own overlay produces these numbers.
#   scale  = 4095 / 3700 = 1.106757
#   offset = -200 / 3700 = -0.054054
run 200 3900 200 3900
if [ "$status" -ne 0 ]; then
	no "the overlay's own range exited $status" "$out"
elif echo "$out" | grep -q '1.106757 0 -0.054054 0 1.106757 -0.054054'; then
	ok "the overlay's own limits give the expected matrix"
else
	no "the overlay's limits gave an unexpected matrix" \
		"$(echo "$out" | grep MATRIX || echo 'no MATRIX line')"
fi

if echo "$out" | grep -q 'ATTRS{name}=="ADS7846 Touchscreen"'; then
	ok "the udev rule names the device ads7846 registers"
else
	no "the printed rule does not match on the ADS7846 name" \
		"a rule that matches nothing applies no calibration"
fi

if echo "$out" | grep -q 'WARNING'; then
	no "the overlay's own limits produced the warning" \
		"1.1 is close to identity; this warning should be quiet here"
else
	ok "no warning for a matrix close to the identity"
fi

echo
echo "--- the warning fires when it should"

# Half the converter range reachable means scale 2, which means the
# overlay is clipping to a range the panel does not have. The kernel clips
# before libinput scales, so this cannot be fixed by the matrix and the
# script says so.
run 0 2047 0 2047
if [ "$status" -ne 0 ]; then
	no "a far-from-identity case exited $status" "$out"
elif echo "$out" | grep -q 'WARNING'; then
	ok "a scale of 2 produces the warning"
	if echo "$out" | grep -q 'overlay'; then
		ok "and the warning points at the overlay, not at the matrix"
	else
		no "the warning does not say where the real fault is"
	fi
else
	no "a scale of 2 produced no warning" \
		"advice that never fires is advice that is never read"
fi

echo
echo "--- the refusals"

run 3900 200 200 3900
if [ "$status" -eq 0 ]; then
	no "x reversed was accepted" "max must be greater than min"
else
	ok "x max below x min is refused"
fi

run 200 3900 3900 200
if [ "$status" -eq 0 ]; then
	no "y reversed was accepted"
else
	ok "y max below y min is refused"
fi

run 200 200 200 3900
if [ "$status" -eq 0 ]; then
	no "a zero-width x range was accepted" "this would divide by zero"
else
	ok "a zero-width range is refused rather than dividing by zero"
fi

run 200 3900 200 abc
if [ "$status" -eq 0 ]; then
	no "a non-numeric argument was accepted"
else
	ok "a non-numeric argument is refused"
fi

run 200 3900 200
if [ "$status" -eq 0 ]; then
	no "three arguments were accepted" "four corners means four numbers"
else
	ok "the wrong number of arguments is refused"
fi

echo
echo "--- the help, which is where the evtest recipe lives"

run -h
if [ "$status" -ne 0 ]; then
	no "-h exited $status"
else
	ok "-h exits zero"
fi
if echo "$out" | grep -q 'evtest'; then
	ok "the help says how to get the four numbers"
else
	no "the help does not mention evtest" \
		"the arithmetic is useless without the measurement"
fi

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
