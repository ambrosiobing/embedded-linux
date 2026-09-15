"""BlueST v1 frame decoding, as a pure function.

The protocol in one paragraph. A BlueST peripheral exposes one service,
and every characteristic under it encodes a **feature mask** in the first
32 bits of its UUID; the rest of the UUID is a fixed base. A notification
on that characteristic carries a 16-bit little-endian device timestamp
followed by the fields of every feature named in the mask, laid out from
the highest bit to the lowest. There is no length field, no type tag and
no padding: the mask is the entire description of the payload.

That design has one consequence which decides the shape of this module.
**An unrecognised bit is not a field that can be skipped.** A field whose
width is unknown makes the offset of every field below it unknown too. A
decoder that keeps going produces numbers that look entirely reasonable
and are measurements of nothing. So this one stops at the first bit it
does not know, keeps everything above it, and marks the record as
incomplete; `tests/stwin-bluest-test.sh` holds it to that.

A frame shorter than its mask promises is a different thing and does
raise. There the peripheral and this table disagree about a field that is
supposedly known, which is a fault rather than a gap.

The scale factors below are the ones the sensor demo firmware uses. They
are a claim about a firmware build, not about the protocol, and the
project README says how to check each one against a frame from a real
btmon trace before any of it is believed.

SPDX-License-Identifier: MIT
"""

import struct

# Every BlueST characteristic UUID ends with this, and begins with eight
# hex digits of feature mask.
BASE = "-0001-11e2-9e96-0002a5d5c51b"
SERVICE_UUID = "00000000" + BASE

# (mask bit, name, struct format, scale, unit), highest bit first, which is
# also the order the fields appear in a frame.
FIELDS = (
    (0x00800000, "acc", "<hhh", 1.0, "mg"),
    (0x00400000, "gyro", "<hhh", 0.1, "dps"),
    (0x00200000, "mag", "<hhh", 1.0, "mGa"),
    (0x00100000, "press", "<i", 0.01, "mbar"),
    (0x00080000, "hum", "<h", 0.1, "percent"),
    (0x00040000, "temp", "<h", 0.1, "degC"),
)

KNOWN_MASK = 0
for _bit, _name, _fmt, _scale, _unit in FIELDS:
    KNOWN_MASK |= _bit

TIMESTAMP_FMT = "<H"
TIMESTAMP_SIZE = struct.calcsize(TIMESTAMP_FMT)


class BluestError(ValueError):
    """A frame that cannot be decoded without guessing."""


def mask_of(uuid):
    """The feature mask encoded in a characteristic UUID, or 0.

    Returns 0 rather than raising for a UUID that is not BlueST, because
    every peripheral also exposes the generic access and device information
    services and the caller iterates over all of them.
    """
    text = str(uuid).lower()
    if not text.endswith(BASE):
        return 0
    try:
        return int(text[:8], 16)
    except ValueError:
        return 0


def fields_of(mask):
    """The known fields in a mask, highest bit first."""
    return tuple(f for f in FIELDS if mask & f[0])


def expected_length(mask):
    """Bytes a frame for this mask should have, or None if it has unknowns."""
    if mask & ~KNOWN_MASK:
        return None
    size = TIMESTAMP_SIZE
    for _bit, _name, fmt, _scale, _unit in fields_of(mask):
        size += struct.calcsize(fmt)
    return size


def decode(mask, data):
    """Decode one notification payload.

    Returns a dict with the device timestamp and one entry per feature.
    Raises BluestError when the frame cannot be decoded without assuming
    something: an unknown bit above a known one, or a payload too short for
    the fields the mask promises.
    """
    if len(data) < TIMESTAMP_SIZE:
        raise BluestError(
            "frame of %d byte(s) has no room for the 16-bit timestamp"
            % len(data))

    out = {"dev_ts": struct.unpack_from(TIMESTAMP_FMT, data, 0)[0]}
    offset = TIMESTAMP_SIZE

    # Highest bit first, over every bit that is set, not only the known
    # ones. Walking the unknown bits as well is the whole point: it is what
    # lets an unknown bit be reported at the position where it breaks the
    # layout instead of silently shifting everything after it.
    for bit in range(31, -1, -1):
        flag = 1 << bit
        if not mask & flag:
            continue

        known = [f for f in FIELDS if f[0] == flag]
        if not known:
            # Stop here, and say so in the record. Everything decoded above
            # this bit was located correctly and is kept; everything below
            # it is at an offset that depends on a width nobody knows.
            #
            # Stopping rather than raising is deliberate. The dangerous
            # outcome is a number at the wrong offset, not a missing one,
            # and refusing the whole frame would throw away good
            # measurements because a firmware also reports something this
            # table has not met yet. The marker is what makes that safe: a
            # record carrying undecoded_mask is visibly incomplete in the
            # CSV and in the MQTT payload, so it cannot be mistaken for a
            # full one.
            out["undecoded_mask"] = "%08x" % (mask & ((flag << 1) - 1))
            out["undecoded"] = bytes(data[offset:]).hex()
            return out

        _bit, name, fmt, scale, _unit = known[0]
        size = struct.calcsize(fmt)
        if offset + size > len(data):
            raise BluestError(
                "mask %08x promises %s at offset %d (%d bytes) but the "
                "frame is %d bytes" % (mask, name, offset, size, len(data)))

        values = struct.unpack_from(fmt, data, offset)
        offset += size
        scaled = [round(v * scale, 3) for v in values]
        out[name] = scaled[0] if len(scaled) == 1 else scaled

    if offset != len(data):
        # Not an error. A firmware may append something this build does not
        # know about, and every field above was located correctly, so the
        # measurements are sound. Keeping the bytes is how the next version
        # of this table gets written.
        out["trailing"] = bytes(data[offset:]).hex()

    return out


def describe(mask):
    """A human-readable field list, for logs and for the CSV header."""
    names = [f[1] for f in fields_of(mask)]
    unknown = mask & ~KNOWN_MASK
    if unknown:
        names.append("unknown:%08x" % unknown)
    return "+".join(names) if names else "none"
