#!/bin/sh
#
# sensorhub-proto-test.sh - the wire protocol, without a wire.
#
# Everything a frame does wrong on a real serial line happens here on
# purpose: a byte lost in the middle, a run of garbage before a frame, a
# length field that has been corrupted into nonsense, a byte inside a
# payload that happens to equal the start-of-frame marker, a frame split
# across three reads because that is how a tty delivers bytes.
#
# The subject is tests/sensorhub_reference.py, the independent second
# implementation. That is the honest description of what this file proves:
# that the specification is consistent and that a parser written from it
# recovers correctly. Whether the C in the layer agrees with it is a
# different question and a different test, sensorhub-cabi-test.sh, which
# needs a compiler.
#
# The golden vectors below were computed once and frozen. A change to the
# encoder that alters a single byte of them is a wire protocol change, and
# a wire protocol change that nobody noticed is exactly the failure this
# project exists to make impossible.
#
#   sh tests/sensorhub-proto-test.sh
#
# SPDX-License-Identifier: MIT

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PYTHON=${PYTHON:-python3}

if ! "$PYTHON" -c "import struct" 2>/dev/null; then
	echo "FAILED   no usable python3 interpreter"
	exit 1
fi

cd "$ROOT/tests" || exit 1
exec "$PYTHON" - <<'PYTEST'
import sys

import sensorhub_reference as proto

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


def raises(label, fn, exc):
    global passed, failed
    try:
        fn()
    except exc:
        print("ok       %s" % label)
        passed += 1
        return
    except Exception as error:      # noqa: BLE001 - the point is the type
        print("FAILED   %s: raised %r, wanted %s" % (label, error, exc.__name__))
        failed += 1
        return
    print("FAILED   %s: did not raise" % label)
    failed += 1


# ------------------------------------------------------------ the CRC
#
# CCITT-FALSE has a published check value, which is the whole reason for
# naming the variant rather than saying "CRC-16". Six different functions
# answer to that name and they disagree on every input.

check("CRC-16/CCITT-FALSE check value", hex(proto.crc16(b"123456789")), "0x29b1")
check("the CRC of nothing is the seed", hex(proto.crc16(b"")), "0xffff")
check("one bit changes the CRC",
      proto.crc16(b"123456789") != proto.crc16(b"123456780"), True)

# ---------------------------------------------------------- the frames
#
# Frozen bytes. These are the protocol.

check("SET_RATE 200 on the wire",
      proto.frame(proto.SET_RATE, proto.encode_set_rate(200)).hex(),
      "a501100400a10018c86b09")
check("CALIBRATE on the wire",
      proto.frame(proto.CALIBRATE, proto.encode_calibrate()).hex(),
      "a501110100a09454")
check("ACK(SET_RATE, OK) on the wire",
      proto.frame(proto.ACK, proto.encode_ack(proto.SET_RATE, proto.ACK_OK)).hex(),
      "a501030500a200100100365c")

header = proto.frame(proto.CALIBRATE, proto.encode_calibrate())[:5]
check("the header is SOF, version, type, length little endian",
      header.hex(), "a501110100")

# ---------------------------------------------------------- the payloads

sample = proto.encode_sample(1234, (0.1, -0.2, 9.81), (1.0, 2.0, 3.0), 25.5)
check("a sample payload is 45 bytes", len(sample), 45)
check("a sample frame is 52 bytes",
      len(proto.frame(proto.SAMPLE, sample)), 52)

decoded = proto.decode(sample)
check("the sample map has four keys", sorted(decoded), [0, 1, 2, 3])
check("the timestamp survives", decoded[0], 1234)
check("three axes of acceleration", len(decoded[1]), 3)
check("float32 rounding is the only loss",
      round(decoded[1][2], 4), 9.81)
check("the temperature survives exactly", decoded[3], 25.5)

# A wider timestamp is a longer sample, and a bandwidth budget has to use
# the long one. CBOR integers are variable length, so the frame grows as
# the hub stays up: 52 bytes while t_us fits in 16 bits, 54 while it fits
# in 32, and 58 from 71.6 minutes of uptime onwards. A link sized from a
# bench test is sized from the first of those three.
wide = proto.encode_sample(1234567890123, (0.1, -0.2, 9.81), (1.0, 2.0, 3.0), 25.5)
check("a 64-bit timestamp costs six more bytes", len(wide) - len(sample), 6)

hello = proto.encode_hello(1, "0.1.0", ["lsm6dsv32x", "lsm6dso16is"])
check("hello carries minor, firmware and sensors",
      proto.decode(hello),
      {0: 1, 1: "0.1.0", 2: ["lsm6dsv32x", "lsm6dso16is"]})

check("ack round trip", proto.decode(proto.encode_ack(0x10, proto.ACK_BUSY)),
      {0: 0x10, 1: 2})
check("calibrate carries an empty map", proto.decode(proto.encode_calibrate()), {})

# Preferred serialisation: the shortest head that fits. Two independent
# encoders only produce identical bytes if both obey this.
check("0 to 23 live in the head", proto.encode_set_rate(23).hex(), "a10017")
check("24 spills into one byte", proto.encode_set_rate(24).hex(), "a1001818")
check("256 spills into two", proto.encode_set_rate(256).hex(), "a100190100")
check("65536 spills into four", proto.encode_set_rate(65536).hex(),
      "a1001a00010000")

# The decoder refuses what the protocol does not use, so a test cannot
# accidentally bless a frame the daemon would reject.
raises("indefinite length is refused", lambda: proto.decode(b"\x9f\xff"),
       proto.CborError)
raises("trailing bytes are refused", lambda: proto.decode(b"\x00\x00"),
       proto.CborError)

# ----------------------------------------------------------- the bounds

check("a maximum payload is accepted",
      len(proto.frame(proto.SAMPLE, b"x" * proto.MAX_PAYLOAD)),
      proto.MAX_FRAME)
raises("one byte more is refused",
       lambda: proto.frame(proto.SAMPLE, b"x" * (proto.MAX_PAYLOAD + 1)),
       ValueError)

# ----------------------------------------------------------- the parser

good = proto.frame(proto.SET_RATE, proto.encode_set_rate(200))

parser = proto.Parser()
check("one frame in one push", parser.push(good),
      [(1, proto.SET_RATE, proto.encode_set_rate(200))])
check("and it counted one", parser.frames_ok, 1)

parser = proto.Parser()
check("two frames in one push", len(parser.push(good + good)), 2)

# A tty hands over whatever happens to be in the buffer. Every split has
# to work, so try every one of them rather than a representative sample.
for cut in range(1, len(good)):
    parser = proto.Parser()
    first = parser.push(good[:cut])
    second = parser.push(good[cut:])
    if first or len(second) != 1:
        check("split at byte %d" % cut, (len(first), len(second)), (0, 1))
        break
else:
    print("ok       a frame split at each of its %d byte boundaries" % (len(good) - 1))
    passed += 1

parser = proto.Parser()
check("a frame arriving one byte at a time",
      sum(len(parser.push(bytes([b]))) for b in good), 1)

# Garbage before a frame is discarded a byte at a time and counted.
parser = proto.Parser()
check("garbage first, frame still found", len(parser.push(b"\x00\x01\x02" + good)), 1)
check("and the garbage was counted", parser.resyncs, 3)

# A byte inside a payload that happens to be the start marker. The length
# field carries the parser over it, so this is only interesting when
# something else has already gone wrong; it is here because a parser that
# hunted for a SOF instead of trusting a checked length would fail it.
inside = proto.frame(proto.SAMPLE, bytes([0xA5] * 16))
parser = proto.Parser()
check("a SOF byte inside a payload is not a frame boundary",
      parser.push(inside), [(1, proto.SAMPLE, bytes([0xA5] * 16))])

# A corrupted CRC. The next good frame still has to arrive: a receiver
# that loses synchronisation permanently after one bad frame is worse than
# one that drops the frame.
bad = bytearray(good)
bad[-1] ^= 0xFF
parser = proto.Parser()
check("a bad CRC yields no frame", parser.push(bytes(bad)), [])
check("and is counted", parser.frames_bad, 1)
check("the next good frame still arrives", len(parser.push(good)), 1)

# A corrupted length field. The parser must not skip the length it was
# told, because that length is exactly what failed.
absurd = bytearray(good)
absurd[3] = 0xFF
absurd[4] = 0xFF
parser = proto.Parser()
check("an absurd length is rejected without waiting for it",
      parser.push(bytes(absurd) + good), [(1, proto.SET_RATE,
                                           proto.encode_set_rate(200))])
check("and counted as a bad frame", parser.frames_bad, 1)

# One byte lost in the middle of a frame, which is what a serial line
# actually does. The frame is lost; the stream is not.
lost = good[:4] + good[5:]
parser = proto.Parser()
frames = parser.push(lost + good + good)
check("a dropped byte costs one frame, not the stream", len(frames), 2)

# The version byte is passed through rather than judged. Refusing a
# mismatched major version is the daemon's decision, because the daemon is
# the thing with a log and a property to report it in.
odd = proto.frame(proto.SET_RATE, proto.encode_set_rate(200), version=2)
parser = proto.Parser()
check("a future version still parses", parser.push(odd)[0][0], 2)

print("")
print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
PYTEST
