# Hardware sources for project 1

[docs/DESIGN.md](DESIGN.md) carries the architecture, the LED wiring, the
console wiring and the LK-LED10 pinout, including the correction that cost
three projects. **This page does not repeat any of that.** It records
where the numbers come from, now that the host's datasheet and the
instrument's guide have been read, and names the one specification that
bounds this project's acceptance figures.

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What has been read

| Document | Evidence | Status |
|---|---|---|
| Raspberry Pi 4 Model B datasheet, release 1.1, 12 March 2024 | `datasheet` | **read Wednesday 7 October 2026** |
| PPK2 user guide v1.0.1, document 4461_012 | `datasheet` | **read**, in [project 3's page](../../03-boot-energy/docs/hardware.md) |
| the microSD card in use | | **`NOT READ`**, and see below: nobody knows which card it is |
| Joy-it LK-LED10 | | no datasheet found; the module is characterised by **measurement** instead |

## The sentence in the design that now has a source

`DESIGN.md` says: "The series resistor is on each module rather than on
the breadboard; a GPIO pin sources at most a few milliamps."

**Raspberry Pi 4 Model B datasheet, Table 3, page 8**, footnotes: the
default drive strength is **8 mA** and the maximum is **16 mA**, with a
guaranteed output current of at least 7 mA at maximum strength.

So "a few milliamps" is conservative and correct, and it now has a number
rather than a feel. **And the measurement agrees with it from the other
side.** The LED currents taken with the PPK2 on Saturday 3 October 2026,
recorded in [docs/HARDWARE.md](../../../docs/HARDWARE.md), are 2.94 mA to
7.39 mA at 3.3 V across the four modules. Three modules driven together
draw 16.5 mA at 3.3 V, which is inside one pin's maximum and spread across
three pins.

**The two sources are independent and they agree**, which is the only kind
of confirmation worth having: one is the manufacturer's specification of
what a pin may drive, the other is an instrument's reading of what these
particular parts actually draw.

**One caveat, carried honestly.** The 8 mA and 16 mA figures are the Pi
4's. This project's board is a Pi 4, so they apply directly. They would
not apply to the Pi 3 in projects 6, 18, 19 and 20, which has no published
electrical specification at all.

## The LED measurements are better than the file used to say

Also corrected on Wednesday 7 October 2026: the LED current table carried
a caveat of plus or minus 20 per cent, taken from Nordic's overview page.
**The user guide's Table 9, page 17**, gives 10 per cent accuracy with a
2 per cent offset for everything between 100 nA and 50 mA. Every value in
that table lies between 2.94 mA and 15.98 mA, so **they all carry 10 per
cent.**

The derived effective resistances near 247 ohm and the derived forward
voltages inherit the same 10 per cent. That is still not four significant
figures, and the table says so.

## The photograph that corrected three projects, and why it belongs here

[`figures/leds-lit.jpg`](figures/leds-lit.jpg) is the single most
load-bearing piece of evidence in this repository, and it is not a
document.

The notes used to claim the LK-LED10's 2.0 mm LinkerKit socket could not
take ordinary Dupont jumpers and that a special cable or a soldered
pigtail was needed. That belief deferred this project's LED output, three
status LEDs in project 4, and shaped project 9 around bare LEDs and
resistors that are not on this bench. **Nothing was ever missing.** The
modules carry a 2.54 mm male header for `S1`, `S2`, `U` and `G` beside the
2.0 mm housing, and three were lit from GPIO17, GPIO27 and GPIO22 on
Friday 2 October 2026.

**There is no LK-LED10 datasheet to have read.** Searching for one is not
what would have prevented this; looking at the part would have. So this
project is the precedent for a rule the rest of the bench now follows:
**where the bench can answer, photograph the bench.** It is recorded in
[docs/DATASHEETS.md](../../../docs/DATASHEETS.md) under the citation
conventions for exactly that reason.

**And the module's own behaviour is `measured`, not specified.** Which way
round the LED sits is not printed on the board. The signal pin is the
anode side, so the header **sources**, a pin driven high is lit, and a
line released to an input is dark and reads low. That was established on a
Raspberry Pi 3 Model B Rev 1.2 with libgpiod v2.2.1 on Friday 2 October
2026, by driving high, driving low, and releasing. Every one of those
three steps is necessary: the first two without the third would not
distinguish a lit LED from a floating one.

## The card interface, which bounds this project's numbers

This project's acceptance criteria are about image size and build and boot
behaviour, and the thing every one of them eventually passes through is
the microSD card.

**Raspberry Pi 4 Model B datasheet, section 5.1.4, page 11:** the
dedicated SD card socket supports 1.8 V DDR50 mode, at a peak bandwidth of
**50 megabytes per second**.

| What that bounds | How |
|---|---|
| boot time | every byte of kernel and rootfs crosses that interface |
| flashing time | writing a 78 MB image cannot beat about 1.6 s of pure transfer, and in practice is far slower |
| any size-versus-speed trade | a smaller image is faster to boot in direct proportion, which is the argument this project is making |

**It is a peak, not a rate.** The datasheet gives the interface's
bandwidth; the card's own sustained write rate is usually much lower and
is a property of the card, not of the Pi. **Which card is on this bench is
not recorded anywhere**, and that is the gap.

That matters more than it looks for a project whose headline is image
size. A boot time measured on a fast card and a boot time measured on a
slow one are not comparable, and nothing in the evidence currently says
which was used. **Recording the card's make, model and speed class in the
evidence directory costs one line** and makes every timing figure in this
project reproducible instead of indicative.

## The before-power questions, answered once for this project

| Question | Answer, and source |
|---|---|
| what draws current and from where | the Pi from its USB-C supply, 5 V at 3 A per section 4.1 page 8; the LEDs from three GPIO pins, at 8 mA default drive per Table 3 page 8 |
| which connector is data and which is power | the USB-C port is power only here, unlike [project 14](../../14-usb-gadget/docs/hardware.md), where it is both |
| what on the header is about to be driven | GPIO17, GPIO27 and GPIO22 as outputs, and GPIO14 and GPIO15 as the console |
| the one wiring mistake that would matter | the LK-LED10's `U` pin to header pin 2 or 4 instead of pin 1. `DESIGN.md` writes "NEVER pin 2 or 4 (5 V)" in capitals and that is proportionate |

**And the module does not need `U` at all.** One module was lit with that
jumper pulled, so the supply pin is optional and the safest wiring is the
one that omits it. A wire that is not there cannot be in the wrong hole.

## Reflections on the wiring, and on the rewiring that never happened

**This project's wiring was deferred for a year on a belief about a
connector.** Not on a measurement, not on a failed attempt, on a reading
of a part that nobody had picked up. Three projects were designed around
the deferral.

**The rewiring, when it came, was no rewiring at all**: the modules
plugged straight onto ordinary jumpers and lit first time. The cost was
entirely in the delay and in the three designs that routed around a
non-existent obstacle.

**The general form, which this bench has since adopted.** Where a claim is
about a part that is physically present, the cheapest check is to look at
it, and a photograph makes the check reviewable afterwards. Documents are
for the things you cannot see: voltages, timings, register layouts,
tolerances. **Connectors are not one of those things.**

## Still `NOT READ`

| Document | Why it matters |
|---|---|
| the microSD card's specification | every timing figure in this project rests on it, and the card is not even identified |
| a Joy-it LK-LED10 datasheet | none found; the module is characterised by measurement, which for this part is sufficient and is labelled as such |
