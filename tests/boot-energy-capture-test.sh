#!/bin/sh
#
# boot-energy-capture-test.sh - the order of the four calls that make up
# Project 3's measurement, asserted with no PPK2 and no board.
#
# THE DEFECT THIS EXISTS FOR does not produce an error. If start_measuring
# comes after the supply is switched on, every recording begins somewhere
# inside the BROM, t=0 means nothing, and every phase time in the project
# is wrong by an unknown constant that is different in every run. The CSV
# looks fine. The plots look fine. The table is nonsense.
#
# Project 8 had the same shape of defect in rt-capture, where a thread
# priority set after the scan started raised the wrong thread, and it is
# tested here the same way: a stub PPK2 records the calls it receives, so
# the order is observable without hardware.
#
# The second thing asserted here is smaller and was found by writing the
# test: the obvious way to detect the boot-complete marker is to look at
# the last sample of each batch, and that drops the marker whenever the
# batch boundary falls after the edge.
#
#   sh tests/boot-energy-capture-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUT=$ROOT/projects/03-boot-energy/measure/ppk2_boot.py
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

before() {
	# "$3 appears before $4 in the newline-separated log $2"
	a=$(printf '%s\n' "$2" | grep -n "^$3\$" | head -n 1 | cut -d: -f1)
	b=$(printf '%s\n' "$2" | grep -n "^$4\$" | head -n 1 | cut -d: -f1)
	if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then
		echo "ok       $1"
		pass=$((pass + 1))
	else
		echo "FAILED   $1: '$3' at ${a:-absent}, '$4' at ${b:-absent}"
		printf '%s\n' "$2" | sed 's/^/           /'
		fail=$((fail + 1))
	fi
}

# ------------------------------------------------------------- the driver

cat >"$WORK/drive.py" <<'PYTHON'
"""Run record_boot() against a stub PPK2 and print what it was asked to do.

    drive.py SUT MODE

MODE "marker" puts the boot-complete edge in the MIDDLE of a batch, which
is where a last-sample-only check loses it. MODE "silent" never raises it.

The module is loaded by path because every program in this repository is
run as a file rather than installed, and because ppk2_boot.py imports
ppk2_api inside main() precisely so that this is possible on a machine
that has never seen a PPK2.
"""
import importlib.util
import sys

path, mode = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("ppk2_boot", path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class StubPPK2:
    def __init__(self, batches):
        self.log = []
        self.batches = list(batches)

    def get_modifiers(self):
        self.log.append("get_modifiers")

    def use_source_meter(self):
        self.log.append("use_source_meter")

    def set_source_voltage(self, mv):
        self.log.append("set_source_voltage %d" % mv)

    def toggle_DUT_power(self, state):
        self.log.append("power %s" % state)

    def start_measuring(self):
        self.log.append("start_measuring")

    def stop_measuring(self):
        self.log.append("stop_measuring")

    def get_data(self):
        return self.batches.pop(0) if self.batches else b""

    def get_samples(self, buf):
        return buf["i"], buf

    def digital_channels(self, raw):
        return raw["d0"], raw["d1"], raw["d2"]


def batch(i, d0, d1, d2):
    return {"i": i, "d0": d0, "d1": d1, "d2": d2}


if mode == "highfirst":
    # WHAT THE BOARD ACTUALLY DOES. D0 is high through BROM, SPL and
    # U-Boot because nothing owns PA6 yet, then the kernel's gpio-leds
    # driver applies default-state = "off" and drives it low, and only
    # then does the marker unit raise it. Observed on 20 September 2026
    # across a power cycle.
    #
    # A detector that asks "is D0 high" stops the capture in the first
    # batch, about half a second after power on.
    batches = [
        batch([100.0, 100.0, 100.0], [1, 1, 1], [0, 0, 0], [1, 1, 1]),
        batch([150.0, 150.0, 150.0], [1, 0, 0], [1, 1, 1], [0, 0, 0]),
        batch([200.0, 200.0, 200.0], [0, 1, 1], [1, 1, 1], [1, 1, 1]),
    ]
elif mode == "marker":
    batches = [
        batch([100.0, 100.0, 100.0], [0, 0, 0], [0, 1, 1], [1, 1, 1]),
        # The edge is in the MIDDLE. A check that reads only the last
        # sample of a batch sees a 0 here and keeps waiting.
        batch([200.0, 200.0, 200.0], [0, 1, 0], [1, 1, 1], [0, 0, 0]),
    ]
else:
    batches = [
        batch([100.0, 100.0, 100.0], [0, 0, 0], [0, 0, 0], [1, 1, 1]),
        batch([100.0, 100.0, 100.0], [0, 0, 0], [0, 0, 0], [1, 1, 1]),
    ]

ppk = StubPPK2(batches)

# A clock that advances a tenth of a second per read, and a sleep that does
# nothing, so proving a timeout costs no wall time.
ticks = iter(range(0, 10000))


def clock():
    return next(ticks) * 0.1


currents, digital, seen = mod.record_boot(
    ppk, timeout_s=2.0, tail_s=0.2, clock=clock, sleep=lambda _s: None)

n = mod.write_csv(sys.argv[3], currents, digital)

print("\n".join(ppk.log))
print("MARKER %s" % ("yes" if seen else "no"))
print("ROWS %d" % n)
PYTHON

# ------------------------------------------- the order is the measurement

out=$("$PYTHON" "$WORK/drive.py" "$SUT" marker "$WORK/out.csv")

before "the supply is switched off before anything is recorded" \
	"$out" "power OFF" "start_measuring"
before "recording starts BEFORE the supply comes on, or t=0 is meaningless" \
	"$out" "start_measuring" "power ON"
before "the meter is in source mode before it is asked to switch the DUT" \
	"$out" "use_source_meter" "power OFF"
contains "and it is set to 5.0 V" "$out" "set_source_voltage 5000"
before "the supply is switched off again at the end" \
	"$out" "power ON" "stop_measuring"

# ------------------------- a level is not an event, and D0 starts high

# The capture must not end because D0 happened to be high when it began.
# Three batches: high throughout the first, falling in the second when
# the kernel claims the pin, rising in the third when the marker unit
# writes it. Only that last transition is the boot completing.
high=$("$PYTHON" "$WORK/drive.py" "$SUT" highfirst "$WORK/high.csv")
contains "a capture that opens with D0 high still finds the real edge" 	"$high" "MARKER yes"
contains "and records every sample rather than stopping in batch one" 	"$high" "ROWS 9"

# ------------------------------- the marker is looked for in the whole batch

contains "an edge in the middle of a batch is still the boot completing" \
	"$out" "MARKER yes"

silent=$("$PYTHON" "$WORK/drive.py" "$SUT" silent "$WORK/silent.csv")
contains "a run where the marker never rises says so" "$silent" "MARKER no"

# ------------------------------------------------------------- the CSV

contains "every sample of both batches is written" "$out" "ROWS 6"
check "the header is the one analyze.py checks by name" \
	"$(head -n 1 "$WORK/out.csv")" "t_s,i_ua,d0,d1,d2"
check "the first row is at t=0" \
	"$(sed -n '2p' "$WORK/out.csv" | cut -d, -f1)" "0.00000"
check "and the second is one sample period later, not one second" \
	"$(sed -n '3p' "$WORK/out.csv" | cut -d, -f1)" "0.00001"

# The two streams can differ by a sample at a batch boundary, and zipping
# them silently would hide a larger mismatch.
mismatch=$("$PYTHON" - "$SUT" "$WORK/short.csv" <<'PYTHON'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ppk2_boot", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod.write_csv(sys.argv[2], [1.0, 2.0, 3.0, 4.0], [(0, 0, 1), (0, 0, 1)]))
PYTHON
)
check "a short digital stream truncates rather than inventing samples" \
	"$mismatch" "2"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
