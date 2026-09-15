#!/bin/sh
#
# stwin-bluest-test.sh - the BlueST decoder, without a radio.
#
# The decoder is a pure function from (feature mask, bytes) to a
# dictionary, which is the one part of Project 17 that can be proven
# correct rather than merely exercised. Everything else in that project
# needs a peripheral, a controller and a D-Bus daemon; this needs a
# frame and an expected answer.
#
# The frames here are synthetic and are labelled as such. Replacing them
# with bytes copied out of a btmon trace is the first job after the first
# successful connection, and until that happens these tests prove the
# arithmetic of the decoder rather than the layout of the protocol. The
# project README says the same thing in the same words, because it is the
# difference between a tested decoder and a correct one.
#
#   sh tests/stwin-bluest-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/meta-bench/recipes-bench/bench-stwin/files
PYTHON=${PYTHON:-python3}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/run.py" <<'PYTHON'
import importlib.util
import os
import sys

src = sys.argv[1]
spec = importlib.util.spec_from_file_location(
    "bluest", os.path.join(src, "bluest.py"))
bluest = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bluest)

passed = 0
failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        print("ok       %s" % label)
        passed += 1
    else:
        print("FAILED   %s: wanted %r, got %r" % (label, want, got))
        failed += 1


def raises(label, fn, fragment):
    global passed, failed
    try:
        fn()
    except bluest.BluestError as error:
        if fragment in str(error):
            print("ok       %s" % label)
            passed += 1
        else:
            print("FAILED   %s: %r not in %r" % (label, fragment, str(error)))
            failed += 1
    except Exception as error:
        print("FAILED   %s: wrong exception %r" % (label, error))
        failed += 1
    else:
        print("FAILED   %s: no exception" % label)
        failed += 1


# ------------------------------------------------ the mask lives in the UUID

UUID_ACC_GYRO_MAG = "00e00000" + bluest.BASE
check("mask read from a characteristic UUID",
      bluest.mask_of(UUID_ACC_GYRO_MAG), 0x00E00000)
check("an uppercase UUID decodes the same",
      bluest.mask_of(UUID_ACC_GYRO_MAG.upper()), 0x00E00000)
check("a non-BlueST UUID is 0, not an error",
      bluest.mask_of("00002a19-0000-1000-8000-00805f9b34fb"), 0)
check("the service UUID is mask 0",
      bluest.mask_of(bluest.SERVICE_UUID), 0)

# ----------------------------------------------------- an inertial frame
#
# timestamp 0x1234, then acc, gyro and mag, three int16 each, little
# endian, highest mask bit first.

FRAME = bytes.fromhex("3412" "0a00f6ff0004" "0100feff0300" "6400c8ff2c01")
rec = bluest.decode(0x00E00000, FRAME)

check("the device timestamp is little endian", rec["dev_ts"], 0x1234)
check("accelerometer in mg", rec["acc"], [10.0, -10.0, 1024.0])
check("gyroscope scaled by 0.1", rec["gyro"], [0.1, -0.2, 0.3])
check("magnetometer in mGa", rec["mag"], [100.0, -56.0, 300.0])
check("nothing was left over", "trailing" in rec, False)
check("and nothing was skipped", "undecoded_mask" in rec, False)
check("the expected length matches the frame",
      bluest.expected_length(0x00E00000), len(FRAME))

# ------------------------------------------------- an environmental frame
#
# press is the only int32 in the table, and it is the field that catches a
# decoder which assumes every value is 16 bits.

ENV = bytes.fromhex("0100" "a0860100" "5302" "1a01")
env = bluest.decode(0x001C0000, ENV)
check("pressure is a 32-bit field", env["press"], 1000.0)
check("humidity is a scalar, not a list", env["hum"], 59.5)
check("temperature scaled by 0.1", env["temp"], 28.2)
check("environmental length", bluest.expected_length(0x001C0000), len(ENV))

# A single feature is still a list for a vector and a scalar for a scalar.
one = bluest.decode(0x00800000, bytes.fromhex("0000" "0100" "0200" "0300"))
check("one vector feature", one["acc"], [1.0, 2.0, 3.0])

# --------------------------------------------- an unknown bit stops the walk
#
# Bit 0x00000100 is not in the table. It sits below acc, so acc was located
# correctly and is kept; everything after it is at an offset that depends
# on a width nobody knows, so it is handed back as bytes.

MIXED = bytes.fromhex("0000" "0100" "0200" "0300" "deadbeef")
mixed = bluest.decode(0x00800100, MIXED)
check("fields above the unknown bit survive", mixed["acc"], [1.0, 2.0, 3.0])
check("the record is marked incomplete",
      mixed["undecoded_mask"], "00000100")
check("and the undecoded bytes are kept", mixed["undecoded"], "deadbeef")

# An unknown bit above everything known means nothing can be decoded at all,
# and the record says so rather than being empty and plausible.
high = bluest.decode(0x01800000, bytes.fromhex("0000" "0100020003000000"))
check("an unknown high bit decodes no features", "acc" in high, False)
check("and is reported", high["undecoded_mask"], "01800000")
check("expected_length refuses a mask with unknown bits",
      bluest.expected_length(0x00800100), None)

# ------------------------------------------------------- frames that are wrong

raises("a frame too short for its fields",
       lambda: bluest.decode(0x00E00000, FRAME[:-2]),
       "the frame is")
raises("a frame with no room for the timestamp",
       lambda: bluest.decode(0x00800000, b"\x01"),
       "no room for the 16-bit timestamp")

# A longer frame is not an error: a firmware may append something. The
# fields above were located correctly, so the measurements stand and the
# extra bytes are kept for whoever writes the next version of the table.
extra = bluest.decode(0x00800000, bytes.fromhex("0000" "010002000300" "abcd"))
check("trailing bytes are kept, not rejected", extra["trailing"], "abcd")
check("and the fields before them are intact", extra["acc"], [1.0, 2.0, 3.0])

# ------------------------------------------------------------- description

check("describe names the features in mask order",
      bluest.describe(0x00E00000), "acc+gyro+mag")
check("and names what it does not know",
      bluest.describe(0x00800100), "acc+unknown:00000100")
check("an empty mask is not an empty string",
      bluest.describe(0), "none")

print()
print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
PYTHON

"$PYTHON" "$WORK/run.py" "$SRC"
