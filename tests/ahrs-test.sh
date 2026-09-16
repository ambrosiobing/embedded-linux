#!/bin/sh
#
# ahrs-test.sh - the orientation filter, checked against physics.
#
# The filter's own --selftest does the work, and this wrapper exists so
# that tests/*.sh discovers it and so that a host without a working python
# skips rather than failing.
#
# WHY THE CHECKS ARE ROTATIONS AND NOT REFERENCE OUTPUT
#
# A sign error in a quaternion filter does not look like an error. The
# orientation tracks smoothly, responds to movement, and is mirrored. Diffed
# against a recorded run from the same broken filter it passes forever.
#
# So every check is a rotation whose answer comes from the geometry rather
# than from another program: gravity on an axis means ninety degrees about
# another, and a gyroscope turning at a known rate for a known time has
# turned by their product. Two independent paths to the same angle is what
# makes a sign convention visible, and it is what caught the first version
# of these expectations, which were themselves inverted.
#
#   sh tests/ahrs-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/meta-bench/recipes-bench/bench-iio/files/ahrs.py

# A python that runs, not a python that exists. Windows ships a python3
# stub that satisfies "command -v" and then advertises the Microsoft Store.
PY=
for candidate in ${PYTHON:-} python3 python; do
	[ -n "$candidate" ] || continue
	if "$candidate" -c 'import math, sys' >/dev/null 2>&1; then
		PY=$candidate
		break
	fi
done
if [ -z "$PY" ]; then
	echo "skip     no working python on this host, so the filter is not run"
	exit 0
fi

pass=0
fail=0

out=$("$PY" "$SUT" --selftest 2>&1) || true
printf '%s\n' "$out" | sed 's/^/         /'

# Every named check has to appear AND be ok. Counting failures alone would
# pass a selftest that silently stopped running checks, which is the same
# defect this repository has now found in three of its own suites.
for name in \
	"level roll" \
	"level pitch" \
	"rolled 90 about x" \
	"rolled -90 about x" \
	"pitched 90 about y" \
	"gyro integrates in the right direction" \
	"heading with the field on +x" \
	"heading with the field on +y" \
	"a zero dt is rejected"
do
	case $out in
	*"ok       $name"*)
		echo "ok       $name"
		pass=$((pass + 1))
		;;
	*)
		echo "FAILED   $name did not pass in the selftest"
		fail=$((fail + 1))
		;;
	esac
done

case $out in
*"selftest failures: 0"*)
	echo "ok       the selftest reports no failures"
	pass=$((pass + 1))
	;;
*)
	echo "FAILED   the selftest reports failures"
	fail=$((fail + 1))
	;;
esac

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
