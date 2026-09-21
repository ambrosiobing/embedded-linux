#!/bin/sh
#
# adxl345-registers-test.sh - the library's register map against the
# datasheet, from two independent sources.
#
# THE GAP THIS CLOSES, WHICH THE OTHER TWO SUITES CANNOT
#
# tests/fake_platform.c uses the same register numbers as src/adxl.c. So
# the whole fake-bus suite passes whether those numbers are right or not:
# change POWER_CTL from 0x2d to 0x2c and the library writes to 0x2c, the
# fake stores at 0x2c, the assertion reads back 0x2c and agrees. The part
# would never leave standby and 78 assertions would stay green.
#
# Internal consistency is not correctness. This suite parses the constants
# out of src/adxl.c and compares them against tests/adxl345_datasheet.py,
# which was transcribed from the datasheet and not from the code.
#
# When the two disagree, one is wrong and a person has to decide which.
# That is the point: a single source cannot be checked against anything.
#
#   sh tests/adxl345-registers-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/meta-bench/recipes-bench/libadxl345/files/adxl345-linux
PYTHON=${PYTHON:-python3}

[ -f "$SRC/src/adxl.c" ] || {
	echo "FAILED   missing: $SRC/src/adxl.c"
	exit 1
}
[ -f "$ROOT/tests/adxl345_datasheet.py" ] || {
	echo "FAILED   missing: tests/adxl345_datasheet.py"
	exit 1
}

if ! command -v "$PYTHON" >/dev/null 2>&1; then
	echo "skipped  no $PYTHON on this host, so the register map was not"
	echo "         compared. CI has python3 and does compare it."
	exit 0
fi

"$PYTHON" - "$SRC/src/adxl.c" "$ROOT/tests" <<'ENDPY'
import re
import sys

source_path, tests_dir = sys.argv[1], sys.argv[2]
sys.path.insert(0, tests_dir)
import adxl345_datasheet as ds

text = open(source_path, encoding="utf-8").read()

checks = 0
failures = 0


def ok(what, cond, detail=""):
    global checks, failures
    checks += 1
    if cond:
        print("ok       %s" % what)
    else:
        print("FAILED   %s" % what)
        if detail:
            print("         %s" % detail)
        failures += 1


def define(name):
    """The value of a #define in the C, or None."""
    m = re.search(r"^#define\s+%s\s+(\S+)" % re.escape(name), text,
                  re.MULTILINE)
    if not m:
        return None
    try:
        return int(m.group(1), 0)
    except ValueError:
        return None


print("--- register addresses the library must name")
for name in sorted(ds.REQUIRED, key=lambda n: ds.REGISTERS[n]):
    want = ds.REGISTERS[name]
    got = define("REG_" + name)
    if got is None:
        # DATAX0 is the only one the library reads a burst from; the
        # others it touches by name. A missing one is reported rather
        # than skipped, because "the code does not define it" is a
        # finding.
        ok("REG_%s is defined" % name, False,
           "the library needs this one and does not name it; the "
           "datasheet has it at 0x%02x" % want)
        continue
    ok("REG_%s is 0x%02x" % (name, want), got == want,
       "code says 0x%02x, datasheet says 0x%02x" % (got, want))

# What the library deliberately does not use, said out loud. A check
# that stays silent about what it did not look at teaches you to trust it
# further than it has earned.
unused = [n for n in ds.REGISTERS if n not in ds.REQUIRED]
for name in sorted(unused, key=lambda n: ds.REGISTERS[n]):
    print("note     REG_%s (0x%02x) is in the map and unused by design"
          % (name, ds.REGISTERS[name]))

print("")
print("--- fixed values")
ok("DEVID reads 0x%02x" % ds.DEVID_VALUE,
   define("DEVID_VALUE") == ds.DEVID_VALUE,
   "a wrong DEVID makes adxl_open reject the real part, or accept a "
   "different one")
ok("POWER_CTL measure bit is 0x%02x" % ds.POWER_CTL_MEASURE,
   define("POWER_CTL_MEASURE") == ds.POWER_CTL_MEASURE)
ok("DATA_FORMAT FULL_RES bit is 0x%02x" % ds.DATA_FORMAT_FULL_RES,
   define("DATA_FORMAT_FULL_RES") == ds.DATA_FORMAT_FULL_RES)
ok("the watermark interrupt bit is 0x%02x" % ds.INT_WATERMARK,
   define("INT_WATERMARK") == ds.INT_WATERMARK)
ok("FIFO stream mode is 0x%02x" % ds.FIFO_CTL_STREAM,
   define("FIFO_CTL_STREAM") == ds.FIFO_CTL_STREAM)
ok("FIFO bypass is 0x%02x" % ds.FIFO_CTL_BYPASS,
   define("FIFO_CTL_BYPASS") == ds.FIFO_CTL_BYPASS)
ok("the FIFO entry count mask is 0x%02x" % ds.FIFO_STATUS_ENTRIES,
   define("FIFO_STATUS_ENTRIES") == ds.FIFO_STATUS_ENTRIES,
   "six bits, even though the FIFO is 32 deep")
ok("a FIFO entry is %d bytes" % ds.ENTRY_BYTES,
   define("ENTRY_BYTES") == ds.ENTRY_BYTES,
   "three axes of little-endian int16")

print("")
print("--- the output data rate ladder")
# The codes are not a function of the frequency, so every one is a
# separate opportunity for a transcription error.
body = text[text.find("static int rate_code"):]
body = body[:body.find("static int range_bits")]
pairs = re.findall(r"case\s+(\d+):\s*\n\s*return\s+(0x[0-9a-fA-F]+);", body)
found = {int(hz): int(code, 16) for hz, code in pairs}

ok("the code offers the same nine rates as the datasheet",
   sorted(found) == sorted(ds.RATE_CODES),
   "code: %s\n         datasheet: %s"
   % (sorted(found), sorted(ds.RATE_CODES)))

for hz in sorted(ds.RATE_CODES):
    want = ds.RATE_CODES[hz]
    got = found.get(hz)
    ok("%d Hz is code 0x%02x" % (hz, want), got == want,
       "code says %s" % ("0x%02x" % got if got is not None else "nothing"))

print("")
print("--- the measurement ranges")
body = text[text.find("static int range_bits"):]
body = body[:body.find("static int write_reg")]
pairs = re.findall(r"case\s+(\d+):\s*\n\s*return\s+(0x[0-9a-fA-F]+);", body)
found = {int(g): int(bits, 16) for g, bits in pairs}

ok("the code offers the same four ranges as the datasheet",
   sorted(found) == sorted(ds.RANGE_BITS))
for g in sorted(ds.RANGE_BITS):
    ok("%d g is bits 0x%02x" % (g, ds.RANGE_BITS[g]),
       found.get(g) == ds.RANGE_BITS[g])

print("")
print("--- the two strap addresses")
for addr in ds.ADDRESSES:
    ok("0x%02x is accepted by adxl_open" % addr,
       ("0x%02x" % addr) in text or ("0x%02X" % addr) in text,
       "the argument check must name both, or one board cannot be opened")

print("")
print("--- the FIFO depth the header promises")
header = open(source_path.replace("src/adxl.c", "include/adxl.h"),
              encoding="utf-8").read()
m = re.search(r"#define\s+ADXL_FIFO_DEPTH\s+(\d+)", header)
ok("ADXL_FIFO_DEPTH is %d" % ds.FIFO_DEPTH,
   m is not None and int(m.group(1)) == ds.FIFO_DEPTH,
   "a caller sizes its array from this, so too large is a buffer the "
   "library can never fill and too small silently loses samples")

print("")
print("%d checked, %d failed" % (checks, failures))
sys.exit(1 if failures else 0)
ENDPY
