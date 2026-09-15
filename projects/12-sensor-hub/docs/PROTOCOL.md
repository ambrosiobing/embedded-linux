# The sensor hub wire protocol, version 1.1

This document is the specification. `proto.c` and `proto.h` implement it,
`tests/sensorhub_reference.py` implements it a second time in Python, and
`tests/sensorhub-cabi-test.sh` compares the two byte for byte. When any of
the three disagree, this file is right and the code is wrong.

Writing it first was not ceremony. The frame layout below has a field
order, an endianness, a CRC variant and a resynchronisation rule, and every
one of those is a decision that becomes impossible to change once two
implementations exist.

## The frame

```
   0        1        2        3        4        5              5+n
   +--------+--------+--------+--------+--------+-- ... --+--------+--------+
   |  SOF   |  ver   |  type  |   length (LE)   | payload |   CRC-16 (LE)   |
   |  0xA5  |   1    |        |   0 .. 512      |  CBOR   |                 |
   +--------+--------+--------+--------+--------+-- ... --+--------+--------+
            |<---------------- covered by the CRC ------->|
```

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 1 | SOF | Always `0xA5`. Not covered by the CRC |
| 1 | 1 | version | Protocol **major**. Currently 1 |
| 2 | 1 | type | See the catalogue below |
| 3 | 2 | length | Payload bytes, little endian, at most 512 |
| 5 | n | payload | A CBOR item, always a map |
| 5+n | 2 | CRC-16 | Little endian, over bytes 1 to 4+n |

**The SOF is outside the CRC on purpose.** It is the resynchronisation
marker, and a receiver that has just found one has not yet decided whether
this is a frame. It cannot be part of the evidence that it is.

**Little endian for both multi-byte fields**, because both ends are little
endian and a conversion nobody needs is a conversion somebody will get
wrong. Network byte order would be defensible and is not free.

### The CRC

CRC-16/CCITT-FALSE. Polynomial `0x1021`, initial value `0xFFFF`, input not
reflected, output not reflected, no final xor.

Its published check value, the CRC of the nine bytes `123456789`, is
`0x29B1`. Both implementations assert that constant, and any third one
should before it is trusted: at least six different functions are called
"CRC-16" and they agree on nothing.

### Bounds and resynchronisation

A receiver must:

1. discard bytes until it sees `0xA5`
2. wait for five bytes, then read the length
3. reject the frame if the length is above 512
4. wait for the whole frame, then check the CRC
5. on **any** failure, discard the leading `0xA5` and go back to step 1

Step 5 is the rule with a consequence. After a bad CRC or an absurd length,
the receiver steps forward exactly one byte. It must **not** skip the
length the broken header claimed, because that length is part of what just
failed its own integrity check. A receiver that trusts it ends up
permanently one frame out of step after a single dropped byte, which looks
like a dead link rather than like a lost frame.

## The message catalogue

Payloads are CBOR maps with integer keys. Integer keys rather than strings
keep a sample at 45 bytes instead of about 90, and the names live here
where they can be read rather than being repeated in every frame.

### Hub to Pi

| Type | Name | Payload |
|---|---|---|
| `0x01` | HELLO | `{0: proto_minor, 1: fw_version, 2: [sensor names]}` |
| `0x02` | SAMPLE | `{0: t_us, 1: [ax, ay, az], 2: [gx, gy, gz], 3: temp_c}` |
| `0x03` | ACK | `{0: acked_type, 1: status}` |

### Pi to hub

| Type | Name | Payload |
|---|---|---|
| `0x10` | SET_RATE | `{0: rate_hz}` |
| `0x11` | CALIBRATE | `{}` |

Types below `0x10` travel from the hub, `0x10` and above towards it. That
split is a convention rather than a rule the code enforces, and it makes a
trace readable without a table.

### Field types

| Field | CBOR type | Units |
|---|---|---|
| `t_us` | unsigned integer | microseconds since the hub started |
| `ax` .. `gz` | float32 (major 7, argument 26) | g, and degrees per second |
| `temp_c` | float32 | degrees Celsius |
| `rate_hz` | unsigned integer | 1 to 1000 |
| `proto_minor` | unsigned integer | see versioning |
| `fw_version` | text string | free form, for example `0.1.0` |
| `acked_type` | unsigned integer | the type being acknowledged |
| `status` | unsigned integer | 0 ok, 1 out of range, 2 busy, 3 unknown type |

float32 rather than float64 for the sensor values: the part delivers 16 bit
raw counts, so a double would carry eleven digits of precision that do not
exist, at twice the bytes on a wire with a budget.

### Preferred serialisation

Every integer is encoded in the shortest head that fits it, which RFC 8949
calls the preferred serialisation. This is not an aesthetic rule. It is
what makes two independent encoders produce identical bytes, and therefore
what makes `tests/sensorhub-cabi-test.sh` able to compare them at all.

| Value | Encoding |
|---|---|
| 0 to 23 | in the head byte |
| 24 to 255 | head plus 1 byte |
| 256 to 65535 | head plus 2 bytes |
| up to 2^32-1 | head plus 4 bytes |
| beyond | head plus 8 bytes |

Indefinite length items, tags and every other CBOR feature are **not** part
of this protocol. The Python reference decoder rejects them, so that a test
cannot bless a frame the daemon would refuse.

## Golden vectors

Frozen. A change to any of these bytes is a protocol change.

| Frame | Bytes |
|---|---|
| SET_RATE 200 | `a5 01 10 04 00 a1 00 18 c8 6b 09` |
| CALIBRATE | `a5 01 11 01 00 a0 94 54` |
| ACK(SET_RATE, ok) | `a5 01 03 05 00 a2 00 10 01 00 36 5c` |

A SAMPLE with `t_us = 1234` is a 45 byte payload and a 52 byte frame.

## The bandwidth budget

A sample frame is not a fixed size, because CBOR integers are not. The
timestamp grows as the hub stays up:

| Uptime | `t_us` | Frame | At 100 Hz | At 1 kHz |
|---|---|---|---|---|
| first 65 ms | below 2^16 | 52 bytes | 5.2 kB/s | 52 kB/s |
| to 71.6 minutes | below 2^32 | 54 bytes | 5.4 kB/s | 54 kB/s |
| after that, for 584000 years | below 2^64 | 58 bytes | 5.8 kB/s | 58 kB/s |

At 8N1 a byte costs ten bits, so the steady state at 1 kHz is 58 kB/s,
which is 580 kbaud. **115200 baud cannot carry 1 kHz**; 921600 can with
room to spare, which is why the link runs at the higher rate even though
100 Hz would fit comfortably in the lower one.

The row that matters is the third, and it arrives 71.6 minutes after the
hub powers on, which is long enough that a bench test never sees it. Size
a link from the first minute of uptime and it will be 7 percent short
during the second hour.

## Versioning

Two boundaries, two rules, and they are not the same rule.

### The wire

The **major** version is the byte at offset 1. It changes only when the
frame layout changes: a field moving, a length growing, the CRC variant
changing. A receiver that sees a major version it does not implement must
refuse the whole stream, say so once, and expose the number it saw.
`sensorhubd` does exactly that, and puts the number in the
`ProtocolVersion` property so that a client can see the mismatch without
reading a log.

The **minor** version is announced in HELLO and never appears in a header.
It goes up for additions: a new message type, a new key in an existing map.
Both directions ignore what they do not recognise, so a new key is
invisible to an old receiver and an unknown type is not counted as an
error. Counting it would make a compatible firmware update look like a
fault.

| Change | Major | Minor |
|---|---|---|
| A new message type | no | yes |
| A new key in an existing map | no | yes |
| A key's type changing | **yes** | no |
| The header growing a field | **yes** | no |
| A different CRC | **yes** | no |
| Units changing, g to m/s2 | **yes** | no |

The last row is the one people get wrong. Nothing about the encoding
changes when the units do, so every check passes and every number is wrong
by 9.81. A semantic change is a breaking change.

### The bus

The interface name carries its major version: `org.bench.SensorHub1`.

| Change | Compatible |
|---|---|
| Adding a method | yes |
| Adding a property | yes |
| Adding a signal | yes |
| Adding an argument to an existing method | **no** |
| Changing a signature | **no** |
| Removing anything | **no** |

A breaking change becomes `org.bench.SensorHub2`, served from the same
process, on the same object path, beside the old one for as long as clients
need it. That is the whole reason the name ends in a digit, and it is why
`tests/sensorhub-policy-test.sh` asserts that it does.

## Change log

| Version | Date | Change |
|---|---|---|
| 1.1 | 15 September 2026 | The ACK status codes gained names: 0 ok, 1 out of range, 2 busy, 3 unknown type. Previously only 0 was defined, so this is an addition and the major version stays |
| 1.0 | 15 September 2026 | First definition: the frame, the five message types, CCITT-FALSE |

---

Back to the [project README](../README.md), or on to the
[design](DESIGN.md).
