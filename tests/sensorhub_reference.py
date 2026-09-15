"""An independent second implementation of the sensor hub protocol.

This exists so that the C in the layer has something to be wrong against.
A test that drives one implementation can only show that it is
self-consistent; a test that compares two implementations written from the
specification can show that the specification was understood the same way
twice. That is the whole argument for this file, and it is why it is
written from PROTOCOL.md rather than transcribed from proto.c.

It is also the decoder the tests use. The daemon decodes with libcbor, the
firmware encodes by hand, and neither of those can be run on a laptop, so
the tests need a third party that can be. The decoder here covers exactly
the subset the protocol uses and refuses everything else, which is the
right amount of CBOR for a test: a decoder that accepted more than the
protocol allows would pass frames the real daemon would reject.

    tests/sensorhub-proto-test.sh    exercises this against the spec
    tests/sensorhub-cabi-test.sh     compares it against the C, byte for byte

SPDX-License-Identifier: MIT
"""

import struct

SOF = 0xA5
VERSION = 1
MINOR = 1

HEADER_LEN = 5
CRC_LEN = 2
MAX_PAYLOAD = 512
MAX_FRAME = HEADER_LEN + MAX_PAYLOAD + CRC_LEN

HELLO = 0x01
SAMPLE = 0x02
ACK = 0x03
SET_RATE = 0x10
CALIBRATE = 0x11

ACK_OK = 0
ACK_RANGE = 1
ACK_BUSY = 2
ACK_UNKNOWN = 3


def crc16(data):
    """CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflection, no xor."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def frame(msg_type, payload, version=VERSION, sof=SOF, crc=None):
    """Wrap a payload. The overrides exist so tests can build bad frames."""
    if len(payload) > MAX_PAYLOAD:
        raise ValueError("payload of %d exceeds %d" % (len(payload), MAX_PAYLOAD))
    head = bytes([sof, version, msg_type,
                  len(payload) & 0xFF, (len(payload) >> 8) & 0xFF])
    body = head + payload
    # Over bytes 1 to 4+n: the SOF is the resync marker and is not covered.
    value = crc16(body[1:]) if crc is None else crc
    return body + bytes([value & 0xFF, (value >> 8) & 0xFF])


# ----------------------------------------------------------------- CBOR

def _head(major, arg):
    """The shortest form RFC 8949 calls preferred serialisation."""
    if arg < 24:
        return bytes([(major << 5) | arg])
    if arg <= 0xFF:
        return bytes([(major << 5) | 24, arg])
    if arg <= 0xFFFF:
        return bytes([(major << 5) | 25]) + struct.pack(">H", arg)
    if arg <= 0xFFFFFFFF:
        return bytes([(major << 5) | 26]) + struct.pack(">I", arg)
    return bytes([(major << 5) | 27]) + struct.pack(">Q", arg)


def _uint(value):
    return _head(0, value)


def _text(value):
    raw = value.encode("utf-8")
    return _head(3, len(raw)) + raw


def _float(value):
    return bytes([(7 << 5) | 26]) + struct.pack(">f", value)


def encode_sample(t_us, accel, gyro, temp_c):
    out = _head(5, 4)
    out += _uint(0) + _uint(t_us)
    out += _uint(1) + _head(4, 3) + b"".join(_float(v) for v in accel)
    out += _uint(2) + _head(4, 3) + b"".join(_float(v) for v in gyro)
    out += _uint(3) + _float(temp_c)
    return out


def encode_hello(proto_minor, fw_version, sensors):
    out = _head(5, 3)
    out += _uint(0) + _uint(proto_minor)
    out += _uint(1) + _text(fw_version)
    out += _uint(2) + _head(4, len(sensors)) + b"".join(
        _text(name) for name in sensors)
    return out


def encode_ack(acked_type, status):
    return _head(5, 2) + _uint(0) + _uint(acked_type) + _uint(1) + _uint(status)


def encode_set_rate(rate_hz):
    return _head(5, 1) + _uint(0) + _uint(rate_hz)


def encode_calibrate():
    return _head(5, 0)


class CborError(Exception):
    pass


def decode(data):
    """Decode one CBOR item. Raises if anything is left over."""
    value, rest = _decode_item(memoryview(data))
    if rest:
        raise CborError("%d trailing bytes" % len(rest))
    return value


def _decode_item(view):
    if not view:
        raise CborError("truncated")
    initial = view[0]
    major, minor = initial >> 5, initial & 0x1F
    view = view[1:]

    if minor < 24:
        arg = minor
    elif minor == 24:
        arg, view = view[0], view[1:]
    elif minor == 25:
        arg, view = struct.unpack(">H", view[:2])[0], view[2:]
    elif minor == 26:
        arg, view = struct.unpack(">I", view[:4])[0], view[4:]
    elif minor == 27:
        arg, view = struct.unpack(">Q", view[:8])[0], view[8:]
    else:
        # 28 to 30 are reserved and 31 is the indefinite length form.
        # The protocol uses neither, so accepting them here would let a
        # test pass a frame the daemon would reject.
        raise CborError("unsupported additional information %d" % minor)

    if major == 0:
        return arg, view
    if major == 3:
        raw, view = view[:arg], view[arg:]
        return bytes(raw).decode("utf-8"), view
    if major == 4:
        items = []
        for _ in range(arg):
            item, view = _decode_item(view)
            items.append(item)
        return items, view
    if major == 5:
        pairs = {}
        for _ in range(arg):
            key, view = _decode_item(view)
            value, view = _decode_item(view)
            pairs[key] = value
        return pairs, view
    if major == 7 and minor == 26:
        # The four bytes were already consumed above as the argument: in
        # CBOR a float is a head whose argument is the value, not a head
        # followed by a value. Reading them a second time here is the bug
        # this comment exists to stop being rewritten, and it presents as
        # "unsupported major type 6" several items later, which points at
        # everything except the float.
        return struct.unpack(">f", struct.pack(">I", arg))[0], view
    raise CborError("unsupported major type %d" % major)


# --------------------------------------------------------------- parser

class Parser(object):
    """The same state machine as proto_parser in proto.c.

    Kept deliberately close to the C, because the point of the pair is that
    a disagreement is a bug rather than a difference of style. The one
    thing to look at twice is the resynchronisation rule: after any
    failure the parser steps forward by exactly one byte and starts
    hunting again. Skipping the length the broken header claimed would
    mean trusting a header that has just failed its integrity check.
    """

    def __init__(self):
        self.buf = bytearray()
        self.frames_ok = 0
        self.frames_bad = 0
        self.resyncs = 0

    def push(self, data):
        """Feed bytes, return the list of (version, type, payload) frames."""
        out = []
        self.buf.extend(data)
        while self.buf:
            if self.buf[0] != SOF:
                self.resyncs += 1
                del self.buf[0]
                continue
            if len(self.buf) < HEADER_LEN:
                break
            payload_len = self.buf[3] | (self.buf[4] << 8)
            if payload_len > MAX_PAYLOAD:
                self.frames_bad += 1
                del self.buf[0]
                continue
            total = HEADER_LEN + payload_len + CRC_LEN
            if len(self.buf) < total:
                break
            want = self.buf[total - 2] | (self.buf[total - 1] << 8)
            got = crc16(bytes(self.buf[1:HEADER_LEN + payload_len]))
            if want == got:
                self.frames_ok += 1
                out.append((self.buf[1], self.buf[2],
                            bytes(self.buf[HEADER_LEN:HEADER_LEN + payload_len])))
                del self.buf[:total]
                continue
            self.frames_bad += 1
            del self.buf[0]
        return out
