# The bench, part by part

Welcome. This page is the shared hardware reference for all twenty
projects: what is actually on the bench, where each fact came from, and
the handful of physical rules that apply before any of it is powered.

It exists because the same questions kept being answered twice, and
because a few of them were once answered wrongly with confidence. Both of
those are cheaper to fix in one place.

**Read this before wiring anything, and before writing a project's
design.** A project that assumes a part is missing when it is present, or
present when it is missing, has to be rewritten rather than corrected.
That has happened here three times.

## Every project has its own hardware sourcing page

This page is the shared reference. **Each project also has a
`docs/hardware.md`** that does something different: it says where that
project's own hardware claims came from, which of them are confirmed, and
which are still waiting on a document that has not been read.

The division is deliberate. This page holds what is true of the bench.
A project's page holds what is true of that project, including its
unknowns, which belong next to the work rather than in a shared file.

| Project | Its hardware page is mostly about |
|---|---|
| [1, Yocto image](../projects/01-yocto-image/docs/hardware.md) | the drive strength behind "a few milliamps", and why a photograph outranked a datasheet |
| [2, NEO Air](../projects/02-neo-air-mainline/docs/hardware.md) | an input range of 4.7 to 5.6 V, and a 24 pin header that resembles a Raspberry Pi's and is not one |
| [3, boot energy](../projects/03-boot-energy/docs/hardware.md) | the PPK2's real limits, including the 600 mA one that corrected this project's design |
| [4, netboot HIL](../projects/04-netboot-hil/docs/hardware.md) | 300 Mbit/s of Ethernet over USB, and two routes to a power cycle that neither board has here |
| [5 and 11, ADXL345](../projects/05-iio-adxl345/docs/hardware.md) | module against die, and a 47 kohm pull-up that predicts its own failure |
| [6, Explorer 700](../projects/06-explorer700/docs/hardware.md) | a host with no datasheet at all, and three HAT parts still unread |
| [7, LCD 3.5](../projects/07-lcd35-drm/docs/hardware.md) | a panel controller the vendor never names |
| [8, PREEMPT_RT](../projects/08-preempt-rt/docs/hardware.md) | an instrument whose datasheet specifies everything except its own clock |
| [9, kernel debug](../projects/09-kernel-debug/docs/hardware.md) | the three bit field under the console, from the register to the wire |
| [10, IIO IKS4A1](../projects/10-iio-iks4a1/docs/hardware.md) | ST's register maps as code, an 8-bit address trap, and a second IMU nobody listed |
| [12, sensor hub](../projects/12-sensor-hub/docs/hardware.md) | why moving sensors behind firmware removes most of this bench's hazards, and what it costs |
| [13, Wayland kiosk](../projects/13-wayland-kiosk/docs/hardware.md) | a touch controller the vendor never names, and a safety instruction worth borrowing |
| [14, USB gadget](../projects/14-usb-gadget/docs/hardware.md) | a board run knowingly at a third of its specified supply |
| [15, LTE router](../projects/15-lte-router/docs/hardware.md) | two vendor documents giving opposite PWRKEY polarities |
| [16, NB-IoT tracker](../projects/16-nbiot-tracker/docs/hardware.md) | a vendor page that answers almost nothing, and a 0 ohm resistor that sets the logic voltage |
| [17, BLE gateway](../projects/17-ble-gateway/docs/hardware.md) | a link that is a radio, so the peripheral is the primary source |
| [18, edge AP](../projects/18-edge-ap-mqtt/docs/hardware.md) | two documents that each state exactly what the other omits |
| [19, RAUC A/B](../projects/19-rauc-ab/docs/hardware.md) | a project whose hardware is a card nobody has identified |
| [20, OP-TEE](../projects/20-optee-keystore/docs/hardware.md) | how to cite an absence, when no document says what a part lacks |

**Four recurring shapes** came out of writing them, and they are worth
knowing before reading any one of them.

1. **The driver names the part and the manufacturer does not.** The
   ILI9486, the FT5406, the dual-role `dwc2` port and the BCM43455 are all
   identified from Linux. It is reliable and it is not a citation.
2. **The easily reachable version of a document says least.** Nordic's
   HTML guide against its PDF, and the Raspberry Pi 3B+ brief against a
   datasheet that does not exist.
3. **Two documents from one vendor are two sources.** Where both exist,
   diff them. On the SIM7600E-H HAT they disagree about a polarity.
4. **Where the bench can answer, photograph the bench.** A connector, a
   jumper cap, a 0 ohm resistor and a chip marking have each blocked more
   than a datasheet could unblock.

## How to read the evidence column

Every hardware claim in this repository carries one of these. The idea is
borrowed from [project 6's pin map](../projects/06-explorer700/docs/pin-map.md),
which did it first and does it best.

| Level | Means |
|---|---|
| `datasheet` | Read out of the manufacturer's own document, which is cited by name and where possible by URL and date |
| `schematic` | Read off the vendor's schematic, which is a different and usually better source than the product page |
| `vendor page` | Stated on the product or wiki page only. Weaker: vendor pages contradict their own schematics more often than you would like |
| `inferred` | Not stated anywhere. The reasoning is given, and the row is a hypothesis rather than a fact |
| `measured` | Seen on this bench, with the instrument and the date |
| `NOT READ` | A datasheet exists and nobody here has opened it. This is an honest row, and it is better than a plausible one |

**`NOT READ` is used a lot on this page and that is deliberate.** Several
vendor PDFs cannot be fetched from the authoring laptop at all, so filling
those rows from memory would produce something that reads like a
reference and is not one.

## Before power, every time

Three rules, and they are short because they are absolute.

**The console cable's red 5 V lead stays open.** Every board here has its
own supply. Two sources on one rail is how the adapter, and sometimes the
board, is destroyed. On the NanoPi NEO Air it is worse than that: the
supply is the instrument, so a second 5 V source makes the power profiler
measure part of the current with nothing anywhere saying so.

**Ground goes on first, and comes off last.** If a signal lead is
connected before the ground, that signal pin becomes the return path for
whatever current wants to flow. Connect black, then the signals.

**Nothing on a header is driven by software that has not been read against
a pinout.** A GPIO offset is a property of a board revision, not of a
part, and a wrong offset does not fail safely: it drives whatever else is
on that pin, usually while nobody is watching.

## The console cable

A Renkforce USB/TTL jumper cable, a **PL2303HXA** with four leads. The
same four colours go to every board on this bench.

| Lead | Signal and direction | Raspberry Pi 40-pin header | NanoPi NEO Air 4-pin debug header |
|---|---|---|---|
| **black** | GND | pin 6 | pin 1 |
| **white** | board TX, cable RX | pin 8, GPIO14 `TXD0` | pin 3, `TXD0` |
| **green** | board RX, cable TX | pin 10, GPIO15 `RXD0` | pin 4, `RXD0` |
| **red** | 5 V | **nothing** | **nothing** |

Evidence: `measured`, in the sense that this cable has been used and the
colours confirmed. **If a different adapter ever appears, its own printed
labels win over this table.**

On a Raspberry Pi, pins 6, 8 and 10 are three consecutive pins in the
**even** row, which is the row nearer the board edge, counting from the
end nearest the micro-USB power connector: position 1 is pin 2, position 2
is pin 4, position 3 is pin 6, and so on. A reliable cross check is the
heartbeat LED, when a project has one: its ground is pin 9 and its signal
pin 11, both in the odd row, so **green sits directly across the header
from the LED's ground lead**.

### Which UART those two pins carry is a three bit field

Worth knowing before anything else about the serial console, because it
makes the rest make sense. **Source: BCM2835 ARM Peripherals, Broadcom, 6
February 2012**, Table 6-31 on page 102 and its legend on page 103.

| Pin | Default pull | ALT0 | ALT5 |
|---|---|---|---|
| GPIO14, header pin 8 | Low | `TXD0`, UART 0 transmit | `TXD1`, mini UART transmit |
| GPIO15, header pin 10 | Low | `RXD0`, UART 0 receive | `RXD1`, mini UART receive |

UART0 is the PL011. So **the same two header pins carry either the PL011
or the mini UART, and the only difference is the alternate function
number.** "The UART" is therefore an ambiguous phrase on this board.

The choice lives in three bits. Table 6-1 on page 90 puts the GPIO
registers at bus address `0x7E20 0000` with GPFSEL1 at `0x7E20 0004`;
Table 6-3 on page 92 puts FSEL14 at bits 14 to 12 and FSEL15 at bits 17 to
15; and Table 6-2 on the same page gives the encoding, in which **ALT0 is
binary `100`, which is 4**, and the reset value for every pin is `000`,
plain input. That 4 is where `pin_func=4` in a `config.txt` line comes
from.

**The address trap.** The datasheet gives bus addresses beginning `0x7E`.
The ARM physical base is `0x2000 0000` on a BCM2835, which is a Pi 1 or
Zero, and `0x3F00 0000` on the BCM2836 and BCM2837 of a Pi 2 or Pi 3. So
GPFSEL1 is at `0x3F20 0004` on every Pi 3 here, and an address copied
straight from the PDF reads the wrong place without complaining. This row
is `inferred`: the document predates the Pi 3 and does not say it.

### The serial console does not currently work on the Raspberry Pi

This is the single most expensive thing on this page, so it is near the
top rather than buried.

`disable-bt` moves the PL011 to the header pins by targeting `uart0_pins`
and declaring `brcm,pins`, `brcm,function` and `brcm,pull` as **empty**
properties. It blanks the group and leaves the real values to the
VideoCore firmware, and on the bench image that firmware does not supply
them. The result is a kernel that enables a console on `ttyAMA0`, a
`/proc/consoles` that lists it, a driver that probes, writes that succeed,
and not one bit reaching the header.

The only evidence is one line, at about 4.6 seconds, printed on the
console that does not work:

    uart-pl011 3f201000.serial: there is not valid maps for state default

**Diagnose in this order and do not start at the cable.** Measured
Tuesday 6 October 2026; starting at the cable cost most of an afternoon.

```sh
ssh root@BOARD "dmesg | grep -i -e pl011 -e uart -e 'valid maps'"
ssh root@BOARD "grep -E 'pin 14|pin 15' /sys/kernel/debug/pinctrl/*/pinmux-pins"
ssh root@BOARD "wc -c /proc/device-tree/soc/gpio@7e200000/uart0_pins/brcm,pins"
```

Muxed pins read `3f201000.serial ... function alt0`. Unmuxed pins read
`(MUX UNCLAIMED)`, and then no cable can help.
`dtoverlay=uart0,txd0_pin=14,rxd0_pin=15,pin_func=4` fixes the mux, which
is `measured`, and did **not** by itself make output appear on the host. A
second fault is still open. [Project 9's journal](../projects/09-kernel-debug/JOURNAL.md)
entries 26 and 27 have the whole account.

### Splitting the cable between a terminal and gdb

kgdb and the console are the same UART. `agent-proxy` holds the device and
offers two TCP ports, 5550 for the console and 5551 for gdb, and
[`./go proxy`](../projects/09-kernel-debug/host/agent-proxy.sh) wraps it.
Two notes that cost time: **use `telnet`, not `nc`**, because the proxy's
telnet negotiation arrives through `nc` as a run of replacement characters
that looks exactly like line noise; and the adapter **renumbers between
`/dev/ttyUSB0` and `/dev/ttyUSB1`** whenever it re-enumerates, taking the
proxy down with it, which from outside reads as a dead cable.

### The Raspberry Pi 3 electrical specification exists, and this file said it did not

**Correction, Friday 9 October 2026.** For three days this file, and four
project pages following it, said that the Raspberry Pi 3 Model B has no
electrical specification, that the gap was permanent, and that every claim
about a Pi 3 GPIO therefore had to be borrowed from the Pi 4 datasheet.

**All of that was wrong.** The specification is published, in the GPIO
section of Raspberry Pi's own documentation rather than in a datasheet,
and it covers exactly the parts this bench uses.

**Source: Raspberry Pi documentation, "GPIO", AsciiDoc source at
`documentation/asciidoc/computers/raspberry-pi/gpio-on-raspberry-pi.adoc`
on the `master` branch of `raspberrypi/documentation`.** Read Friday
9 October 2026.

Its "Voltage specifications" section carries **two** tables, and names
whose they are:

> The table below gives the various voltage specifications for the GPIO
> pins for BCM2835, BCM2836, BCM2837 and RP3A0-based products (for
> example, Raspberry Pi Zero or Raspberry Pi 3+).

and then a second for "BCM2711-based products (4-series devices)".

**How the mistake happened, because it is worth not repeating.** The
search was for a *datasheet*, and the question asked was "does Raspberry
Pi publish a Pi 3 datasheet". The answer to that question is still no.
The answer to the question that mattered, "does Raspberry Pi publish the
Pi 3's GPIO electrical characteristics", is yes, and in a place a
datasheet search does not reach. **The name of the document is not the
name of the fact.**

### What the Pi 3 table actually says

For BCM2835, BCM2836, BCM2837 and RP3A0, which is the Pi Zero, Pi 1,
Pi 2, Pi 3 and **Pi 3B+**:

| Symbol | Parameter | Condition | Value |
|---|---|---|---|
| `V_IL` | input low voltage | | 0.9 V maximum |
| `V_IH` | input high voltage, hysteresis enabled | | **1.6 V minimum** |
| `I_IL` | input leakage current | TA = +85 C | 5 microamp maximum |
| `C_IN` | input capacitance | | 5 pF maximum |
| `V_OL` | output low voltage, default drive | `I_OL` = -2 mA | 0.14 V maximum |
| `V_OH` | output high voltage, default drive | `I_OH` = 2 mA | **3.0 V minimum** |
| `I_OL` | output low current, maximum drive | `V_O` = 0.4 V | 18 mA minimum |
| `I_OH` | output high current, maximum drive | `V_O` = 2.3 V | 17 mA minimum |
| `R_PU` | pull-up resistor | | **50 to 65 kohm** |
| `R_PD` | pull-down resistor | | 50 to 65 kohm |

with default drive strength 8 mA and maximum 16 mA.

### And the two Raspberry Pi documents disagree about the Pi 4

The same page's second table is for BCM2711, which is the Pi 4. Put it
beside the Pi 4 datasheet, Table 3 page 8, which this bench read on
Wednesday 7 October 2026:

| Quantity | Pi 4 **datasheet**, release 1.1 | GPIO **documentation**, BCM2711 table |
|---|---|---|
| pull-up resistor | 18 / 47 / 73 kohm | **33 to 73 kohm**, no typical |
| default drive strength | **8 mA** | **4 mA** |
| maximum drive strength | **16 mA** | **8 mA** |
| `I_OH`, maximum drive | 7 mA minimum at `V_O` = 2.3 V | 7 mA minimum at `V_O` = **2.6 V** |

**Two documents from one vendor, about one chip, giving different
numbers.** This file already carries that rule for Waveshare and for
Nordic; it now carries it for Raspberry Pi, who had been treated as the
one source here that did not need diffing.

**No attempt is made to say which is right.** The datasheet is dated and
revision controlled, release 1.1 of 12 March 2024, and says its electrical
specification was updated in that revision. The documentation page is
undated in its source. Where a design depends on one of these numbers,
**cite which document, and prefer the more conservative figure**: 4 mA of
guaranteed default drive rather than 8, and a pull-up that might be 73
kohm rather than 47.

### GPIO2 and GPIO3 have fixed pull-ups, which reverses a conclusion

From the same page, in its second paragraph:

> Pins GPIO2 and GPIO3 have fixed pull-up resistors, but for other pins
> this can be configured in software.

**That is header pins 3 and 5, the primary I2C bus.** Those two pins are
not on the internal pull-up at all; they have resistors fitted to the
board.

**This reverses the arithmetic in
[project 10's page](../projects/10-iio-iks4a1/docs/hardware.md) for the
case that matters most.** That working put the host's internal pull-up,
47 kohm, into Sensirion's bus capacitance formula and found it short by
more than an order of magnitude. The arithmetic is right. **What was wrong
was assuming it applied to a Raspberry Pi's I2C bus**, because a
Raspberry Pi's I2C bus does not use the internal pull-up.

Where it still applies, unchanged:

| Case | Does the arithmetic apply? |
|---|---|
| an I2C bus on a Pi's GPIO2 and GPIO3 | **no**, fixed resistors are fitted |
| a bit-banged I2C bus on other Pi GPIOs | **yes** |
| an I2C bus on a host that fits no pull-ups | **yes** |
| any slow signal, such as a pen-down interrupt | no, and [project 7's page](../projects/07-lcd35-drm/docs/hardware.md) says why |

**And the shopping item is withdrawn.** Project 5's page recommended
buying two resistors of about 4.7 kohm so that the SEN0032's bus would
meet the condition. On a Raspberry Pi that purchase buys nothing, because
the board already fits them.

**The value of the fitted resistors is recorded on this bench as 1.8
kohm**, and that figure is not in the documentation, which says only that
they exist. The Pi 3B+ reduced schematic does show a 1.8 kohm pair at one
per cent tolerance, but in the `ID_SD` and `ID_SC` area, which is the HAT
identification bus and **a different bus**, so that reading does not
confirm the value for GPIO2 and GPIO3. **Existence: `vendor page`. Value:
recorded here, not yet cited.**

### What this changes about the rest of this file

The Pi 3 figures above should be used wherever a Pi 3 or Pi 3B+ number was
previously borrowed from the Pi 4 datasheet, and the two differ in ways
that matter:

- **`V_IH` is 1.6 V on a Pi 3 and 2.0 V on a Pi 4.** A Pi 3 is the more
  tolerant input, so any level check that passed on the Pi 4 figure passes
  on a Pi 3 with more room.
- **`V_OH` is 3.0 V minimum at 2 mA on a Pi 3**, stated outright, rather
  than the Pi 4 datasheet's `VDD_IO - 0.4`.

**Applied to the CP2102 check above**, whose relevant board in project 9
is a Pi 3B+ rather than a Pi 4: the Pi drives at least 3.0 V into a part
needing 2.0 V, a margin of 1.0 V rather than the 0.9 V computed from the
Pi 4 figure. The conclusion is unchanged and the citation is now the right
one for the board.

### The CP2102, which is on three things here and checked against a Pi at last

**Source: Silicon Laboratories CP2102/9 Single-Chip USB to UART Bridge,
revision 1.6, December 2013.** Read Thursday 8 October 2026.
`silabs.com` returned 403, so this was read from a distributor's copy that
carries Silicon Labs' own revision line on every page.

This part appears three times on this bench: on the Joy-it SBC-ESP8266-PROG,
on the SBC-NodeMCU-ESP32, and on the SIM7600E-H 4G HAT, where
[project 15's page](../projects/15-lte-router/docs/hardware.md) found a
jumper position that wires it to the Raspberry Pi's own UART.

**One caveat before any of the numbers.** The two Joy-it boards are
recorded above as carrying "a CP2102 or CH340", which is not the same
thing: a CH340 is a different manufacturer's part with its own levels and
its own driver. **Everything below applies to a CP2102 and to nothing
else.** On the 4G HAT the part is named outright, in that manual's board
inventory, so the numbers apply there without doubt.

#### What it is

| | |
|---|---|
| interface | USB 2.0 full speed, 12 Mbit/s |
| clock and transceiver | both on chip; no crystal and no external resistors |
| regulator | on chip, **3.3 V output on the CP2102**, 3.45 V on the CP2109 |
| buffers | 576 byte receive, 640 byte transmit |
| baud rates | 300 bps to 1 Mbit/s, with **921600 bps** the specified maximum in Table 4 |
| data formats | 5, 6, 7 or 8 data bits; 1, 1.5 or 2 stop bits; odd, even, mark, space or no parity |
| supply | 3.0 to 3.6 V self-powered, 4.0 to 5.25 V USB bus powered |
| supply current | 20 mA typical and 26 mA maximum in normal operation; 80 to 100 microamp suspended |
| temperature | -40 to +85 C |

#### The pairing with a Raspberry Pi, checked in both directions

This is the useful part, and until now it had been assumed rather than
worked out. Pi figures from the Raspberry Pi 4 datasheet Table 3 page 8;
CP2102 figures from Table 4 page 8 of its own datasheet.

| Direction | Driver guarantees | Receiver needs | Margin |
|---|---|---|---|
| Pi `TXD0` high into CP2102 `RXD` | at least `VDD_IO - 0.4` = **2.9 V** at 2 mA | `V_IH` at least **2.0 V** | 0.9 V |
| Pi `TXD0` low into CP2102 `RXD` | at most **0.4 V** at 2 mA | `V_IL` at most **0.8 V** | 0.4 V |
| CP2102 `TXD` high into Pi `RXD0` | `VDD - 0.1` = **3.2 V** into a 10 microamp load | `V_IH` at least **2.0 V** | 1.2 V |
| CP2102 `TXD` low into Pi `RXD0` | at most **0.1 V** at 10 microamp | `V_IL` at most **0.8 V** | 0.7 V |

**All four directions clear, with the tightest margin 0.4 V.** A Raspberry
Pi GPIO and a CP2102 are a clean pairing and now that is arithmetic across
two datasheets rather than a convention everybody follows.

**And 115200 baud is nowhere near any limit**, at an eighth of the
specified maximum.

This matters most for the plan in
[project 9's hardware page](../projects/09-kernel-debug/docs/hardware.md),
which proposes using the 4G HAT's CP2102 as the console adapter that
project went without. Its second precondition was "the `VCCIO` jumper must
be on 3.3 V, not 5 V, because the other side is a Raspberry Pi GPIO". That
precondition now has a reason with numbers behind it: **the CP2102's own
logic is 3.3 V, derived from its on-chip regulator**, and that is exactly
what a Pi expects.

#### The absolute maximum that breaks the pattern for good

This bench has been watching how parts state their limiting values, and
the CP2102 settles the question by doing something no other part here
does. **Table 2, page 6:**

| Parameter | Limit |
|---|---|
| voltage on `VDD` | -0.3 V to **4.2 V** |
| voltage on **any I/O pin**, `VBUS` or `RST` | -0.3 V to **5.8 V** |
| maximum total current through `VDD` and `GND` | 500 mA |
| maximum output current sunk by `RST` or any I/O pin | 100 mA |

**The I/O limit is higher than the supply limit.** 5.8 V on a pin against
4.2 V on the rail. That is deliberate: it is what "5 V tolerant I/O"
means, and it is impossible to express as "the supply plus a bit".

So the running tally of how six parts state the same kind of limit:

| Shape | Parts |
|---|---|
| signal pins referenced to the supply | PCF8574, SHT4x, ADS7846 |
| one flat figure for any pin | DS3231 |
| **signal pins flat and above the supply's own maximum** | **CP2102** |
| **absolute maximum equal to the recommended maximum**, no margin at all | **Allwinner H3**, `VCC_IO` at 3.6 V in both tables |

**Four shapes among six parts that state it.** The convention this
bench half-formulated on Thursday morning, that signal maxima are
supply-referenced, is a convention and not a law, and it took three
successive readings to say so properly. The rule that survives is the
dull one: **read the row, every time, and quote which row it was.**

#### What is still unknown, and it is the part number

The two Joy-it boards may carry a CH340 instead. Nothing read so far
settles which, and the settling move is the same as everywhere else on
this bench: **look at the chip.** A CP2102 is a 28-pin QFN of 5 by 5 mm,
per the ordering information on page 1; a CH340 in these products is
usually a 16-pin SOP, which is visibly a different package before any
marking is read.

That is one more line for the photograph list, and it is the cheapest one
on it: a package shape, not a marking, visible without magnification.

## Boards

| Board | On the bench | Evidence | Notes |
|---|---|---|---|
| Raspberry Pi 3 | yes | `vendor page` and `schematic` | no datasheet exists, but its **GPIO electrical specification does**, in the GPIO documentation, and its reduced schematic is read; see below |
| Raspberry Pi 3 Model B Plus | yes | `vendor page` and `schematic` | the Project 9 board, Rev 1.3; see below |
| Raspberry Pi 4 | yes | `datasheet` | the only one some HATs support; the only host here with a published electrical specification, see below |
| NanoPi NEO Air | yes | `NOT READ` | Project 2's target; its supply is the instrument when the profiler is in use |
| NUCLEO-H7A3ZI-Q | yes | `NOT READ` | STM32H7A3ZI, Nucleo-144; the firmware volume's board |
| SBC-NodeMCU-ESP32 | yes | `NOT READ` | carries a CP2102 or CH340 |
| Joy-it SBC-ESP8266-PROG | yes | `datasheet` | carries a CP2102 or CH340; **its socket pinout is published nowhere**, see below |

### The three Raspberry Pi hosts, read from their own documents

Until Wednesday 7 October 2026 this bench had used two Raspberry Pi hosts
for fourteen projects without once reading what Raspberry Pi says about
them. That is worth admitting at the top, because the gap it left is not
the one you would guess. The pinout was never in doubt. **What was missing
is the electrical specification, and for one of the two boards it is still
missing, because the manufacturer does not publish it.**

#### What the Pi 3B+ product brief gives

**Source: Raspberry Pi 3 Model B+ product brief, Raspberry Pi Ltd,
published October 2025**, pages 2 to 4. Read Wednesday 7 October 2026.

| Specification | Value | Page |
|---|---|---|
| processor | Broadcom BCM2837B0, Cortex-A53 64-bit SoC at 1.4 GHz | 3 |
| memory | 1 GB | 3 |
| input power | 5 V / 2.5 A DC via micro USB; 5 V DC via GPIO header; PoE with a separate HAT | 3 |
| operating temperature | 0 to 50 C | 3 |
| MTBF, ground benign | 378 000 hours | 3 |
| production lifetime | in production until at least January 2028 | 3 |
| board outline | 85 mm by 56 mm, dimensioned drawing | 4 |

**The part number is `BCM2837B0`, not `BCM2837`.** That matters more than
it looks. Project 9 reads GPIO function select registers out of the
*BCM2835 ARM Peripherals* document, and has been right to, but the reason
had never been written down: that document describes the peripheral block,
which the later parts inherit, while the ARM physical base address moves
from `0x2000 0000` on BCM2835 to `0x3F00 0000` on BCM2836 and BCM2837. So
the register layout transfers and the address does not. Using a document
whose part number does not match the board is defensible exactly once you
can say which parts of it transfer.

#### What the Pi 3B+ product brief withholds, which is the finding

A product brief is not a datasheet, and this one is honest about being a
brief. It contains **no GPIO pinout, no alternate function table, no input
or output voltage thresholds, no pull-up or pull-down values, and no
per-pin current figure.**

So: **nothing in this brief supports an electrical claim about a
Raspberry Pi 3 GPIO.** Before anyone repeats "3.3 V logic, 16 mA per pin,
50 mA in total" as settled, notice that the brief says none of those three
things.

**That used to be the end of the paragraph, and the sentence that followed
it was wrong.** It said every such claim therefore comes from somewhere
other than Raspberry Pi. On Friday 9 October 2026 the figures turned up in
the GPIO section of Raspberry Pi's own documentation, which names BCM2835,
BCM2836, BCM2837 and RP3A0 explicitly. They are set out below, with the
correction and how the mistake was made. The 50 mA total still has no
source anywhere.

#### Instructions from the brief that belong in the bench rules

All from page 4, quoted because they are instructions rather than numbers.

- the external supply shall be rated 5 V / 2.5 A and shall comply with the
  regulations of the country of use
- operate in a well-ventilated environment, and do not cover the case
- place it on a stable, flat, **non-conductive** surface, where no
  conductive item can touch it
- "The connection of incompatible devices to the GPIO connection may
  affect compliance, result in damage to the unit, and invalidate the
  warranty."
- whilst powered, avoid handling the board, or handle it by the edges, to
  limit electrostatic discharge
- **do not expose the printed circuit board to high-intensity light
  sources, for example a xenon flash or a laser, whilst in operation**

The last one reads like a joke and is not. It belongs in the bench rules
for a practical reason: **this bench photographs boards**, and several
questions still open here are waiting on a photograph of a running board.
Take it with the flash off, or take it powered down.

#### What the Pi 3B+ reduced schematic settles

**Source: Raspberry Pi 3 Model B+ reduced schematic, revision V1.0, sheet
1 of 1, drawn by Roger Thornton, dated Monday 19 March 2018, copyright
Raspberry Pi 2018.** Read Wednesday 7 October 2026.

**The console pins are confirmed by the manufacturer.** In the GPIO
EXPANSION block, the nets running from the SoC symbol `U1C` to `J8`, the
40 way 0.1 inch header, carry their alternate function names in brackets.
`GPIO14` is annotated `(TXD0)` and `GPIO15` is annotated `(RXD0)`. Those
are header pins 8 and 10. Until now project 9 identified them from the
Broadcom function select table plus the assumption that the header follows
it; the assumption is now a citation.

**The micro USB input is protected and the header input is not.** The
POWER IN block shows `J1`, the micro USB connector, feeding `F1`, a
resettable fuse marked `MF-MSMF250/X`, with `D7`, an `SMBJ5.0A` transient
voltage suppressor, across the output. That is where the brief's 2.5 A
figure comes from. The 5 V pins on `J8` sit on the same `5V` net
downstream of that fuse, which means **feeding 5 V into header pins 2 or 4
enters the board after the protection, not through it.** Evidence level
for the protection: `schematic`. Evidence level for the consequence:
`inferred`, from net naming on a sheet read at page resolution, not from a
continuity measurement.

**The same thing as a picture.** Redrawn from the POWER IN block, not
copied from it, and reduced to the three parts that matter to a bench.

```
    Raspberry Pi 3B+ power in, as drawn on the reduced schematic

      micro USB            F1                            5V net
         J1  o-----------[ MF-MSMF250/X ]-------+-------------o  to the
             |            resettable fuse       |                board
             |                                  |
             |                           D7  [ SMBJ5.0A ]
             |                             transient clamp
             |                                  |
            GND o------------------------------ o GND

      J8 pin 2  o--+
                   +------------------------->  the same 5V net,
      J8 pin 4  o--+                            downstream of both

      in through J1   : fused, and clamped at about 5 V
      in through J8   : neither
```

**The two LEDs are driven, not merely connected.** `D6`, the red POWER OK
LED marked "PWR", and `D5`, the green STATUS LED marked "ACT", are each
switched by a small transistor from nets named `STATUS_LED_R` and
`STATUS_LED_G`. **Where those nets originate is not legible on this sheet
at the resolution read**, so this does not yet prove that a beating ACT
LED means a live kernel. What it does prove is the weaker and still useful
statement: the ACT LED is not a bare indicator strapped across a supply
rail, so when it changes, something is deliberately changing it.

**And the limit of this reading, stated rather than implied.** This is one
A2 sheet rendered at page size. Net names and reference designators on the
blocks above were legible. Component values in the fine print near the
GPIO nets were not. So **"there is nothing between the SoC and header pins
8 and 10" is not a claim this reading supports**, and nobody should treat
it as one.

#### The Pi 3 Model B reduced schematic, and what it does and does not show

**Source: Raspberry Pi 3 Model B reduced schematic, revision 1.2, sheet
1 of 1, drawn by James Adams, dated Monday 4 April 2016, copyright
Raspberry Pi 2015.** Read Friday 9 October 2026, from the URL Joseph
supplied that day. One A2 sheet at page resolution, with the same limits
as the 3B+ sheet: reference designators and net names legible, fine print
not.

**This is the board projects 6, 18, 19 and 20 run on**, and until today
nothing of its own had been read beyond a product page.

**The 1.8 kohm pair is on the ID bus, on this board too.** `R23` and
`R24`, 1.8 kohm at one per cent from `3V3`, feed `ID_SD` and `ID_SC`
beside `U1C`, exactly as on the 3B+. The GPIO EXPANSION block annotates
header pins 3 and 5 as `(SDA1)` and `(SCL1)` and **shows no resistor pair
on them at this resolution.** So the second reduced schematic says the
same as the first: the HAT identification bus has fitted 1.8 kohm
pull-ups, and whatever GPIO2 and GPIO3 carry is either not drawn on a
reduced sheet or not legible. The documentation's statement that they
have fixed pull-ups stands; the value recorded on this bench as 1.8 kohm
remains uncited by either drawing.

**The micro USB input has a MOSFET stage, which this file understated.**
`J1` feeds `F1`, the `MF-MSMF250/X` polyfuse, then **`Q3`, a `DMG2305UX`
P-channel MOSFET, with `U14`, a `BCM857BS` transistor pair, and `R2` and
`R3`**, before `D5`, the `SMBJ5.0A` suppressor. That is the same shape as
the NanoPi NEO Air's input stage recorded in
[project 2's page](../projects/02-neo-air-mainline/docs/hardware.md),
which this file had contrasted with "one polyfuse, one transient
suppressor, in series" on the Raspberry Pi. **That description came from
the 3B+ sheet, where no MOSFET was noted at page resolution, and it does
not describe the 3B.** The contrast is withdrawn: both boards use a
MOSFET arrangement on the input, and neither sheet read here settles its
exact function.

**The red PWR LED is driven by a supply supervisor, not by the SoC.**
`D1`, red, is switched by `Q1` from `U4`, an **`APX803-46SAG`**, whose
`RST` output also appears as `PWR_LOW_N`. An APX803 is a voltage
supervisor; its threshold is in its own datasheet, `NOT READ`, and the
`46` in the part number is where that datasheet would say to look. **So
on a Pi 3B the PWR LED going out is a brownout indication from a
dedicated part**, which is why it is the one LED on the board whose
meaning does not depend on software. That matters to
[project 19](../projects/19-rauc-ab/docs/hardware.md), where power loss
is the experiment.

**The green ACT LED, `D2`, is switched by `Q6` from a net called
`STATUS_LED`**, whose origin is not legible, as on the 3B+. Two reduced
schematics, same answer, same gap.

**And the console pins are confirmed a third time.** `GPIO14` is annotated
`(TXD0)` and `GPIO15` `(RXD0)` on `J8`. The ID_SD and ID_SC warning box is
present word for word.

#### What the Pi 4 datasheet gives that nothing else on this bench does

**Source: Raspberry Pi 4 Model B Datasheet, Release 1.1, Raspberry Pi
(Trading) Ltd.** The release history on page 1 dates release 1 to
21 June 2019 and release 1.1 to 12 March 2024, describing the latter as an
update to the obsolescence statement and the electrical specification.
Read Wednesday 7 October 2026.

**This is the only document on this bench that states what a GPIO pin can
do electrically.** Four rows from Table 3, DC Characteristics, page 8,
selected because the bench depends on them and relaid out rather than
copied; the other eight rows, and the AC characteristics in Table 4, are
in the document.

| Quantity | Condition | Value |
|---|---|---|
| input low voltage, max | VDD_IO = 3.3 V | 0.8 V |
| input high voltage, min | VDD_IO = 3.3 V | 2.0 V |
| output current, min | at maximum drive strength, which is 16 mA; the default is 8 mA | 7 mA |
| internal pull-up or pull-down | | 18 kohm min, 47 kohm typical, 73 kohm max |

Page 7 adds the absolute maximum, a 5 V input between -0.5 V and 6.0 V,
and one sentence that is the key to the whole table: VDD_IO is the GPIO
bank voltage and it is tied to the on-board 3.3 V rail. That is what makes
every row above a 3.3 V row.

**The pull-up row pays for the whole document.** Project 5's page records
that the SEN0032 module carries no resistors at all, so a two-wire bus
built from it has only the host's internal pull-ups and nothing else. That
was a qualitative worry. It now has a number, and the number predicts the
failure: a 47 kohm pull-up is somewhere between five and twenty five times
the usual I2C value, so the rising edge is slow, and a bus like that works
at low clock rates over short wires and stops working as soon as either
grows. **That is a testable prediction rather than an unease**, which is
the whole reason to go and read the thing.

**Carry it across carefully, and say when you do.** That figure is the Pi
4's. The Pi 3B+ brief states no such number, and the ADXL345 work was done
on a Nucleo and on a Raspberry Pi. Writing "47 kohm" into a Pi 3 or STM32
context without naming where it came from would be exactly the move this
bench keeps catching itself making.

**What the datasheet does not say, and is widely believed to.** There is
no total GPIO current budget anywhere in it. The familiar figure of 50 mA
across all pins together does not appear. What appears is a per-pin drive
strength, default 8 mA and maximum 16 mA, in the footnotes to Table 3. If
a design here ever depends on a total, that total has no source.

#### The alternate function table, and the trap inside it

Table 5, page 10, lists the default pull state and six alternate functions
for GPIO 0 to 27. For the two pins project 9 cares about it agrees exactly
with the Broadcom document: `GPIO14` is `TXD0` on ALT0 and `TXD1` on ALT5,
`GPIO15` is `RXD0` on ALT0 and `RXD1` on ALT5. An independent confirmation
of a reading that had carried a lot of weight.

**The trap is everything else in the same table.** The Pi 4's ALT4 column
carries `TXD2` through `TXD5` and `RXD2` through `RXD5`, four extra UARTs
that BCM2711 added and **that do not exist on the Pi 3.** The datasheet
says so in its own words on page 9, that extra I2C, UART and SPI
peripherals have been added to BCM2711 and appear as further mux options.
So this table is a correct cross-check for ALT0 and ALT5 and a loaded
question for ALT4: read it while working on a Pi 3 and you can configure,
in good faith, a UART that is not on the chip.

**One sentence from page 9 is load-bearing for this whole repository.**
The Pi 4 makes 28 BCM2711 GPIOs available on a standard 40 pin header that
is backwards compatible with all previous 40-way Raspberry Pi boards. That
is the licence for a single pin map to serve both hosts, and it is better
to have it cited than assumed.

Also from the same figure, repeated from the Pi 3B+ schematic: the note
against `ID_SD` and `ID_SC`, header pins 27 and 28, reserved for the HAT
identification EEPROM, not to be used for anything else. That is why those
two rows are blank in every pin map here.

#### The rest of the Pi 4 datasheet, briefly

Power, section 4.1 page 8: a good quality USB-C supply of 5 V at 3 A; a
5 V 2.5 A supply may be used if attached downstream USB devices draw under
500 mA. USB, section 5.3 page 11: downstream current limited to roughly
1.1 A in aggregate across the four sockets. Thermals, section 5.6 page 11:
recommended ambient 0 to 50 C, with the governor throttling so the CPU
never exceeds 85 C. Availability, section 6 page 11: until at least
January 2031.

**And a versioning point worth more than it looks.** Release 1.1 changed
the electrical specification. A copy of release 1 from 2019 is a different
document with the same name, and quoting DC characteristics from a stale
local file is a way to be precisely, confidently wrong. Check the release
line on page 1 before using a number from any copy of this.

#### Which document answers which question

This is the table to look at first, and it is mostly a table of gaps.

| Question | Pi 3B+ brief | Pi 3B+ schematic | Pi 4 datasheet | BCM2835 peripherals |
|---|---|---|---|---|
| 40-pin header pinout | no | yes, with function names | yes, figure 3 | no |
| alternate function per pin | no | partly, names only | yes, table 5, Pi 4 only | yes, the register view |
| input thresholds | no | no | yes, table 3 | no |
| internal pull-up value | no | no | yes, table 3 | no |
| per-pin drive strength | no | no | yes, table 3 footnotes | no |
| total GPIO current | no | no | **no** | no |
| operating temperature | yes | no | yes | no |
| power input and protection | yes, the rating | yes, the fuse and TVS | yes, the rating | no |
| production lifetime | yes, January 2028 | no | yes, January 2031 | no |

**And the same thing as a picture, because the ordering is the point.**

```
     the question you actually have        the document that answers it

   "what is this product, and what         product brief (Pi 3B+)
    may I plug into it?"                   datasheet sections 1 to 4 (Pi 4)
            |
            v
   "what is physically on the board,       reduced schematic (Pi 3B+ only)
    and what is each header pin
    wired to?"
            |
            v
   "what can this pin be turned            BCM2835 ARM Peripherals, 6-31
    into?"                                 Pi 4 datasheet, table 5
            |
            v
   "what can this pin actually             Pi 4 datasheet, table 3
    drive, and at what voltage?"           ... and nothing, for a Pi 3

                                           ^
                                           |
                             one document, for the other board
```

The arrow at the bottom is the honest summary of fourteen projects. Every
question above it has a source. The last one has a source for one of the
two hosts, and the bench has been quietly using it for both.

**The shape of it.** A board-level document tells you what the product is.
A SoC document tells you what a pin can be. Only one of these four tells
you what a pin can drive, and it is the one for the other board. There is
no document on this bench that states the electrical characteristics of a
Raspberry Pi 3 GPIO, and the honest thing is to say so in the places that
depend on it rather than to quietly borrow the Pi 4's numbers.

### The ESP8266 programmer, and why it is not a drop-in console adapter

Evidence: `datasheet` and `vendor page`, both read Tuesday 6 October 2026,
and **both silent on the pinout**. The manual is four pages, the datasheet
is one, and the product page has neither. What they do give:

- the socket takes an **ESP-01**, so its holes are the ESP-01's pins
- there is a slide switch with **`Prog` and `UART` positions**, and
  anything other than flashing wants `UART`
- there are no broken out header pins, only the 2x4 socket, so reaching
  another board needs male-to-female jumpers

What is **`NOT READ`**: which end of the socket is pin 1. That cannot be
inferred safely, because the far-end pair is RX and VCC, and putting VCC
onto a Raspberry Pi GPIO that is driving low is a short. **Read the
silkscreen before using this board as a bridge.**

**And there is a better option on this bench.** The SIM7600E-H 4G HAT
carries a CP2102 and a documented jumper position that connects it to
the Raspberry Pi's own UART. It seats on the header in one orientation
with no loose lead to misplace, which removes exactly the hazard that
disqualified this programmer. See
[project 15's hardware page](../projects/15-lte-router/docs/hardware.md).

## HATs and 40-pin boards

**The exclusivity rule: one HAT at a time.** These all take the whole
40-pin header, so a project needing two of them needs two Raspberry Pis.

| HAT | Evidence | Notes |
|---|---|---|
| SIM7600E-H 4G HAT | `datasheet` and `vendor page` | Project 15, fully read in [its hardware page](../projects/15-lte-router/docs/hardware.md). **Carries a CP2102 and a jumper position that makes it a console adapter for the Pi.** Its two vendor documents give opposite PWRKEY polarities |
| SIM7070G Cat-M/NB-IoT/GPRS HAT | `vendor page` | Project 16, in [its hardware page](../projects/16-nbiot-tracker/docs/hardware.md). **Its host logic voltage is set by a 0 ohm resistor, not a jumper**, and the wiki does not say which way the factory fitted it. No pin table, no PWRKEY polarity, no flight mode pin, no peak current |
| SIM7020E NB-IoT HAT | `NOT READ` | |
| MCC 118 DAQ HAT | `datasheet` | 12-bit, 8 single-ended inputs, +/-10 V fixed range, 1 Mohm, 150 kHz bandwidth, 100 kS/s **aggregate across configured channels**, 7168 sample FIFO, 0 to 55 C. Uses GPIO 8, 9, 10, 11 for SPI on CE0, `ID_SD` and `ID_SC`, and GPIO 12, 13, 26 for the board address. **Its datasheet states no accuracy for its own scan clock.** Fully read in [project 8's hardware page](../projects/08-preempt-rt/docs/hardware.md) |
| Joy-it RB-Explorer700, DIV56316 | `datasheet` | fully mapped in [project 6's pin map](../projects/06-explorer700/docs/pin-map.md), including three places where the manual contradicts itself about one sensor |
| Waveshare 3.5 inch RPi LCD (A) | `NOT READ` | Project 7 |
| Waveshare RS232/RS485/CAN/CAN FD, WS-28164 | `schematic` | see below |

### WS-28164, read from Waveshare's wiki and schematic

Read Tuesday 6 October 2026. There is no separate manual: the wiki is the
manual.

`https://www.waveshare.com/wiki/RS232-RS485-CAN-Board`
`https://files.waveshare.com/wiki/RS232-RS485-CAN-Board/RS232_RS485_CAN_Board_Sch.pdf`

**It carries two CAN controllers, not one**, which corrected an earlier
reading here:

| Channel | Controller | Transceiver | Bus | Interrupt | Crystal |
|---|---|---|---|---|---|
| CAN FD | MCP2518FD | MCP2562FD | SPI0 chip select 1 | GPIO24 | 40 MHz, Y2 |
| classic CAN | MCP2515 | SN65HVD230 | SPI0 chip select 0 | GPIO23 | 16 MHz |

So the Pi never supplies a CAN controller, and the classic channel has its
own SN65HVD230 already, separate from the loose module. The wiki's whole
tested config block:

    dtparam=spi=on
    dtoverlay=i2c0
    dtoverlay=spi1-3cs
    dtoverlay=sc16is752-spi1,int_pin=25
    dtoverlay=mcp2515,spi0-0,oscillator=16000000,interrupt=23
    dtoverlay=mcp251xfd,spi0-1,interrupt=24

For CAN FD alone the first and last are enough, and leaving the middle
four out of a first bring-up means a failure has one place to be.

Two cautions. **Both channels can fit a 120 ohm termination resistor
selected by a jumper cap, and the wiki does not name the jumper**, so read
the reference designator off the schematic rather than assuming either is
fitted. And **Waveshare specify Pi 4B and Pi 5 only**, so whether it works
on a Pi 3 is `NOT READ` and untested here.

## ST sensor boards

All four are on the bench. An earlier version of the bench notes said they
were not, and three project decisions were made on that false premise;
they were corrected on Wednesday 30 September 2026.

| Board | Part | Form factor |
|---|---|---|
| X-NUCLEO-IKS4A1 | motion and environmental sensors | Arduino shield |
| X-NUCLEO-IKS5A1 | motion and environmental sensors | Arduino shield |
| X-NUCLEO-53L8A1 | VL53L8CX, 8x8 multizone time of flight | Arduino shield |
| STEVAL-STWINBX1, the STWIN.box | sensor node | USB-C device, not a shield and not a HAT |

The three shields stack on the NUCLEO-H7A3ZI-Q one at a time, or go to a
Raspberry Pi I2C bus on flying leads.

**Datasheet status: `NOT READ`, with a reason.** st.com serves no PDF to
the authoring laptop. ST's own header repositories on GitHub carry the
register definitions and are the working substitute; see the bench notes
on that. Anything in a project document that quotes an ST register layout
should say which header file it came from.

**One live constraint on the VL53L8CX**, and it is a licence rather than a
part: it needs ST's ULD, `STSW-IMG040`, which is a licence-gated download,
and the specified tests link it. That is why project 11 was retargeted,
and it is the one of its two stated reasons that survived.

## Loose parts

### DFRobot SEN0032, triple-axis ADXL345

Digi-Key 1738-1067-ND. Settled from **the vendor's schematic** on Tuesday
6 October 2026, deliberately not from another maker's ADXL345 breakout,
because both the pad order and the supply arrangement vary between makers.

**Silkscreen pad order**, from the end opposite the mounting hole toward
it, with SCL beside the hole and the axis legend:

    GND  VCC  CS  INT1  INT2  SDO  SDA  SCL

**The schematic's J1 numbering is not that order.** J1 pin 1 is VCC, pin 2
is CS, and GND is the unlabelled end pin. Following J1 puts the supply one
pad out. **Use the silkscreen.**

**For I2C at address 0x53: CS tied high, SDO tied low.** CS floating
leaves the part in four-wire mode; SDO floating leaves the address
undefined. Both are easy to omit and neither announces itself.

**The two vendor pages disagree about the supply and both are right.** The
product page says 2.0 to 3.6 V, which is the ADXL345 die's range. The wiki
says 3.3 to 6 V, which is the module's, because `U2` is a **BL8555-30**
regulator with the header's VCC on its input and the die on its 3.0 V
output.

**The digital pins have no margin and 5 V logic would destroy them.** CS,
SDO, SDA and SCL run from the header straight to the die with no level
shifter, so the 3.3 to 6 V figure applies to VCC alone. The ADXL345's
absolute maximum on a digital pin is VDD I/O plus 0.3 V or 3.6 V,
whichever is less. With VDD I/O at 3.0 V that is **3.3 V**, so a 3.3 V
host sits exactly at the limit and nothing about the supply changes it.

**The module carries no resistors at all.** The schematic's complete
component list is `U` the ADXL345, `U2` the BL8555-30, `C1`, `C3` and `C4`
at 104P, `C2` at 4.7 uF, and the header `J1`. No pull-up on SDA, none on
SCL, none on CS or SDO. A two-wire bus built from this module has only the
host's internal pull-ups, around 40 kOhm on an STM32, and there are no
loose resistors on this bench to add any.

**Two things about wiring it that are not in any datasheet**, both learned
the hard way on Tuesday 6 October 2026:

- **Take its VCC straight to the host's 3V3 pin, not through a breadboard
  power rail.** The module read nothing, then intermittently, until its
  supply came directly from the Nucleo's `+3V3`. This is worth
  generalising: **a supply rail is the one conductor that bus-based
  continuity tests cannot check.** Tying a signal row to the ground row
  proves the signal and ground leads and says nothing about the rail.
- **Its header is not soldered, so every connection is a friction
  contact.** The module has bare plated holes. The working arrangement is
  male pins pushed through the holes and down into a breadboard, so the
  breadboard's spring holds each pin against its hole wall. Assume in
  every step that any one of the six contacts can be open at any moment,
  and that "the connections are in place" means positioned, not
  conducting. An intermittent VCC here does more than go quiet: the
  ADXL345's protection diodes clamp SDA and SCL toward its dead rail and
  take other devices on the same bus down with it, which was observed.

**It is a known good part**, confirmed Tuesday 6 October 2026, read
successfully before on a Raspberry Pi. So a silent SEN0032 is a wiring or
contact question and never a dead part question. **A soldering iron and
one 8-pin 2.54 mm male header would close this permanently**, and there is
no soldering iron on this bench.

### SN65HVD230 CAN transceiver board

Loop delay from **TI SLOS346O**, which project work on transmitter delay
compensation needs. With the slope control pin tied to ground: recessive
to dominant 70 ns typical and 115 ns maximum; dominant to recessive 100 ns
typical and 135 ns maximum. A 10 kOhm resistor to ground raises those to
about 105 and 155 ns, and 100 kOhm to about 535 and 830 ns. Rated
signalling rate is **1 Mbit/s** with no bit rate switch, which is why a
bus with this part at one end cannot demonstrate CAN FD's two speeds.

**The slope control pin pulled high is standby**, which is the usual
reason one of these looks dead while every register reads correctly.

### Adafruit VL53L4CD, ADA5396

Single zone time of flight, 1 to 1300 mm, I2C. **Not** the VL53L8CX and
not an 8x8 array. A second, simpler ranging option beside the
X-NUCLEO-53L8A1 rather than a replacement for it. Datasheet `NOT READ`.

### Joy-it LinkerKit LK-LED10 modules

There are **four: blue, green, yellow and red**, 10 mm, each with a fitted
resistor `R1`. They mate with ordinary 2.54 mm Dupont jumpers: the module
carries a 2.54 mm male header for `S1`, `S2`, `U` and `G` beside the white
2.0 mm LinkerKit housing.

**That last sentence was wrong here for a long time**, and it is worth
saying why. The notes previously claimed the 2.0 mm socket could not take
Dupont jumpers and that a special cable or a soldered pigtail was needed.
That belief is why project 1 deferred its LED output after driving three
pins into open air, why project 4 deferred three status LEDs, and why
project 9 was designed around bare LEDs and resistors that are not on this
bench. **Nothing was ever missing.** A photograph settled it, and it is
committed at
[`projects/01-yocto-image/docs/figures/leds-lit.jpg`](../projects/01-yocto-image/docs/figures/leds-lit.jpg).

**Measured Friday 2 October 2026** on a Raspberry Pi 3 Model B Rev 1.2,
gpiochip0, pinctrl-bcm2835, 54 lines, libgpiod v2.2.1: the signal pin is
the **anode** side, so the header pin **sources**, a pin driven **high is
lit**, low is dark, and a line released to an input is dark and reads low.
**The module needs signal and ground only**: one module had `U` wired and
lit identically with that jumper pulled. Which way round the LED sits is
not printed on the board, so test one module before wiring three: drive
high, drive low, release.

**Measured with the nRF PPK2 on Saturday 3 October 2026**, each module
alone on the source meter, `S1` to VOUT and `G` to GND, window on the lit
stretch:

| | blue | green | yellow | red |
|---|---|---|---|---|
| at 5.000 V | 9.81 mA | 15.98 mA | 13.10 mA | 13.16 mA |
| at 3.300 V | 2.94 mA | 7.39 mA | 6.20 mA | 6.34 mA |
| effective R | 247 ohm | 198 ohm | 246 ohm | 249 ohm |
| derived Vf | 2.57 V | 1.84 V | 1.77 V | 1.72 V |

**These are the instrument's readout, not four significant figures of
accuracy.** This paragraph said plus or minus 20 per cent until Wednesday
7 October 2026, taken from Nordic's overview page. **The user guide's own
Table 9, page 17, is more specific and kinder:** 10 per cent accuracy with
a 2 per cent offset for everything from 100 nA to 50 mA, and 15 per cent
with a 5 per cent offset from 50 mA to 1 A. Every value in the table above
lies between 2.94 mA and 15.98 mA, so **all of them carry 10 per cent**,
and the derived resistance and forward voltage inherit it. The comparison
between the four modules is still sound, because they were measured the
same way on the same instrument within minutes; it is the absolute values
that should not be read as precise. Source: Power Profiler Kit II v1.0.1
User Guide, document 4461_012, Nordic Semiconductor, read Wednesday 7
October 2026.

The fraction kept at 3.3 V is `(3.3 - Vf) / (5 - Vf)` and matches all
four. **This green is the old low-forward-voltage type**, not an InGaN
green, so it sits with yellow and red; a prediction that put it beside
blue was wrong. Three modules share an effective resistance near 247 ohm
and green is 198, most likely a different fitted resistor. Three on a Pi
together draw 16.5 mA at 3.3 V.

## Instruments

| Instrument | On the bench | What it does and does not do |
|---|---|---|
| nRF PPK2, Power Profiler Kit II | yes | ampere meter, or source meter from 0.8 to 5.0 V, 100 kS/s, resolution 0.2 microamp to 1 mA by range. **Maximum DUT current is 1 A in ampere meter mode and 600 mA in source meter mode** (user guide Table 7, page 16). **Accuracy is 10 per cent up to 50 mA and 15 per cent above it** (Table 9, page 17), not the 20 per cent the overview page advertises. Logic port `VCC` is 1.65 V to 5.5 V (Table 6, page 16) and D0 to D7 are sampled at 100 kHz with a 50 kHz bandwidth (section 8.3.4, page 17). Its own operating range is 5 to 40 C, the narrowest on this bench. It measures current and sources a voltage, and **cannot read the voltage at an arbitrary node**, which is `inferred` rather than stated. Fully worked through in [project 3's hardware page](../projects/03-boot-energy/docs/hardware.md) |
| multimeter | **no** | the single purchase that unblocks the most acceptance tests |
| signal generator | no | would give the MCC 118 an external scan clock with a known accuracy, which is the only way to put a number on project 8's time base |
| oscilloscope | no | |
| logic analyser | no | |
| soldering iron | no | |

**The multimeter is the thing to buy next.** It is the only way one kit
lab reaches a recorded pass at all, because that test asks for an
independent reading to disagree with the instrument under test, and the
DAQ HAT cannot stand in for the second instrument when the whole point is
independence. It also closes the SEN0032's friction-contact question and
would have shortened the Project 9 console afternoon considerably.

Having no voltmeter is why several acceptance rows read "unmeasured, no
instrument" rather than being filled in. **That is a finding in the table,
not a gap**, and the rows say so.

## Where to go next

- **Each project's own `docs/hardware.md`**, indexed at the top of this
  page. All twenty exist as of Wednesday 7 October 2026.
- [Project 6's pin map](../projects/06-explorer700/docs/pin-map.md) is the
  worked example of this page's evidence discipline, and the best thing to
  read before writing a new one.
- Each project's `docs/DESIGN.md` carries its own ownership table, which
  is the thing that catches two managers on one resource.
- [`docs/CARD.md`](CARD.md) covers flashing and the boot partition;
  [`docs/BUILD-HOST.md`](BUILD-HOST.md) covers the build machines.

If something here turns out to be wrong, the thing to do is not to patch
around it in a project document. Fix it here, say what the old claim was,
and name what it cost, in the way the LED section above does. Three of
this page's facts were once confidently wrong, and each one quietly shaped
a project design before anybody noticed.
