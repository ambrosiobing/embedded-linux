#!/bin/sh
#
# accel-fit-test.sh - scripts/accel-fit.py recovers what it is given, and
# refuses what it cannot determine.
#
# The program it exercises reads static accelerometer poses and reports a
# per-axis sensitivity and offset, using only the fact that a stationary
# board has |a| = g whichever way it points.
#
# WHY A SYNTHETIC FIXTURE AND NOT THE BENCH DATA.
#
# The real poses in projects/10-iio-iks4a1/docs/evidence/ are the thing
# being measured, so they cannot also be the answer: running the fit on
# them and comparing against its own published output would check that the
# program still does what it did, not that what it does is right. Here the
# sensitivities and offsets are CHOSEN, poses are generated from them, and
# the test asks whether the program finds the numbers it was never told.
#
# A fit that cannot fail is the failure this repository keeps finding in
# its own tools, so the refusals are driven too: too few poses, an axis
# that never points both ways, and poses that are all nearly the same.
# Each of those returns plausible numbers if nobody checks, which is why
# they are refusals in the program rather than notes in a document.
#
#   sh tests/accel-fit-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIT=$ROOT/scripts/accel-fit.py

. "$ROOT/tests/lib/python.sh"
bench_python "scripts/accel-fit.py went unchecked"

pass=0
fail=0

say() {
	if [ "$1" = yes ]; then
		pass=$((pass + 1))
		printf 'ok   %s\n' "$2"
	else
		fail=$((fail + 1))
		printf 'FAIL %s\n' "$2"
	fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

out=$TMP/out
status=0

run() { # args...
	status=0
	"$PYTHON" "$FIT" "$@" >"$out" 2>&1 || status=$?
}

said() { # description pattern
	if grep -q "$2" "$out"; then say yes "$1"; else say no "$1"; fi
}

# ---------------------------------------- the fixture, with known answers
#
# Sensitivities and offsets are chosen here and nowhere else. The poses are
# generated from them, including four deliberately tilted ones, because a
# set of six exactly axis-aligned poses is the easiest case and not the one
# the bench produces.
TRUE_SX=16400; TRUE_SY=16300; TRUE_SZ=16500
TRUE_BX=10;    TRUE_BY=-50;   TRUE_BZ=120

"$PYTHON" - "$TMP/good.csv" <<'EOF'
import math, sys
s = (16400.0, 16300.0, 16500.0)
b = (10.0, -50.0, 120.0)
# Unit vectors: the six faces, then four tilted ones.
dirs = [(1,0,0), (-1,0,0), (0,1,0), (0,-1,0), (0,0,1), (0,0,-1),
        (0.9,0.3,0.3), (-0.2,0.95,-0.24), (0.3,-0.2,0.93), (-0.5,-0.5,-0.7)]
rows = []
for i, d in enumerate(dirs):
    n = math.sqrt(sum(v*v for v in d))
    a = [v/n for v in d]
    m = [a[k]*s[k] + b[k] for k in range(3)]
    rows.append("pose%d,%.4f,%.4f,%.4f" % (i, m[0], m[1], m[2]))
with open(sys.argv[1], "w") as fh:
    fh.write("label,x,y,z\n" + "\n".join(rows) + "\n")
EOF

run "$TMP/good.csv"
check_axis() { # axis truth tolerance
	_got=$(sed -n "s/^---   $1 *\([0-9.]*\).*/\1/p" "$out" | head -n 1)
	_ok=$("$PYTHON" -c "import sys;t=float('$2');g=float('$_got');print('yes' if abs(g-t)<=float('$3') else 'no')")
	say "$_ok" "$1 sensitivity recovered as $_got, wanted $2 within $3"
}
# TOLERANCE 0.2 LSB IN 16400, WHICH IS TWELVE PARTS PER MILLION, and it
# is that tight on purpose. The fixture is noiseless, so the only thing
# standing between the program and exact recovery is its own arithmetic.
# A looser bound is the comfortable choice and it is what let a wrong sign
# in the refinement step pass unnoticed on Monday 26 October 2026: it
# biased every axis 1.03 LSB low, which 20 LSB of slack happily accepted.
# The bench cannot resolve anything near this; the fixture can, and that is
# the point of having one.
check_axis X "$TRUE_SX" 0.2
check_axis Y "$TRUE_SY" 0.2
check_axis Z "$TRUE_SZ" 0.2

check_offset() { # axis truth tolerance
	_got=$(sed -n "s/^---   $1 *[0-9.]* *\([-+][0-9.]*\).*/\1/p" "$out" | head -n 1)
	_ok=$("$PYTHON" -c "import sys;t=float('$2');g=float('$_got');print('yes' if abs(g-t)<=float('$3') else 'no')")
	say "$_ok" "$1 offset recovered as $_got, wanted $2 within $3"
}
check_offset X "$TRUE_BX" 0.2
check_offset Y "$TRUE_BY" 0.2
check_offset Z "$TRUE_BZ" 0.2

said "it reports how many poses it used" "poses     10"
said "and the spread it flattened" "magnitude spread"

# THE NUMBERS ABOVE ARE THE WHOLE TEST, so prove the comparison can fail:
# feed poses built from different constants and watch the same assertion
# reject them. Without this, a check_axis that always said yes would look
# exactly like a passing suite.
"$PYTHON" - "$TMP/wrong.csv" <<'EOF'
import math, sys
s = (15000.0, 17000.0, 16000.0)   # deliberately not the fixture's
b = (400.0, 400.0, 400.0)
dirs = [(1,0,0), (-1,0,0), (0,1,0), (0,-1,0), (0,0,1), (0,0,-1),
        (0.9,0.3,0.3), (-0.2,0.95,-0.24)]
rows = []
for i, d in enumerate(dirs):
    n = math.sqrt(sum(v*v for v in d))
    a = [v/n for v in d]
    rows.append("pose%d,%.4f,%.4f,%.4f" % (i, *[a[k]*s[k]+b[k] for k in range(3)]))
with open(sys.argv[1], "w") as fh:
    fh.write("label,x,y,z\n" + "\n".join(rows) + "\n")
EOF
run "$TMP/wrong.csv"
_got=$(sed -n "s/^---   X *\([0-9.]*\).*/\1/p" "$out" | head -n 1)
_ok=$("$PYTHON" -c "print('yes' if abs(float('$_got')-16400)>20 else 'no')")
say "$_ok" "the sensitivity assertion rejects a fixture built from other constants"

# ------------------------------------------------ the refusals
#
# Each of these returns numbers that look ordinary if the program does not
# refuse, which is why they are refusals.

head -n 4 "$TMP/good.csv" >"$TMP/few.csv"
run "$TMP/few.csv"
say "$([ "$status" -ne 0 ] && echo yes || echo no)" "fewer than six poses is refused"
said "and the refusal says why six" "six unknowns"

# Every pose has Z positive: Z's offset is then free, and a solve still
# returns a number for it.
"$PYTHON" - "$TMP/onesided.csv" <<'EOF'
import math, sys
s = (16400.0, 16300.0, 16500.0); b = (10.0, -50.0, 120.0)
dirs = [(1,0,0.2), (-1,0,0.2), (0,1,0.2), (0,-1,0.2), (0,0,1), (0.5,0.5,0.6)]
rows=[]
for i,d in enumerate(dirs):
    n=math.sqrt(sum(v*v for v in d)); a=[v/n for v in d]
    rows.append("pose%d,%.4f,%.4f,%.4f"%(i,*[a[k]*s[k]+b[k] for k in range(3)]))
open(sys.argv[1],"w").write("label,x,y,z\n"+"\n".join(rows)+"\n")
EOF
run "$TMP/onesided.csv"
say "$([ "$status" -ne 0 ] && echo yes || echo no)" \
	"an axis that never points both ways is refused"
said "and the refusal names that axis" "no pose has Z pointing both ways"
said "and says what to do about it" "Turn the board over"

# Ten poses all within a degree of each other: enough rows, no information.
"$PYTHON" - "$TMP/degenerate.csv" <<'EOF'
import sys
rows=["pose%d,%.4f,%.4f,%.4f"%(i,100.0+i*0.5,50.0+i*0.3,16400.0+i*0.4) for i in range(10)]
open(sys.argv[1],"w").write("label,x,y,z\n"+"\n".join(rows)+"\n")
EOF
run "$TMP/degenerate.csv"
say "$([ "$status" -ne 0 ] && echo yes || echo no)" \
	"ten nearly identical poses are refused despite being ten"

# ------------------------------------------------ the held-out prediction
#
# The mode that makes the whole thing falsifiable: poses the fit never saw.
run "$TMP/good.csv" --holdout "$TMP/good.csv"
said "holdout mode reports a worst and an rms" "worst"
_rms=$(sed -n 's/.*rms \([0-9.]*\) mg.*/\1/p' "$out" | head -n 1)
_ok=$("$PYTHON" -c "print('yes' if float('$_rms')<1.0 else 'no')")
say "$_ok" "a correct fit predicts its own fixture to under 1 mg, got $_rms"

run "$TMP/good.csv" --holdout "$TMP/wrong.csv"
_rms=$(sed -n 's/.*rms \([0-9.]*\) mg.*/\1/p' "$out" | head -n 1)
_ok=$("$PYTHON" -c "print('yes' if float('$_rms')>10.0 else 'no')")
say "$_ok" "and misses poses from a different sensor badly, got $_rms mg"

# ------------------------------------------------ the units pass
run "$TMP/good.csv" --scale 0.000598205
said "the scale option converts to m/s2" "m/s2"
said "and reports offsets in mg, which is how the datasheet states them" "mg"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
