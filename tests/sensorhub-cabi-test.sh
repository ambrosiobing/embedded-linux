#!/bin/sh
#
# sensorhub-cabi-test.sh - the C and the specification, compared byte for
# byte.
#
# proto.c is compiled into the firmware and into the daemon, so a mistake
# in it is a mistake at both ends of the wire at once, and the two would
# agree with each other while disagreeing with the document. That is the
# failure this test exists for, and it is why the comparison is against
# tests/sensorhub_reference.py, which was written from PROTOCOL.md rather
# than from proto.c.
#
# Everything here goes through ctypes: the C is built into a shared object
# and called with the same inputs as the reference. Nothing is transcribed,
# nothing is approximated, and the assertions are on exact bytes.
#
# This test needs a C compiler. It fails rather than skips without one,
# for the reason scripts/host-check.sh gives at length: a check that
# reports success when it did not run is worse than no check.
#
#   sh tests/sensorhub-cabi-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/meta-bench/recipes-bench/bench-sensorhub/files
PYTHON=${PYTHON:-python3}
CC=${CC:-cc}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

if ! command -v "$CC" >/dev/null 2>&1; then
	echo "FAILED   no C compiler ($CC): this test compares the C against"
	echo "         the specification, so without one it proves nothing."
	echo "         Run scripts/host-setup.sh, or: sudo apt-get install -y gcc"
	exit 1
fi

# The same warnings the recipe and CI use. A shared object rather than a
# program because ctypes needs to call individual functions, not a main.
"$CC" -shared -fPIC -O2 -Wall -Wextra -Werror \
	"$SRC/proto.c" -o "$WORK/libproto.so"
echo "ok       proto.c compiles clean with -Werror as a shared object"

cd "$ROOT/tests" || exit 1
LIBPROTO=$WORK/libproto.so
export LIBPROTO
exec "$PYTHON" - <<'PYTEST'
import ctypes
import os
import random
import sys

import sensorhub_reference as ref

lib = ctypes.CDLL(os.environ["LIBPROTO"])

passed = 1      # the compile above counted as one
failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        print("ok       %s" % label)
        passed += 1
    else:
        print("FAILED   %s:\n           C   %r\n           ref %r"
              % (label, got, want))
        failed += 1


# ------------------------------------------------------------ prototypes

lib.proto_crc16.restype = ctypes.c_uint16
lib.proto_crc16.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]

lib.proto_frame.restype = ctypes.c_int
lib.proto_frame.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t,
                            ctypes.c_uint8, ctypes.POINTER(ctypes.c_uint8),
                            ctypes.c_size_t]

FLOAT3 = ctypes.c_float * 3

lib.proto_encode_sample.restype = ctypes.c_int
lib.proto_encode_sample.argtypes = [ctypes.POINTER(ctypes.c_uint8),
                                    ctypes.c_size_t, ctypes.c_uint64,
                                    FLOAT3, FLOAT3, ctypes.c_float]

lib.proto_encode_hello.restype = ctypes.c_int
lib.proto_encode_hello.argtypes = [ctypes.POINTER(ctypes.c_uint8),
                                   ctypes.c_size_t, ctypes.c_uint32,
                                   ctypes.c_char_p,
                                   ctypes.POINTER(ctypes.c_char_p),
                                   ctypes.c_size_t]

lib.proto_encode_ack.restype = ctypes.c_int
lib.proto_encode_ack.argtypes = [ctypes.POINTER(ctypes.c_uint8),
                                 ctypes.c_size_t, ctypes.c_uint8,
                                 ctypes.c_uint8]

lib.proto_encode_set_rate.restype = ctypes.c_int
lib.proto_encode_set_rate.argtypes = [ctypes.POINTER(ctypes.c_uint8),
                                      ctypes.c_size_t, ctypes.c_uint32]

lib.proto_encode_calibrate.restype = ctypes.c_int
lib.proto_encode_calibrate.argtypes = [ctypes.POINTER(ctypes.c_uint8),
                                       ctypes.c_size_t]


class Parser(ctypes.Structure):
    _fields_ = [("buf", ctypes.c_uint8 * ref.MAX_FRAME),
                ("len", ctypes.c_size_t),
                ("frames_ok", ctypes.c_uint64),
                ("frames_bad", ctypes.c_uint64),
                ("resyncs", ctypes.c_uint64)]


CALLBACK = ctypes.CFUNCTYPE(None, ctypes.c_void_p, ctypes.c_uint8,
                            ctypes.c_uint8, ctypes.POINTER(ctypes.c_uint8),
                            ctypes.c_size_t)

lib.proto_parser_init.restype = None
lib.proto_parser_init.argtypes = [ctypes.POINTER(Parser)]

lib.proto_parser_push.restype = None
lib.proto_parser_push.argtypes = [ctypes.POINTER(Parser),
                                  ctypes.POINTER(ctypes.c_uint8),
                                  ctypes.c_size_t, CALLBACK, ctypes.c_void_p]


def buf(data):
    array = (ctypes.c_uint8 * max(len(data), 1))()
    for i, byte in enumerate(data):
        array[i] = byte
    return array


def out(size=1024):
    return (ctypes.c_uint8 * size)()


def taken(array, count):
    return bytes(array[:count])


# ----------------------------------------------------------------- CRC

check("the C agrees on the CCITT-FALSE check value",
      hex(lib.proto_crc16(buf(b"123456789"), 9)), "0x29b1")

random.seed(20260915)
mismatch = None
for _ in range(500):
    data = bytes(random.randrange(256) for _ in range(random.randrange(0, 600)))
    got = lib.proto_crc16(buf(data), len(data))
    if got != ref.crc16(data):
        mismatch = (data.hex(), got, ref.crc16(data))
        break
check("500 random buffers give the same CRC in both", mismatch, None)

# --------------------------------------------------------------- frames

for rate in (1, 23, 24, 100, 255, 256, 1000, 65535, 65536, 4000000000):
    dst = out()
    n = lib.proto_encode_set_rate(dst, len(dst), rate)
    if taken(dst, n) != ref.encode_set_rate(rate):
        check("SET_RATE payload for %d" % rate, taken(dst, n).hex(),
              ref.encode_set_rate(rate).hex())
        break
else:
    check("SET_RATE payloads match across ten integer widths", True, True)

dst = out()
n = lib.proto_encode_calibrate(dst, len(dst))
check("CALIBRATE payload", taken(dst, n), ref.encode_calibrate())

dst = out()
n = lib.proto_encode_ack(dst, len(dst), ref.SET_RATE, ref.ACK_BUSY)
check("ACK payload", taken(dst, n), ref.encode_ack(ref.SET_RATE, ref.ACK_BUSY))

names = (ctypes.c_char_p * 2)(b"lsm6dsv32x", b"lsm6dso16is")
dst = out()
n = lib.proto_encode_hello(dst, len(dst), 1, b"0.1.0", names, 2)
check("HELLO payload", taken(dst, n),
      ref.encode_hello(1, "0.1.0", ["lsm6dsv32x", "lsm6dso16is"]))

mismatch = None
for _ in range(200):
    t_us = random.randrange(0, 2 ** 48)
    accel = [random.uniform(-32.0, 32.0) for _ in range(3)]
    gyro = [random.uniform(-4000.0, 4000.0) for _ in range(3)]
    temp = random.uniform(-40.0, 85.0)
    dst = out()
    n = lib.proto_encode_sample(dst, len(dst), t_us, FLOAT3(*accel),
                                FLOAT3(*gyro), ctypes.c_float(temp))
    # The reference is handed the float32 values the C actually received,
    # so this compares encoders rather than the host's double to float
    # rounding.
    narrowed = [FLOAT3(*accel)[i] for i in range(3)]
    narrowed_g = [FLOAT3(*gyro)[i] for i in range(3)]
    want = ref.encode_sample(t_us, narrowed, narrowed_g,
                             ctypes.c_float(temp).value)
    if taken(dst, n) != want:
        mismatch = (t_us, taken(dst, n).hex(), want.hex())
        break
check("200 random samples encode to identical bytes", mismatch, None)

# The whole frame, not only the payload.
payload = ref.encode_set_rate(200)
dst = out()
n = lib.proto_frame(dst, len(dst), ref.SET_RATE, buf(payload), len(payload))
check("the framed SET_RATE matches the frozen vector",
      taken(dst, n).hex(), "a501100400a10018c86b09")

# ---------------------------------------------------------- the bounds

dst = out(4)
check("a buffer too small for the header is refused",
      lib.proto_frame(dst, 4, ref.SET_RATE, buf(payload), len(payload)), -1)

big = b"x" * (ref.MAX_PAYLOAD + 1)
dst = out(2048)
check("a payload over the maximum is refused",
      lib.proto_frame(dst, 2048, ref.SAMPLE, buf(big), len(big)), -1)

dst = out(8)
check("an encoder with no room says so rather than truncating",
      lib.proto_encode_sample(dst, 8, 1, FLOAT3(1, 2, 3), FLOAT3(4, 5, 6),
                              ctypes.c_float(7.0)), -1)

# ---------------------------------------------------------- the parser

def run_c_parser(stream):
    parser = Parser()
    lib.proto_parser_init(ctypes.byref(parser))
    seen = []

    def collect(_user, version, msg_type, payload_ptr, payload_len):
        seen.append((version, msg_type,
                     bytes(payload_ptr[i] for i in range(payload_len))))

    callback = CALLBACK(collect)
    data = buf(stream)
    lib.proto_parser_push(ctypes.byref(parser), data, len(stream), callback,
                          None)
    return seen, (parser.frames_ok, parser.frames_bad, parser.resyncs)


def run_ref_parser(stream):
    parser = ref.Parser()
    seen = parser.push(stream)
    return seen, (parser.frames_ok, parser.frames_bad, parser.resyncs)


good = ref.frame(ref.SET_RATE, ref.encode_set_rate(200))
sample = ref.frame(ref.SAMPLE, ref.encode_sample(1234, (0.1, -0.2, 9.81),
                                                 (1.0, 2.0, 3.0), 25.5))
corrupt = bytearray(good)
corrupt[-1] ^= 0xFF
absurd = bytearray(good)
absurd[3] = 0xFF
absurd[4] = 0xFF
truncated = good[:-1]
lost_byte = good[:4] + good[5:]

streams = {
    "one frame": good,
    "two frames": good + sample,
    "garbage then a frame": b"\x00\x01\x02\xa5junk" + good,
    "a corrupted CRC then a good frame": bytes(corrupt) + good,
    "an absurd length then a good frame": bytes(absurd) + good,
    "a truncated frame then a good one": truncated + good,
    "a byte lost mid frame": lost_byte + good + sample,
    "a payload full of SOF bytes": ref.frame(ref.SAMPLE, bytes([0xA5] * 32)),
    "nothing at all": b"",
}

for label, stream in streams.items():
    check("parser agrees: %s" % label, run_c_parser(stream),
          run_ref_parser(stream))

# Chunking must not change the answer: the same bytes delivered in
# different sized reads have to produce the same frames and counters.
stream = b"\x00\xa5" + good + bytes(corrupt) + sample + good
whole = run_c_parser(stream)
mismatch = None
for size in (1, 2, 3, 5, 7, 13, 64):
    parser = Parser()
    lib.proto_parser_init(ctypes.byref(parser))
    seen = []

    def collect(_user, version, msg_type, payload_ptr, payload_len):
        seen.append((version, msg_type,
                     bytes(payload_ptr[i] for i in range(payload_len))))

    callback = CALLBACK(collect)
    for start in range(0, len(stream), size):
        chunk = stream[start:start + size]
        lib.proto_parser_push(ctypes.byref(parser), buf(chunk), len(chunk),
                              callback, None)
    got = (seen, (parser.frames_ok, parser.frames_bad, parser.resyncs))
    if got != whole:
        mismatch = (size, got, whole)
        break
check("the chunk size does not change the result", mismatch, None)

# Randomised streams: frames, noise and corruption in arbitrary order. The
# two implementations have to agree on every frame and every counter.
mismatch = None
for trial in range(200):
    stream = bytearray()
    for _ in range(random.randrange(1, 8)):
        pick = random.random()
        if pick < 0.45:
            stream += ref.frame(ref.SET_RATE,
                                ref.encode_set_rate(random.randrange(1, 1001)))
        elif pick < 0.7:
            stream += sample
        elif pick < 0.85:
            broken = bytearray(good)
            broken[random.randrange(1, len(broken))] ^= 1 << random.randrange(8)
            stream += broken
        else:
            stream += bytes(random.randrange(256)
                            for _ in range(random.randrange(1, 20)))
    if run_c_parser(bytes(stream)) != run_ref_parser(bytes(stream)):
        mismatch = (trial, bytes(stream).hex())
        break
check("200 randomised streams parse identically", mismatch, None)

print("")
print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
PYTEST
