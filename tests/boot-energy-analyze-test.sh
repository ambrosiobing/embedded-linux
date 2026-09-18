#!/bin/sh
#
# boot-energy-analyze-test.sh - Project 3's analysis, against traces whose
# answers are known before they are read.
#
# None of this needs a NanoPi, a PPK2, or Project 2's system. A boot
# recording is a CSV of current and three logic channels, and every number
# this project reports is a function of that file. Synthetic traces with
# arithmetic answers settle the three places an error would otherwise hide:
#
#   an edge detector that finds the wrong edge, and in particular reads the
#   console channel as rising when it falls;
#
#   an energy integral taken over the whole recording instead of over
#   [0, t_done], which would fold the idle tail into the boot;
#
#   a discard rule that drops a run without saying which rule fired, so an
#   average quietly changes and nobody can see why.
#
#   sh tests/boot-energy-analyze-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/projects/03-boot-energy/measure/analyze.py
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

close() {
	verdict=$(awk -v a="$2" -v b="$3" -v t="$4" \
		'BEGIN { d = a - b; if (d < 0) d = -d; print (d <= t) ? "yes" : "no" }')
	if [ "$verdict" = yes ]; then
		echo "ok       $1 ($2)"
		pass=$((pass + 1))
	else
		echo "FAILED   $1: $2 is not within $4 of $3"
		fail=$((fail + 1))
	fi
}

far() {
	verdict=$(awk -v a="$2" -v b="$3" -v t="$4" \
		'BEGIN { d = a - b; if (d < 0) d = -d; print (d > t) ? "yes" : "no" }')
	if [ "$verdict" = yes ]; then
		echo "ok       $1 ($2)"
		pass=$((pass + 1))
	else
		echo "FAILED   $1: $2 is within $4 of $3 and should not be"
		fail=$((fail + 1))
	fi
}

field() {
	"$PYTHON" -c "import json,sys; print(json.load(sys.stdin)['$1'])"
}

# ------------------------------------------------------------ generator

cat >"$WORK/make_trace.py" <<'PYTHON'
"""Write one synthetic boot recording.

    make_trace.py PATH N N_D1 N_D2FALL N_D0 I_UA

Sample indices, not seconds; -1 means the edge never happens. The current
is constant, so the energy over [0, N_D0] is exactly

    5.0 V * I_UA * 1e-6 * N_D0 * 1e-5

and the test can assert an arithmetic value rather than a fitted one.
"""
import csv
import sys

path = sys.argv[1]
n, n_d1, n_d2, n_d0, i_ua = (int(x) for x in sys.argv[2:7])

with open(path, "w", newline="") as handle:
    w = csv.writer(handle)
    w.writerow(["t_s", "i_ua", "d0", "d1", "d2"])
    for k in range(n):
        d1 = 1 if (n_d1 >= 0 and k >= n_d1) else 0
        d0 = 1 if (n_d0 >= 0 and k >= n_d0) else 0
        # The console line IDLES HIGH and falls at the first start bit.
        d2 = 0 if (n_d2 >= 0 and k >= n_d2) else 1
        w.writerow(["%.5f" % (k * 1e-5), "%.1f" % i_ua, d0, d1, d2])
PYTHON

trace() {
	"$PYTHON" "$WORK/make_trace.py" "$1" "$2" "$3" "$4" "$5" "$6"
}

# ------------------------------------- three good runs, two of them kept

# D1 at 1000 (0.010 s), console falls at 2000 (0.020 s), D0 at 4000
# (0.040 s), 300 mA throughout. Energy over [0, 4000] is
# 5.0 * 0.3 * 0.040 = 0.060 J exactly.
good=$WORK/good
mkdir -p "$good"
for i in 01 02 03; do trace "$good/boot-$i.csv" 6000 1000 2000 4000 300000; done
out=$("$PYTHON" "$SUT" "$good" --json)

check "every run in the directory is found" \
	"$(printf '%s' "$out" | field runs_found)" "3"
check "and the first one is not averaged in" \
	"$(printf '%s' "$out" | field runs_kept)" "2"

close "the U-Boot marker is read from the rising edge of D1" \
	"$(printf '%s' "$out" | field t_uboot_mean)" 0.010 0.0001
close "the first console byte is read from the FALLING edge of D2" \
	"$(printf '%s' "$out" | field t_console_mean)" 0.020 0.0001
close "boot complete is read from the rising edge of D0" \
	"$(printf '%s' "$out" | field t_done_mean)" 0.040 0.0001

# The number this project exists to produce, and the one with no
# independent source to check it against on the board.
close "energy is integrated over [0, t_done] and not over the recording" \
	"$(printf '%s' "$out" | field energy_j_mean)" 0.060 0.0005

# 6000 samples at 300 mA is 0.090 J, which is what the whole recording
# comes to including the idle tail after the marker.
#
# THIS WAS A STRING SEARCH FOR "0.09" AND IT PASSED WITH THE DEFECT IN
# PLACE, because the wrong integral evaluates to 0.08999999999999998 and
# that does not contain the substring. A check that depends on how a float
# happens to print is not checking the thing it names.
far "the idle tail after the marker is not part of the boot energy" \
	"$(printf '%s' "$out" | field energy_j_mean)" 0.090 0.005

check "the interval the energy covers is reported, not assumed" \
	"$(printf '%s' "$out" | field integration_interval)" "[0, t_done]"
close "peak current is reported, so the 1 A source limit is checked by data" \
	"$(printf '%s' "$out" | field peak_ma_mean)" 300 1

# ------------------------------------------- which rule fired, by name

text=$("$PYTHON" "$SUT" "$good")
contains "the discarded first run is named in the output" "$text" "boot-01.csv"
contains "and the rule that discarded it is stated" "$text" \
	"first run of the variant"

# ---------------------------------- one kept run has no spread to report

# Two files: the first is discarded by rule, so exactly one is kept.
# Reporting 0.0 here would read as "perfectly repeatable" for a sample of
# one, which is a claim the data cannot support.
single=$WORK/single
mkdir -p "$single"
for i in 01 02; do trace "$single/boot-$i.csv" 6000 1000 2000 4000 300000; done
out=$("$PYTHON" "$SUT" "$single" --json)
check "one kept run is counted as one" \
	"$(printf '%s' "$out" | field runs_kept)" "1"
check "and its standard deviation is absent, not zero" \
	"$(printf '%s' "$out" | field t_done_sd)" "None"

# Two kept identical runs, by contrast, really do have a spread of zero.
check "two identical kept runs do have a spread, and it is zero" \
	"$("$PYTHON" "$SUT" "$good" --json | field t_done_sd)" "0.0"

# ------------------------------------------------ a bootloader that did not start

# D1 at 55000 is 0.550 s, past the 0.5 s deadline in the first acceptance
# criterion. Discarded rather than averaged: the board did not boot, and
# folding it in reports a slow boot instead of a failed one.
late=$WORK/late
mkdir -p "$late"
trace "$late/boot-01.csv" 60000 1000 2000 4000 300000
trace "$late/boot-02.csv" 60000 55000 56000 58000 300000
out=$("$PYTHON" "$SUT" "$late")
check "a late D1 leaves nothing to average" \
	"$("$PYTHON" "$SUT" "$late" --json | field runs_kept)" "0"
contains "and the refusal gives the time it saw" "$out" "0.550"
contains "and the deadline it was measured against" "$out" "0.5 s deadline"
contains "and says the run is not a slow boot but a failed one" "$out" \
	"bootloader did not start"

# ------------------------------------------- each missing edge, named

for chan in d1 d0 d2; do
	d=$WORK/missing-$chan
	mkdir -p "$d"
	trace "$d/boot-01.csv" 6000 1000 2000 4000 300000
	case $chan in
	d1) trace "$d/boot-02.csv" 6000   -1 2000 4000 300000 ;;
	d0) trace "$d/boot-02.csv" 6000 1000 2000   -1 300000 ;;
	d2) trace "$d/boot-02.csv" 6000 1000   -1 4000 300000 ;;
	esac
	eval "out_$chan=\$(\"\$PYTHON\" \"\$SUT\" \"\$d\")"
done

contains "a missing U-Boot marker says U-Boot never started" "$out_d1" \
	"U-Boot never started"
contains "a missing complete marker says the job queue never emptied" \
	"$out_d0" "startup job queue never emptied"
contains "a silent console says the board printed nothing" "$out_d2" \
	"printed nothing"

# ------------------------------------------------- a file of the wrong shape

# genfromtxt(names=True) returns whatever header it finds, so a CSV with
# the right number of columns and the wrong names would otherwise be read
# as a measurement.
wrong=$WORK/wrong
mkdir -p "$wrong"
trace "$wrong/boot-01.csv" 6000 1000 2000 4000 300000
printf 't_s,i_ua,d0,d1,dX\n0.00000,300000.0,0,0,1\n' >"$wrong/boot-02.csv"
out=$("$PYTHON" "$SUT" "$wrong")
contains "a CSV with the wrong columns is refused" "$out" "missing column"
contains "and the missing column is named" "$out" "d2"

# ------------------------------------ nothing measured is not zero measured

empty=$WORK/emptyvariant
mkdir -p "$empty"
trace "$empty/boot-01.csv" 6000 1000 2000 4000 300000
out=$("$PYTHON" "$SUT" "$empty")
contains "a variant with no kept run says so rather than printing numbers" \
	"$out" "not measured"
lacks "and prints no energy figure at all" "$out" "0.06"

# ------------------------------------- the summary is a file, not only stdout

# docs/DESIGN.md's data flow says analyze.py produces
# results/<variant>/summary.md, and for a while it did not: it printed to
# stdout and the claim stood in the document unchallenged. measure/Makefile
# and docs/before-after.md both rely on the file existing.
written=$WORK/written
mkdir -p "$written"
for i in 01 02 03; do trace "$written/boot-$i.csv" 6000 1000 2000 4000 300000; done
out=$("$PYTHON" "$SUT" "$written")

if [ -f "$written/summary.md" ]; then
	ok_summary=yes
else
	ok_summary=no
fi
check "summary.md is written into the variant directory" "$ok_summary" "yes"
contains "and it names the variant it describes" \
	"$(cat "$written/summary.md")" "written"
contains "and the interval the energy covers is in the FILE, not just stdout" \
	"$(cat "$written/summary.md")" "[0, t_done]"
contains "and the discarded run is named in the file too" \
	"$(cat "$written/summary.md")" "first run of the variant"
contains "and the program says where it put it" "$out" "wrote"

# --json is for machines and must not leave a file behind as a side effect.
nojson=$WORK/nojson
mkdir -p "$nojson"
for i in 01 02; do trace "$nojson/boot-$i.csv" 6000 1000 2000 4000 300000; done
"$PYTHON" "$SUT" "$nojson" --json >/dev/null
if [ -f "$nojson/summary.md" ]; then
	check "--json writes no summary.md" "present" "absent"
else
	check "--json writes no summary.md" "absent" "absent"
fi

nosum=$WORK/nosum
mkdir -p "$nosum"
for i in 01 02; do trace "$nosum/boot-$i.csv" 6000 1000 2000 4000 300000; done
"$PYTHON" "$SUT" "$nosum" --no-summary >/dev/null
if [ -f "$nosum/summary.md" ]; then
	check "--no-summary suppresses the file" "present" "absent"
else
	check "--no-summary suppresses the file" "absent" "absent"
fi

# --------------------------------------------------------------- the plot

# matplotlib is NOT in CI, and this program is written so that its absence
# costs nothing until a plot is actually asked for. Both branches are
# asserted, and which one ran is printed, because a test that silently
# skips is a test that reports a pass it did not earn.
if "$PYTHON" -c "import matplotlib" >/dev/null 2>&1; then
	echo "note     matplotlib is present, so the drawing branch is exercised"
	rc=0
	"$PYTHON" "$SUT" "$written" --plot "$WORK/current.png" >/dev/null 2>&1 || rc=$?
	check "a plot is drawn when matplotlib is installed" "$rc" "0"
	if [ -s "$WORK/current.png" ]; then
		check "and the file it wrote is not empty" "nonempty" "nonempty"
	else
		check "and the file it wrote is not empty" "empty" "nonempty"
	fi
	check "and the PNG really is one" \
		"$(head -c 4 "$WORK/current.png" | od -An -c | tr -d ' ')" \
		"211PNG"
else
	echo "note     matplotlib is absent, so the refusal branch is exercised"
	rc=0
	out=$("$PYTHON" "$SUT" "$written" --plot "$WORK/current.png" 2>&1) || rc=$?
	check "a plot without matplotlib is refused, not skipped" "$rc" "1"
	contains "and the refusal names the missing package" "$out" "matplotlib"
fi

# --------------------------------------------------------------- errors

rc=0
out=$("$PYTHON" "$SUT" "$WORK/nosuchdir" 2>&1) || rc=$?
check "a directory with no runs is an error" "$rc" "1"
contains "and it says which directory" "$out" "nosuchdir"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
