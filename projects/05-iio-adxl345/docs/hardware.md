# Hardware sources for projects 5 and 11

Both projects use the same part, so this page serves both: project 5
writes an in-kernel IIO driver for it, project 11 a packaged userspace
library.

[docs/DESIGN.md](DESIGN.md) already carries the wiring as built, the pad
order, both address and mode straps, and the reasoning about the 3V3
supply. **This page does not repeat that.** It answers where each claim
comes from, and separates two things that are easy to run together: facts
about **the module**, which come from DFRobot's schematic, and facts about
**the die**, which come from the ADXL345 datasheet.

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## Two parts, two documents, often confused

| Layer | Part | Primary source | Status |
|---|---|---|---|
| the module | DFRobot SEN0032 | DFRobot's own schematic | read, Tuesday 6 October 2026 |
| the die | Analog Devices ADXL345 | ADXL345 Rev G datasheet | **`NOT READ`** |

**Nearly every surprise on this bench has been at the module layer**, not
the die layer, which is why the schematic was worth reading first. The
module facts are in [docs/HARDWARE.md](../../../docs/HARDWARE.md) in full;
the short version is that the silkscreen pad order and the schematic's own
`J1` numbering disagree, there is a `BL8555-30` regulator between the
header and the die that makes two vendor pages give different supply
ranges and both be right, and there is not a single resistor on the board,
so a two-wire bus built from it has only the host's internal pull-ups.

## The missing pull-up now has a number, and the number predicts a failure

> **Corrected on Thursday 8 October 2026.** The arithmetic in this section
> is right and its premise is wrong for this bus. Header pins 3 and 5 are
> not bare GPIOs: the Raspberry Pi fits 1.8 kohm pull-ups on them. Read the
> next section before acting on anything below, and in particular before
> buying the resistors this section asks for.

Added Wednesday 7 October 2026, because this is what reading a document
is for.

The paragraph above says the module carries no resistors, so a two-wire
bus built from it has only whatever the host provides internally. That was
true, useful and entirely qualitative. **Source: Raspberry Pi 4 Model B
Datasheet, release 1.1, 12 March 2024, Table 3, page 8.** The internal
pull-up and pull-down on a BCM2711 GPIO is specified as 18 kohm minimum,
**47 kohm typical**, 73 kohm maximum.

An I2C bus is normally pulled up with something between about 1.8 kohm and
10 kohm. So the internal pull-up is roughly five to twenty five times
weaker than the usual value, and the rising edge is correspondingly slow,
because the line is a capacitor charged through that resistor. What
follows is a prediction rather than a worry:

- a bus built this way **works** at a low clock rate with short wires and
  one device
- it **degrades** as the clock rate goes up, as the wires get longer, or
  as more devices add capacitance
- when it fails it fails on the **rising** edge, so the symptom is a stuck
  or stretched high level and reads that are wrong rather than absent

That is a testable statement. It can be checked by halving the clock and
seeing whether a flaky bus becomes reliable, which costs one line in a
device tree overlay and no hardware at all.

**Wednesday 7 October 2026, later the same day: the prediction became
arithmetic.** Sensirion's SHT4x datasheet, version 6.4 of November 2023,
page 9, bounds the bus capacitance for a given pull-up and rise time:

```
   C_b  <  t_rise / (0.8473 * R_p)
```

Put 47 kohm into it and fast mode's 300 ns rise time comes out at
**7.5 pF** of permitted bus capacitance; standard mode's 1000 ns comes out
at **25 pF**. A few centimetres of jumper wire and two devices is fifty to
a hundred.

So the statement this page could make in the morning, that a bus on
internal pull-ups is "somewhere between five and twenty five times
weaker", can now be made properly: **such a bus fails the condition by
more than an order of magnitude at any standard I2C speed with any
realistic wiring.** The criterion is Sensirion's, for its own part, and
the ordinary I2C rise-time condition besides; the working is in
[project 10's hardware page](../../10-iio-iks4a1/docs/hardware.md).

**Which makes the remedy concrete rather than hopeful.** Two resistors of
about 4.7 kohm from `SDA` and `SCL` to 3V3 would put the bus inside the
condition with room to spare. There are none on this bench, and that is
now a specific shopping item rather than a vague wish.

**And the honest caveat, which matters more than the number.** That figure
is the **Pi 4's**, from the BCM2711 datasheet. The Raspberry Pi 3 Model B+
product brief states no GPIO electrical characteristics whatsoever, and
this project's wiring has been exercised on a Nucleo as well. So:

| Host | Internal pull-up value | Source |
|---|---|---|
| Raspberry Pi 4 | 18 k / 47 k / 73 k ohm | `datasheet`, Table 3 page 8 |
| Raspberry Pi 3B+ | unknown | the brief does not say; `NOT READ` elsewhere |
| NUCLEO-H7A3ZI-Q | unknown here | the STM32H7A3 datasheet, `NOT READ` |

Writing "47 kohm" into a Pi 3 or an STM32 context without that line would
be the same move this bench keeps catching: a number that was true where
it was read, carried somewhere it was never checked.

## The pull-up is not missing, because the Pi fits it

Thursday 8 October 2026. The section above evaluates a criterion with the
wrong resistor in it, and the error is not in the arithmetic.

**Header pins 3 and 5 are not bare GPIOs.** They are the only pair on the
40-pin header with pull-up resistors fitted on the Raspberry Pi itself.
**Source: Raspberry Pi 3 Model B+ reduced schematic, Rev V1.0, drawn by
Roger Thornton, dated Monday 19 March 2018, sheet 1 of 1, the GPIO
EXPANSION block.** `R23` and `R24`, both **1K8, 1%, 1005**, run from `3V3`
to the `GPIO3` and `GPIO2` nets, and the junction dots sit on those two
nets. `ID_SD` and `ID_SC` cross the same wires with no dots, so those are
not the pulled lines, which is the reading that has to be checked rather
than assumed because the four nets are drawn adjacent.

So the resistance that matters for this project's bus is **1.8 kohm**, not
the 47 kohm of a bare BCM GPIO. Same formula, same page of the same
Sensirion datasheet:

```
   fast mode, 400 kHz, t_rise 300 ns:
      C_b  <  300e-9 / (0.8473 * 1800)   =  197 pF

   standard mode, 100 kHz, t_rise 1000 ns:
      C_b  <  1000e-9 / (0.8473 * 1800)  =  656 pF
```

A few centimetres of jumper and two devices is fifty to a hundred
picofarads. **The bus passes the condition at both speeds, with room to
spare.** If the BCM internal pull-up is also enabled it sits in parallel,
giving 1.73 kohm and 204 pF, which is slightly more headroom rather than
less, so it cannot rescue the failing conclusion either.

**What survives from the section above, and what does not.**

| Claim | Status |
|---|---|
| the SEN0032 module carries no resistors of its own | stands |
| the Sensirion inequality and its working | stands, and is reproduced above |
| 47 kohm typical for a bare BCM2711 GPIO | stands, and is about a different pin |
| a bus on **internal** pull-ups fails by more than an order of magnitude | stands, for buses that are actually on internal pull-ups |
| **this** bus is on internal pull-ups | **wrong**, and it is the premise everything else hung from |
| two 4.7 kohm resistors are a shopping item **for this bus** | **wrong**, nothing needs buying for pins 3 and 5 |
| 4.7 kohm for any **other** I2C pair on the header | stands, and only GPIO2 and GPIO3 are fitted |

**The Pi 4, which project 11 names, separately.** Its reduced schematic
does **not** show these resistors: the only three 1K8 parts on that sheet
are `R21` on `AUDIO_L`, `R24` on `AUDIO_R` and `R52` between `1V8` and
`3V3`. That is an absence in a reduced drawing and not evidence that the
board lacks them, so it is not cited here as one. The Pi 4 is fitted, on
two sources rather than on that PDF: the Raspberry Pi forum thread
[Pi 4 I2C pull-up resistors](https://forums.raspberrypi.com/viewtopic.php?t=342415),
where the value is given as 1k8, 1%, 63mW, M1005, the same specification as
the Pi 3 B+ parts above, and where it is stated that they appear on no
published schematic; and [pinout.xyz](https://pinout.xyz/pinout/i2c), which
gives the fixed 1.8 kohm to 3V3 and says only GPIO2 and GPIO3 carry it.
Both are `secondary`, not a manufacturer drawing, and they are consistent
with each other and with the 3 B+ sheet.

**The agreement that should have prompted this earlier.** The SEN0032
returned `0xe5` from `DEVID` first time and gave consistent gravity in two
orientations on Saturday 3 October 2026. A bus ten times outside its
rise-time condition does not behave that way; it fails on the rising edge,
intermittently, with wrong values rather than absent ones, which is exactly
what the section above predicts. The prediction and the observation
disagreed for a day and the observation was the older of the two.

## What the ADXL345 datasheet would settle, and currently does not

These are claims this project relies on that are **not** sourced from the
manufacturer's document. Each is marked with where it actually comes from.

| Claim | Used for | Current basis |
|---|---|---|
| a digital pin's absolute maximum is VDD I/O plus 0.3 V, or 3.6 V, whichever is less | the rule that a 3.3 V host sits exactly at the limit | `inferred` from general familiarity with the part, not from the document |
| `SDO` low selects one I2C address and high selects the other | the brown strap to GND in the wiring | `inferred`; the address value `0x53` appears in `DESIGN.md` and the overlay |
| `CS` high selects I2C rather than four-wire SPI | the orange strap to 3V3 | `inferred` |
| the device identification register and its fixed value | the probe that proves the right part answered | not stated anywhere in this project |
| the available output data rates and the g ranges | the IIO attributes the driver exposes | not stated anywhere in this project |

**None of these is likely to be wrong.** That is not the point. The point
is that a reader cannot currently check any of them, and the project's own
`DESIGN.md` is scrupulous about marking its other inferences, so these
should be marked too rather than passing as settled.

**The datasheet could not be fetched.** Three attempts to
`analog.com` on Wednesday 7 October 2026 returned a connection reset and
two timeouts. The URL is in the index and is believed good; this reads as
rate limiting rather than a dead link.

## What the module's schematic settles that no datasheet could

Worth stating because it is the opposite lesson, and it is the one that
cost an evening.

**The supply must come straight from the host's 3V3 pin, not through a
breadboard power rail.** The module read nothing, then intermittently,
until its supply was taken directly from the Nucleo's `+3V3`. The general
form is worth more than the instance: **a supply rail is the one conductor
that bus-based continuity tests cannot check.** Tying a signal row to the
ground row proves the signal and ground leads and says nothing about the
rail.

**Its header is not soldered, so every connection is a friction contact.**
Bare plated holes, male pins pushed through and into a breadboard so the
breadboard's spring holds each pin against its hole wall. In every step,
assume any one of the six contacts can be open at any moment, and that
"the connections are in place" means positioned, not conducting.

**An intermittent supply here does more than go quiet.** The ADXL345's
protection diodes clamp `SDA` and `SCL` toward its dead rail and take
other devices on the same bus down with it. That was observed on Tuesday 6
October 2026, when an X-NUCLEO shield's own soldered sensors dropped out
of a scan while this module's supply contact was wandering. So **a bus
that goes strange while this module is attached is a suspect in its own
right**, and the first move is to remove it and rescan.

**It is a known good part.** It has been read successfully before, on a
Raspberry Pi. A silent SEN0032 is a wiring or contact question and never a
dead part question, and no debugging here should spend a step on replacing
it.

## The one purchase that would change this project

**A soldering iron and one 8-pin 2.54 mm male header.** With a fitted
header the friction-contact caveat disappears entirely, and with it the
whole class of intermittent failures above. There is no soldering iron on
this bench. A multimeter ranks ahead of it overall, but for this project
specifically the header is the thing.

## What to do when the datasheet arrives

In order, because each one makes the next cheaper:

1. Fill the five rows in the table above, with page numbers, and change
   their basis from `inferred` to `datasheet`.
2. Check the absolute maximum against the actual rail. `DESIGN.md`
   reasons that `INT1` cannot be driven above 3V3 because the module is
   powered from 3V3; the datasheet is what turns that from a good argument
   into a cited one.
3. Record the identification register and its value, so that a probe
   becomes a measurement rather than an impression, exactly as project 7
   needs for its display controller.
