# Hardware sources for project 15

[docs/DESIGN.md](DESIGN.md) carries the architecture, the wiring figure,
the ownership table and the watchdog state machine. **This page does not
repeat any of that.** It records which of those hardware claims are now
sourced, which are confirmed, and the one where **two documents from the
same vendor, for the same product name, state opposite polarities.**

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What has been read

| Document | Evidence | Status |
|---|---|---|
| SIM7600E-H 4G HAT user manual, Waveshare, **Rev 1.0, 8 June 2018** | `datasheet` | **read Wednesday 7 October 2026**, pages 1 to 11 |
| Waveshare wiki, SIM7600E-H 4G HAT | `vendor page` | **read Wednesday 7 October 2026** |
| SIM7600E-H module manual, SIMCom | `datasheet` | **`NOT READ`** |
| HAT schematic | `schematic` | **`NOT READ`**, and `DESIGN.md` asks for it by name twice |

## The headline finding: PWRKEY polarity is not settled, and it is revision dependent

`DESIGN.md` says of PWRKEY: "Through the jumper block. **Drive high to
press.** Confirm on the HAT schematic." It was right to flag it. Here is
what the two vendor documents say.

| Source | What it says about powering the module on automatically |
|---|---|
| user manual Rev 1.0, 8 June 2018, page 9 | connect the **PWR and GND** pins on the module header, "so that it can automatically turn on" |
| the wiki, describing the version after 2021 | "PWR and **3V3** are short-circuited by default, so the HAT is turned on automatically after connecting to the power supply" |

**Those are opposite.** Pulling a line to ground and pulling the same line
to 3.3 V cannot both assert it. Neither document mentions the other, and
neither says the behaviour changed. The only reading that makes both true
is that **the board was revised and the strap moved**, which is entirely
ordinary and entirely undocumented.

**What follows for this project.**

1. `DESIGN.md`'s "drive high to press" matches the **post-2021** board and
   not the 2018 one.
2. Which board is on this bench is **unknown from documents**. It is
   knowable in about ten seconds from the board itself: **is there a
   jumper cap between the `PWR` and `3V3` pins on the control header?**
   If yes, it is the newer revision and PWR is active high.
3. The benign failure is driving high on an older board: the modem simply
   never powers on.
4. **The failure to avoid** is mixing the two. On a newer board whose
   `PWR` pin is strapped to 3V3 by its factory jumper, driving GPIO6 high
   is harmless, but following the 2018 manual and strapping `PWR` to
   **GND** while software drives GPIO6 **high** puts a Raspberry Pi output
   directly across a short to ground. **Remove the factory jumper before
   connecting GPIO6 to `PWR` at all**, and know which strap is fitted
   before power.

This is the clearest instance yet of a rule this bench keeps rediscovering:
**a vendor page and a vendor manual are two sources, not one, and when
they disagree the disagreement is the information.**

## What the wiki confirms, pin for pin

`DESIGN.md`'s wiring table has carried these four rows with a note that
two of them were unverified. The wiki states a connection table that
matches all four.

| Signal | `DESIGN.md` | Wiki | Agreement |
|---|---|---|---|
| Pi TXD to modem RXD | header pin 8, GPIO14 | RXD to TXD, BCM 14 | yes |
| Pi RXD from modem TXD | header pin 10, GPIO15 | TXD to RXD, BCM 15 | yes |
| PWRKEY | header pin 31, GPIO6 | PWR to BCM 6 | yes |
| FLIGHT | header pin 7, GPIO4 | FLIGHTMODE to BCM 4 | yes |
| 5 V and ground | pins 2, 4, 6, 9, 14 | 5V to 5V, GND to GND | yes |

**And FLIGHT's polarity is confirmed outright.** The wiki says to pull it
high to enter flight mode. `DESIGN.md` says "High means RF off". Those are
the same statement, and that row moves from `inferred` to `vendor page`.

So of the two lines `DESIGN.md` refused to trust without a schematic, one
is now confirmed and the other turns out to be worse than unverified: it
is contested. That is a better outcome than it sounds, because the
contested one is now a question with a ten second answer rather than a
footnote.

## Current, which `DESIGN.md` guesses and the wiki partly answers

`DESIGN.md`'s figure annotates the 5 V feed as "2 A peaks". **That figure
appears in neither document**, and should be marked as what it is.

The wiki states: after the network is connected the current is generally
50 mA to 300 mA, averaging about 150 mA, "for reference only, depending on
the network environment". **Peak current is not stated anywhere that was
read.**

That matters because the peak, not the average, is what browns out a
Raspberry Pi. The manual does give the transmitter's radiated power, which
bounds it from below in a useful way:

| Mode | Emitting power, manual page 2 |
|---|---|
| LTE | 0.25 W |
| GSM900 | 2 W |
| DCS1800 | 1 W |
| EDGE, EGSM900 | 0.5 W |
| EDGE, DCS1800 | 0.4 W |

A 2 W GSM burst at 5 V is 400 mA of radiated power alone, before
efficiency, and GSM transmits in bursts at 217 Hz rather than
continuously. So a figure of the order of an amp during a 2G burst is
plausible and **"2 A peaks" remains a guess until the SIMCom module manual
is read.** `DESIGN.md`'s existing instruction, to watch `journalctl -k`
for undervoltage, is the right behaviour in the meantime and is now
backed by a reason rather than by caution alone.

## The UART selection jumper, which the wiki does not mention at all

**Manual page 5, item 21**, with the silkscreen block marked `UART JMP`
and three rows `A`, `B`, `C`:

| Position | What the manual says it does | What it connects |
|---|---|---|
| A | "access Raspberry Pi via USB to UART" | the HAT's CP2102 to the **Raspberry Pi** |
| B | "control the SIM7600 by Raspberry Pi" | the Raspberry Pi to the **modem** |
| C | "control the SIM7600 via USB to UART" | the HAT's CP2102 to the **modem** |

**Position B is the one `DESIGN.md` means** when it says "HAT jumper in the
Pi UART position" for the fallback AT channel. It now has a name and a
page.

**The wiki does not describe this jumper at all.** So between the two
documents: the wiki has the pin table and the current figures, the manual
has the jumper and the board inventory, and **neither is sufficient on its
own**. Read both.

## Position A is a known-pinout console adapter, and project 9 needs one

This is the most useful thing to come out of the manual and it has nothing
to do with LTE.

Project 9 spent an evening without a serial console. Its root cause was
the unmuxed GPIO14, recorded in
[project 9's hardware page](../../09-kernel-debug/docs/hardware.md), and
the only USB to serial adapter reached for was the Joy-it ESP8266
programmer, **whose socket pinout is published nowhere** and which this
bench therefore declined to use.

**This HAT carries a CP2102 and a jumper position that wires it to the
Raspberry Pi's own UART.** Manual page 1 lists an "Onboard CP2102 USB to
UART converter, for serial debugging" and a separate "USB TO UART" micro
USB socket, item 13 on page 4, "for serial debugging, or login to
Raspberry Pi".

```
    laptop  ---- micro USB ----> [ USB TO UART socket ]
                                        |
                                     CP2102
                                        |
                        UART JMP in position A
                                        |
                       header pins 8 and 10 of the Pi
```

**Four conditions before anyone tries it**, because this is the point at
which a good idea becomes a flat board:

1. the jumper must be in **A**, not B or C
2. the `VCCIO` jumper must be on **3.3 V**, not 5 V, because the other
   side is a Raspberry Pi GPIO
3. the HAT takes the **whole 40 pin header**, so nothing else can be on it
4. the Pi's `uart0` must actually be muxed onto GPIO14 and GPIO15, which
   is the thing project 9 had to fix in `kas/bench-debug.yml` and which no
   adapter can do for it

Evidence level for the path from the socket to header pins 8 and 10:
`inferred`. The manual says position A accesses the Raspberry Pi via USB
to UART, and a HAT reaches the Pi only through the header, so pins 8 and
10 follow. It is not drawn anywhere that was read, and the schematic is
`NOT READ`.

## What is on the board, from the manual's own inventory

Page 4 numbers twenty one items. The ones that change how this project is
reasoned about:

| Item | Part | Why it matters here |
|---|---|---|
| 1 | SIM7600E-H | the modem |
| 2 | CP2102 | USB to UART, see above |
| 3 | NAU8810 | audio decoder, unused by this project |
| 4 | **TXS0108EPWR** | voltage translator, 3.3 V or 5 V to **1.8 V** |
| 5, 6 | MP2128DT, MP1482 | the two switching regulators |
| 20 | `VCCIO` jumper | selects whether the host side is 3.3 V or 5 V |
| 21 | `UART JMP` | the three position block above |

**Item 4 is the quiet one.** The modem's own logic is 1.8 V and everything
the Raspberry Pi sees goes through a translator. That is why the `VCCIO`
jumper exists and why putting it on 5 V while a Raspberry Pi is attached
would be a mistake rather than a preference.

## Other specifications, from manual page 3

Power supply 5 V. Operating voltage 5 V or 3.3 V, by jumper. Operating
temperature -30 C to 80 C, storage -45 C to 90 C. Dimensions 56.21 mm by
65.15 mm. Default baud rate 115200, settable from 300 to 4 Mbit/s, with
autobauding from 9600 to 115200. AT commands per 3GPP TS 27.007 and
27.005 and V.25TER. SIM card 1.8 V or 3 V. Three antenna connectors: MAIN,
AUX and GNSS.

## The compatibility list, and why its silence proves nothing

Manual page 1: "compatible with Raspberry Pi Zero/Zero W/Zero WH/2B/3B/3B+".
**No Raspberry Pi 4.**

Before reading that as a limitation: the manual is **Rev 1.0, dated
8 June 2018**, and the Raspberry Pi 4 was announced in June 2019. The
document is a year older than the board it fails to mention. Its silence
is chronological, not technical.

That is worth writing down because the opposite mistake is easy and
expensive in both directions: treating an old document's silence as a
prohibition, or treating it as permission. The right reading is that **the
document has nothing to say**, and the question stays open.

## Still `NOT READ`, in the order worth closing

| Document | What it would settle |
|---|---|
| the HAT schematic | PWRKEY polarity, without needing the board; the path from `UART JMP` position A to header pins 8 and 10 |
| SIMCom SIM7600E-H module manual | peak current, which is the number `DESIGN.md` guesses at |
| the SIMCom AT command manual, named on manual page 10 as "Series_AT Command Manual_V1.07" | the exact AT set behind the watchdog's probes |

**And one thing no document will settle, which a photograph will.** Is
there a jumper cap between `PWR` and `3V3` on the control header of the
board on this bench? That single picture decides the PWRKEY polarity, and
it is the first thing to do before this project's GPIO code is run against
hardware.
