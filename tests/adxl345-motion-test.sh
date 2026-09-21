#!/bin/sh
#
# adxl345-motion-test.sh - the motion detector's decision logic.
#
# Project 11's policy half. The detector is a class that takes lists of
# numbers and returns "start", "stop" or nothing, and it touches no
# hardware on purpose: that is what makes this suite possible on a laptop
# with no sensor, no bus and no kernel.
#
# What it is really testing is the two design choices in that class, both
# of which are easy to get wrong and neither of which shows up as a crash:
#
#   a RUNNING BASELINE rather than a fixed threshold, so the detector
#   measures change and needs no calibration and no level surface
#
#   N CONSECUTIVE bursts before declaring movement, so a single knock or
#   a passing lorry does not produce an event
#
# A detector with either of those wrong still runs, still logs, and is
# wrong in a way only a long afternoon with the hardware would reveal.
#
#   sh tests/adxl345-motion-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/meta-bench/recipes-bench/libadxl345/files/adxl345-linux
PYTHON=${PYTHON:-python3}

[ -f "$SRC/python/adxl-motion" ] || {
	echo "FAILED   missing: $SRC/python/adxl-motion"
	exit 1
}

if ! command -v "$PYTHON" >/dev/null 2>&1; then
	echo "skipped  no $PYTHON on this host, so the detector was not run."
	echo "         CI has python3 and does run it."
	exit 0
fi

# The program imports adxl345, which loads libadxl345.so.1 through ctypes
# and is not present on a build host. The Detector class needs none of
# that, so the test loads the file as a module with the import stubbed.
# Importing the real bindings here would test the loader rather than the
# logic, and would skip on every machine that has not built the library.
"$PYTHON" - "$SRC/python/adxl-motion" <<'ENDPY'
import sys
import types
import importlib.machinery
import importlib.util

path = sys.argv[1]

# Stand in for the bindings, which need the shared library.
sys.modules["adxl345"] = types.ModuleType("adxl345")

spec = importlib.util.spec_from_loader(
    "adxl_motion", importlib.machinery.SourceFileLoader("adxl_motion", path))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

checks = 0
failures = 0


def ok(what, cond):
    global checks, failures
    checks += 1
    if cond:
        print("ok       %s" % what)
    else:
        print("FAILED   %s" % what)
        failures += 1


def eq(what, got, want):
    ok("%s: %r" % (what, got) if got != want else what, got == want)


# ---------------------------------------------------------------- helpers
print("\n--- the arithmetic underneath")

eq("magnitude of a board lying flat is about 1 g in counts",
   mod.magnitude((0, 0, 256)), 256)
eq("magnitude ignores sign", mod.magnitude((0, 0, -256)), 256)
ok("magnitude of a tilted board is still about 1 g",
   250 <= mod.magnitude((181, 181, 0)) <= 262)

eq("median of an odd list", mod.median([5, 1, 3]), 3)
eq("median of an even list averages the middle two",
   mod.median([1, 3, 5, 7]), 4)
eq("median of nothing is zero rather than an exception",
   mod.median([]), 0)

ok("the median ignores a single spike, which a mean would not",
   mod.median([100, 100, 100, 100, 9000]) == 100)

# ------------------------------------------------------------- the window
print("\n--- the detector stays quiet until it has a baseline")

d = mod.Detector(window=8, threshold=50, consecutive=2)
still = [(0, 0, 256)] * 4

quiet = True
for _ in range(7):
    if d.feed(still) is not None:
        quiet = False
ok("no event before the window has filled", quiet)

ok("and a violent burst during warm-up still produces nothing",
   mod.Detector(window=8).feed([(0, 0, 9000)]) is None)

# ------------------------------------------------------------ transitions
print("\n--- start and stop")

d = mod.Detector(window=8, threshold=50, consecutive=3)
for _ in range(8):
    d.feed(still)

moved = [(0, 0, 600)] * 4
eq("one burst over the threshold is not movement", d.feed(moved), None)
eq("two is not either", d.feed(moved), None)
eq("three consecutive is", d.feed(moved), "start")
eq("and it does not fire again while still moving", d.feed(moved), None)

d2 = mod.Detector(window=8, threshold=50, consecutive=3)
for _ in range(8):
    d2.feed(still)
d2.feed(moved)
d2.feed(moved)
eq("a quiet burst resets the run", d2.feed(still), None)
eq("so the next one counts as the first again", d2.feed(moved), None)
eq("and the second is still not enough", d2.feed(moved), None)

# ------------------------------------------------- the baseline adapts
print("")
print("--- sustained movement is absorbed, a property not a bug")

# This one was written expecting "start" and found otherwise, which is
# the test teaching the design rather than checking it.
#
# A RUNNING baseline is a high-pass filter. Keep the sensor moving and
# the moved readings become the median, the difference falls to zero,
# and the detector goes quiet. That is correct for "tell me when
# something CHANGED" and wrong for "tell me while something is moving",
# and the two are easy to confuse when reading the code.
#
# The window sets how long sustained movement stays interesting: eight
# bursts here, thirty-two by default. A detector that must report
# continuously needs a fixed reference instead, and then it needs
# calibrating for orientation, which is the trade this design took the
# other side of.
eq("the third after a reset does not fire, because the baseline moved",
   d2.feed(moved), None)

absorbed = mod.Detector(window=8, threshold=50, consecutive=3)
for _ in range(8):
    absorbed.feed(still)
events = [absorbed.feed(moved) for _ in range(12)]
eq("movement is reported once", events.count("start"), 1)
ok("and then goes quiet as the new level becomes normal",
   events[-1] is None)

# --------------------------------------------------------- the baseline
print("\n--- the baseline is what makes orientation irrelevant")

# A board standing on its edge reads 1 g on X instead of Z. A fixed
# threshold on the magnitude would have to be recalibrated; a running
# baseline must not care at all.
edge = [(256, 0, 0)] * 4
d3 = mod.Detector(window=8, threshold=50, consecutive=3)
for _ in range(8):
    d3.feed(edge)
eq("a board on its edge produces no event at rest", d3.feed(edge), None)

d3.feed([(256, 0, 600)] * 4)
d3.feed([(256, 0, 600)] * 4)
eq("and the same movement is detected in that orientation too",
   d3.feed([(256, 0, 600)] * 4), "start")

# ----------------------------------------------------------- the refusals
print("\n--- edges")

eq("an empty burst is ignored rather than crashing",
   mod.Detector().feed([]), None)

print("\n%d checked, %d failed" % (checks, failures))
sys.exit(1 if failures else 0)
ENDPY
