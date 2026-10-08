# Hardware sources for project 11

This project uses the same part as project 5, the DFRobot SEN0032 carrying
an Analog Devices ADXL345, so the sourcing is kept in one place rather
than in two that can drift apart:

**[projects/05-iio-adxl345/docs/hardware.md](../../05-iio-adxl345/docs/hardware.md)**

That page separates facts about the module, which come from DFRobot's
schematic and are read, from facts about the die, which come from the
ADXL345 datasheet and are not. It also carries the two module level
hazards that cost this bench an evening: the supply that must come
straight from the host's 3V3 pin rather than through a breadboard rail,
and the unsoldered header whose every connection is a friction contact.

## What is different here

Project 11 reaches the part from **userspace**, through `i2c-dev` and
`I2C_RDWR`, where project 5 writes an in-kernel IIO driver for it. The
hardware is identical and the wiring is identical. What changes is which
of the die level facts matter:

| Fact | Matters to project 5 | Matters to project 11 |
|---|---|---|
| the address straps, `CS` and `SDO` | yes, the overlay names the address | yes, the library opens that address |
| the identification register and its value | yes, the driver probes it | yes, the library should refuse a part that is not this one |
| output data rates and g ranges | yes, they become IIO attributes | yes, they become the library's API |
| the digital pin absolute maximum | yes | yes, equally |

So nothing in the sourcing is project specific, which is why there is one
page. **If the ADXL345 datasheet is ever read, both projects gain from the
same reading**, and the rows to fill are listed there.

## The bus is pulled up by the host, and this project names a different host

Thursday 8 October 2026, and the only hardware fact that is this project's
rather than project 5's.

The I2C pull-ups are not on the module and not on the host's internal GPIO
pull-up either. Header pins 3 and 5 are the one pair a Raspberry Pi fits
resistors on: 1.8 kohm to 3V3. The working, the sources and what it
corrects are in **[project 5's hardware page](../../05-iio-adxl345/docs/hardware.md#the-pull-up-is-not-missing-because-the-pi-fits-it)**,
kept there for the same reason the rest of the sourcing is.

What belongs here is the host difference, because this project specifies a
**Raspberry Pi 4** and every reading so far was taken on a **Raspberry Pi
3 Model B+**, hostname `eplepi`:

| Host | Fitted on GPIO2 and GPIO3 | Basis |
|---|---|---|
| Raspberry Pi 3 Model B+ | `R23` and `R24`, 1K8 1% 1005 to 3V3 | the board's own reduced schematic, Rev V1.0, 19 March 2018, read |
| Raspberry Pi 4 Model B | 1k8, 1% 63mW M1005 | `secondary`: a Raspberry Pi forum thread and pinout.xyz, both consistent with the 3 B+ parts. The Pi 4 reduced schematic does not show them, and that absence is not evidence either way |

So the two hosts agree, and the number this project would quote is the
same whichever board it runs on. The distinction is kept because it is the
kind that has gone wrong here before: a figure that was true where it was
read, carried somewhere it was never checked.

## The chapter's own subject is not the sensor

Worth remembering when reading the hardware notes: this project exists to
compare a packaged userspace library against an in-kernel driver, and to
work through library hygiene and packaging, soname and hidden visibility,
pkg-config, bindings, fake-bus tests, udev groups, a hardened unit. The
sensor is the vehicle. A reader looking for the interesting part of
project 11 should start at
[docs/kernel-or-userspace.md](kernel-or-userspace.md), not here.
