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

## Boards

| Board | On the bench | Notes |
|---|---|---|
| Raspberry Pi 3 | yes | |
| Raspberry Pi 3 Model B Plus | yes | the Project 9 board, Rev 1.3 |
| Raspberry Pi 4 | yes | the only one some HATs support |
| NanoPi NEO Air | yes | Project 2's target; its supply is the instrument when the profiler is in use |
| NUCLEO-H7A3ZI-Q | yes | STM32H7A3ZI, Nucleo-144; the firmware volume's board |
| SBC-NodeMCU-ESP32 | yes | carries a CP2102 or CH340 |
| Joy-it SBC-ESP8266-PROG | yes | carries a CP2102 or CH340; **its socket pinout is published nowhere**, see below |

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

## HATs and 40-pin boards

**The exclusivity rule: one HAT at a time.** These all take the whole
40-pin header, so a project needing two of them needs two Raspberry Pis.

| HAT | Evidence | Notes |
|---|---|---|
| SIM7600E-H 4G HAT | `NOT READ` | Project 15 |
| SIM7070G Cat-M/NB-IoT/GPRS HAT | `NOT READ` | Project 16 |
| SIM7020E NB-IoT HAT | `NOT READ` | |
| MCC 118 DAQ HAT | `NOT READ` | 12-bit, 100 kS/s, 8 single-ended analog inputs |
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

The fraction kept at 3.3 V is `(3.3 - Vf) / (5 - Vf)` and matches all
four. **This green is the old low-forward-voltage type**, not an InGaN
green, so it sits with yellow and red; a prediction that put it beside
blue was wrong. Three modules share an effective resistance near 247 ohm
and green is 198, most likely a different fitted resistor. Three on a Pi
together draw 16.5 mA at 3.3 V.

## Instruments

| Instrument | On the bench | What it does and does not do |
|---|---|---|
| nRF PPK2, Power Profiler Kit II | yes | ampere meter, or source meter from 0.8 to 5.0 V up to about 1 A, over USB. It measures current and sources a voltage, and **cannot read the voltage at an arbitrary node** |
| multimeter | **no** | the single purchase that unblocks the most acceptance tests |
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
