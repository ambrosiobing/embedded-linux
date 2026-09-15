# BlueST v1, as this gateway implements it

This is the specification the decoder was written against, and it is the
document to argue with when a number looks wrong. It describes what
`bluest.py` does; where it differs from the peripheral's firmware, the
firmware is right and this file is a bug.

**Status: written from the protocol description, not yet checked against a
captured frame.** Every scale factor below is a claim about a firmware
build. The section [Confirming this against a
trace](#confirming-this-against-a-trace) is the procedure that turns it
into a measurement, and until that has been done the project README says
so in its first paragraph.

## The shape of it

One service. Every characteristic under it encodes a **feature mask** in
the first 32 bits of its UUID, and a notification on that characteristic
carries a timestamp followed by the fields of every feature in the mask.

```
  service UUID     00000000-0001-11e2-9e96-0002a5d5c51b
                   ^^^^^^^^
                   mask, zero for the service itself

  characteristic   00e00000-0001-11e2-9e96-0002a5d5c51b
                   ^^^^^^^^
                   mask 0x00E00000 = acc | gyro | mag

  notification     34 12 | 0a 00 f6 ff 00 04 | 01 00 fe ff 03 00 | ...
                   ^^^^^   ^^^^^^^^^^^^^^^^^   ^^^^^^^^^^^^^^^^^
                   ts      acc x, y, z         gyro x, y, z
                   16-bit  three int16         three int16
                   LE      highest mask bit    next bit down
```

There is no length field, no type tag and no padding. The mask is the
entire description of the payload, which is efficient and has one sharp
consequence, below.

## The field table

Highest bit first, which is also the order the fields appear in a frame.

| Bit | Name | Type | Scale | Unit | Bytes |
|---|---|---|---|---|---|
| `0x00800000` | acc | 3 x int16 LE | 1.0 | mg | 6 |
| `0x00400000` | gyro | 3 x int16 LE | 0.1 | dps | 6 |
| `0x00200000` | mag | 3 x int16 LE | 1.0 | mGa | 6 |
| `0x00100000` | press | int32 LE | 0.01 | mbar | 4 |
| `0x00080000` | hum | int16 LE | 0.1 | percent | 2 |
| `0x00040000` | temp | int16 LE | 0.1 | degC | 2 |

Preceded in every frame by a 16-bit little-endian device timestamp, 2
bytes, which is not part of any mask bit.

So a frame for mask `0x00E00000` is 2 + 6 + 6 + 6 = 20 bytes, and
`bluest.expected_length()` computes exactly that.

## The consequence: an unknown bit is not skippable

Because fields are laid out back to back with no lengths, **the width of
every field has to be known to locate the ones after it**. A bit this table
does not recognise makes every field below it unlocatable.

The decoder therefore walks all 32 bits from high to low, not only the ones
it knows, and when it meets an unknown set bit it stops:

```python
>>> decode(0x00800100, bytes.fromhex("0000" "010002000300" "deadbeef"))
{'dev_ts': 0, 'acc': [1.0, 2.0, 3.0],
 'undecoded_mask': '00000100', 'undecoded': 'deadbeef'}
```

`acc` is above the unknown bit, so it was located correctly and is kept.
Everything below is handed back as bytes, and the record carries two fields
that say so. Those two fields are columns in the CSV and keys in the MQTT
payload, so an incomplete record is visibly incomplete wherever it lands.

The alternative, which is what a decoder written from the happy path does,
is to skip the bits it does not know and carry on. That produces a full
record of plausible numbers taken from the wrong offsets. There is nothing
in the data afterwards to distinguish it from a good one.

### Three things that are not errors

| Case | What happens | Why |
|---|---|---|
| Trailing bytes after the last known field | kept as `trailing`, record is otherwise normal | Every field was located correctly. A firmware may append something; the measurements stand |
| A mask bit with no field in this table | decoding stops there, record marked | Above is sound, below is not |
| A characteristic whose UUID is not BlueST | mask 0, ignored | Every peripheral also has generic access and device information services |

### One thing that is

A frame shorter than the mask promises raises `BluestError`. Here the
peripheral and this table disagree about a field that is supposedly known,
which is a fault rather than a gap, and the supervisor counts it and logs
the first one rather than writing a truncated record.

## The two timestamps

Every record carries both, and they are for different things.

| Field | Source | Wraps | Use it for |
|---|---|---|---|
| `dev_ts` | the peripheral's 16-bit counter | every 65536 ticks | Detecting a frame the radio dropped, and measuring the peripheral's own notification interval |
| `host_ts` | the Pi's wall clock when the notification reached user space | no | Correlating with anything else on the host, and reading by a human |

`host_ts` includes the connection interval, the time the frame waited in
the controller, the D-Bus round trip and the scheduler. It is the later of
the two by a variable amount, so the *interval* between consecutive
`host_ts` values is a noisier measurement of the notification rate than
the interval between `dev_ts` values. Use `dev_ts` for rate, `host_ts` for
time of day. The README's link measurement section says the same thing
with the numbers.

## Confirming this against a trace

The table above is a claim. This is how it becomes a measurement, and it
is the first job after the first successful connection.

1. Capture a session: `btmon -w docs/first-connect.btsnoop` while
   connecting and subscribing by hand with `bluetoothctl`.
2. Open it in Wireshark on the host and find an `ATT Handle Value
   Notification`. Its handle maps to a characteristic whose UUID is in the
   service discovery earlier in the same trace, and the first eight hex
   digits of that UUID are the mask.
3. Check the length first. A 20-byte payload with mask `0x00E00000`
   confirms the field widths without any assumption about scale.
4. Check one scale against a known physical value. With the board flat and
   still, `acc` z should read about 1000 mg and x and y about 0; `temp`
   should be room temperature. A factor of ten or a sign error is obvious
   at this step and invisible later.
5. Replace the synthetic frames in `tests/stwin-bluest-test.sh` with the
   captured bytes, and record in the journal which firmware build they came
   from.

Step 5 is the one that matters for anyone reading this repository later:
until it is done, the decoder tests prove the arithmetic of the decoder and
not the layout of the protocol, and the difference between those two is
exactly the difference between a tested program and a correct one.

## What is out of scope here

**BlueST v2**, used by the FP-SNS-DATALOG2 function pack, is a different
protocol with a different advertising layout, and streaming starts only
after a command is written to a command characteristic. Nothing in this
file applies to it. Supporting it means a second decoder module and a
command step in the supervisor, which is a stretch goal rather than a
variant.

**Pairing and bonding.** The sensor demo firmware does not request
encryption, so `Connect` succeeds on an unpaired device and no keys are
stored. If a firmware build does ask for security, the symptom is an ATT
error `Insufficient Authentication` in btmon, and the fix is one
`bluetoothctl` session, not a change here. BRINGUP.md has the steps.

---

Back to the [design](DESIGN.md) or the [project README](../README.md).
