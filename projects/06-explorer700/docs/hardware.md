# Hardware sources for project 6

**This project's sourcing already has a home**, and it is the most
complete one on this bench:

**[docs/pin-map.md](pin-map.md)**

That page maps every line of the RB-Explorer700 against the JOY-iT manual,
with an evidence column on each row, and records the three places where
the manual contradicts itself about one sensor. Nothing here repeats it.

This page exists for the part the pin map does not cover: **what the
host's own documents add**, now that they have been read, and what remains
unsourced about the HAT.

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What has been read

| Document | Evidence | Status |
|---|---|---|
| JOY-iT RB-Explorer700 manual, 16 November 2020 | `datasheet` | **read**, fully worked through in [pin-map.md](pin-map.md) |
| Raspberry Pi 3 Model B product page | `vendor page` | **read Wednesday 7 October 2026**, and it is thin, see below |
| Raspberry Pi 4 Model B datasheet, release 1.1 | `datasheet` | **read**, and it is the nearest thing to an electrical specification this host has |
| DS3231 datasheet, the real time clock on the HAT | `datasheet` | **`NOT READ`** |
| PCF8574 and PCF8591 datasheets | `datasheet` | **`NOT READ`** |

## The host of this project is the one board with no document of its own

This project runs on a **Raspberry Pi 3**, not a 3B+. And the Raspberry Pi
3 Model B has **no product brief and no datasheet**. Its product page
gives a bulleted specification list and nothing else; it does not even
link a PDF, only two package change notices.

| What the product page states | Value |
|---|---|
| SoC | quad core 1.2 GHz Broadcom BCM2837, 64-bit |
| RAM | 1 GB |
| wireless | BCM43438 wireless LAN and Bluetooth Low Energy on board |
| Ethernet | **100 Base**, not Gigabit |
| GPIO | 40-pin extended GPIO |
| USB | 4 USB 2 ports |
| power | switched micro USB source up to 2.5 A |
| production | until at least January 2028 |

**So every electrical claim about a Raspberry Pi 3 GPIO on this bench
comes from the Pi 4 datasheet**, which is a different SoC, or from the
BCM2835 peripherals document, which is a different part again and gives
registers rather than volts. That is already recorded in
[docs/HARDWARE.md](../../../docs/HARDWARE.md); it matters here because
this project puts eleven peripherals on one header and reasons about pull
state and drive on several of them.

**The practical form of that gap**, for this project specifically: the
I2C bus on GPIO2 and GPIO3 relies on pull-ups, and whether those are the
HAT's or the SoC's internal ones is a question the pin map answers from
the HAT's schematic. If it were ever answered from the host side, the only
number available would be the Pi 4's 47 kohm typical, which is **not a
figure for this board** and would have to be labelled so.

## What the Pi 4 datasheet adds that this project can use safely

One row, and it is about a limit rather than a value.

**Table 3, page 8:** the internal pull-up and pull-down is 18 kohm
minimum, 47 kohm typical, 73 kohm maximum, and the per-pin output drive is
8 mA by default and 16 mA at maximum strength. **Table 5, page 10** gives
the default pull state of every GPIO, which is the thing that decides what
a pin does between reset and the overlay being applied.

**That window is the one this project should care about.** Eleven
peripherals bound by one device tree overlay means eleven lines that have
some state before the overlay loads, and the default pull is what
determines it. The Pi 4 table is the only published list of those
defaults; for a Pi 3 it is `inferred`, and the BCM2835 peripherals
document's Table 6-31 gives the same column for the earlier part, which is
the better source here and is already cited in
[project 9's hardware page](../../09-kernel-debug/docs/hardware.md).

## The HAT's own silicon is still unsourced

The pin map is complete about **which line goes where**. It is explicitly
not a source for **what each part does**, because the three component
datasheets have not been read.

| Part | Role on the HAT | What its datasheet would settle |
|---|---|---|
| DS3231 | real time clock | the I2C address, the alarm registers, the temperature sensor's resolution, and the ageing offset; also its own accuracy, which is the only reason to fit a DS3231 rather than anything cheaper |
| PCF8574 | 8-bit I2C expander | the address strap bits, and that its outputs are **quasi-bidirectional** rather than push-pull, which changes how a line is driven and is the classic surprise with this part |
| PCF8591 | 8-bit I2C ADC and DAC | the reference arrangement, the conversion time, and whether the four inputs are single-ended or can be paired differentially |

**The PCF8574 row is the one worth reading first.** A quasi-bidirectional
output cannot sink and source like a normal GPIO, and code that drives it
as though it could works for LEDs and fails for anything that needs a
strong high. This project binds its lines through `gpio-pcf857x` and the
kernel handles it, so nothing is currently wrong; the risk is in anything
written later that assumes an ordinary output.

## Reflections on the wiring, which there is almost none of

**This is the project with the least wiring on the bench and the most
mapping.** The HAT seats on the header in one orientation and there are no
jumper leads at all. Every question is about what is already connected
rather than about what to connect.

**That is why the manual's self-contradictions mattered so much.** With no
wires to check, the document is the only thing standing between a line
number and a wrong register. Three contradictions about one sensor, found
by reading carefully, are worth more here than any amount of continuity
testing, because there is nothing to test continuity on.

**And the general form is worth keeping**, because it inverts the usual
advice on this bench: where there are leads, suspect the leads; where
there are none, suspect the document.

## Still `NOT READ`

| Document | Why it matters |
|---|---|
| DS3231 datasheet | project 6's `rtc` binding, and whether the temperature reading is usable |
| PCF8574 datasheet | the quasi-bidirectional output question above |
| PCF8591 datasheet | the analog inputs' reference and conversion time |
| a Raspberry Pi 3 Model B electrical specification | does not exist; the gap is permanent and should be named rather than closed |
