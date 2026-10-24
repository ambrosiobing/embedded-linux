# The supply and the return were the same net, Tuesday 21 October 2026

Seventeen readings taken with no instrument except the Raspberry Pi's own
GPIO lines. `supply-fault-2026-10-21.csv` carries them in the order they
were taken. This page says what each one could and could not establish,
because four of the seventeen were read as evidence for things they do not
support and those readings are marked as such below rather than removed.

## What was wrong

The module's `VCC` and its `GND` were connected to each other. Both went
to the breadboard's `+V` rail, and that rail was fed from header **pin 9**,
which is one of the Pi's eight ground pins. So the part's supply and its
return were one net at ground potential.

It had no rail at all. Not during any scan that day, not during any of the
five `-121` probe failures, and not when the SPI arm read `DEVID` as
`0x00` on Monday 19 October 2026 and Tuesday 20 October 2026.

Nothing was damaged by it. `VCC` tied to `GND` applies no voltage
anywhere, and the one interval where `VCC` sat at 3.3 V with `GND`
floating returned its current through the `SDO` strap's clamp diode at
the tens of microamps a 1.8 kOhm pull-up can supply.

## The method, which is the part worth keeping

There is no voltmeter on this bench. A GPIO configured as an input is a
one-bit voltmeter with a threshold near 1.3 V, and libgpiod v2's
`--bias` option makes it a usable one, because **one reading cannot tell
a driven line from a floating one and two opposite readings can**:

    gpioget --numeric --bias=pull-up   -c gpiochip0 <line>
    gpioget --numeric --bias=pull-down -c gpiochip0 <line>

| pull-up | pull-down | The line is |
|---|---|---|
| 0 | 0 | driven low by something |
| 1 | 1 | driven high by something |
| 1 | 0 | floating, nothing on it |

Every fact in the table below came from that pair, plus one rule:
**probe the module's own numbered row, never a breadboard power rail.**
A rail and a row are different conductors unless a lead joins them, and
reading the rail is what hid this fault for an hour. Reading 9 found the
rail at ground; reading 12 is the first time all day that 3.3 V was
confirmed at the pad the part actually uses.

The probe needs its own control, because with `--bias=pull-down` an
unseated lead reads 0 for the same reason a dead rail does. Reading 8 is
that control: the probe tied to a known ground pin, which must read 0
before any of the rest means anything. Readings 7 and 13 are the same
lead unplugged, and both read 1, which is what makes 8 worth having.

## What was established

| Link | How | Status |
|---|---|---|
| 3.3 V at the module's `VCC` pin | reading 12, in the module's own row, rail out of the path | present |
| ground at the module's `GND` pin | reading 15, same method | present |
| `CS` high, `SDO` low | header pins 17 and 6 read off the board | correct, I2C mode and address `0x53` |
| the two bus lines | readings 3 to 6 | at 3.3 V, no clamping, no short |
| the I2C controller | `i2cdetect -y 1` returns a full table | healthy |
| the part answering | `i2cget -y 1 0x53 0x00` once a second through a range of tilt and pressure | **never**, always `Error: Read failed` |

So every conductor outside the module conducts, and the part still does
not answer. What remains untested is the male pin against the plated hole
wall, six of them, and no instrument on this bench can reach inside the
module to test one. See `docs/HARDWARE.md` for why that connection is the
only one this part has ever worked through.

## Four readings that were over-read, and the corrections

**Readings 1, 2, 3, 4, 5 and 6 were taken as proof that three contacts
were open.** They are not. The reasoning was that a conducting contact
into an unpowered die would be clamped by the pin's ESD diode and read
low, so a high reading meant no contact. That holds only if the die's
3.0 V node is held at 0 V. It is not: with the `BL8555-30`'s input at
ground its pass device is off and **its output node floats**, so a
conducting contact lets the Pi's pull-up charge that node through the
clamp and read high as well. Both cases predict a 1. Those six readings
distinguish nothing about the contacts.

**Readings 16 and 17 were taken as proof that `INT1`'s contact is open**,
on the argument that a powered ADXL345 drives `INT1` low while no
interrupt is enabled. That was never read in the datasheet. If the pin is
high impedance until `INT_ENABLE` is written, and the part is in standby
by default, then a floating reading is what a perfectly good contact
produces. Unverified, so it establishes nothing either.

**Reading 10 is ambiguous by construction** and is in the file to show
why reading 11 was needed: under a pull-up, a live 3.3 V rail and a
floating one both read 1.

The pattern in all three is one thing: an inference stated in the same
voice as a measurement. The measurements are readings 8, 9, 11, 12, 14
and 15, and they are enough.

## What this costs the project

Criteria 2 through 7 cannot be re-measured until the part answers, and
the part will not answer reliably until its header is soldered. The
inventory has named the purchase since Tuesday 6 October 2026: a
soldering iron and one 8-pin 2.54 mm male header. It also records why
tilt and pressure is not a workaround worth repeating: on friction
contacts the part is reliably present in no condition at all, so a
silence is produced by the apparatus and by the hypothesis alike and no
number of repeats separates them.

Decision 129 chose to replace the wiring rather than retry it. That
remedy cannot be carried out on this bench, which reopens it rather than
satisfying it. Decision 135 has the account.
