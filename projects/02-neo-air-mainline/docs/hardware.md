# Hardware sources for project 2

[docs/DESIGN.md](DESIGN.md) carries the boot chain, the console wiring,
the bench layout and the flashing state machine. **This page does not
repeat any of that.** It records where the hardware claims come from, what
the vendor's page confirms, what it does not say at all, and one number
that changes how project 3 should be read.

Evidence levels: [docs/HARDWARE.md](../../../docs/HARDWARE.md). Source
index: [docs/DATASHEETS.md](../../../docs/DATASHEETS.md).

## What has been read, and what has not

| Document | Evidence | Status |
|---|---|---|
| FriendlyELEC wiki, "NanoPi NEO Air", last modified 14 November 2023 | `vendor page` | **read Wednesday 7 October 2026** |
| Schematic NanoPi-NEO-Air V1.1 1708, thirteen sheets, 13 October 2017 | `schematic` | **read Friday 9 October 2026** |
| Allwinner H3 datasheet Rev 1.2 | `datasheet` | **`NOT READ`** |

The ordering is deliberate and it is the opposite of the ordering used on
the ADXL345 module, where the schematic came first. Here the wiki is the
only one of the three that is reachable as text, and it turned out to
carry the one figure that mattered.

## What the wiki states

**Source: FriendlyELEC wiki, "NanoPi NEO Air", last modified 14 November
2023.** Read Wednesday 7 October 2026.

| Specification | Value |
|---|---|
| CPU | Allwinner H3, quad core Cortex-A7, up to 1.2 GHz |
| RAM | 512 MB DDR3 |
| storage | 8 GB eMMC, plus one microSD slot |
| wireless | 802.11 b/g/n Wi-Fi, Bluetooth 4.0 dual mode |
| camera | DVP, 24 pin FPC seat at 0.5 mm pitch, up to 5 megapixel modules |
| micro USB | OTG **and** power input, on the one connector |
| power supply | DC 5 V / 2 A, **input range 4.7 V to 5.6 V** |
| working temperature | -20 C to 70 C |
| PCB size | 40 mm by 40 mm |
| weight | 7.5 g without pin headers |

## The number that changes how project 3 should be read

**The stated input range is 4.7 V to 5.6 V.** Not "5 V", not "5 V plus or
minus ten per cent", which would be 4.5 V to 5.5 V. The low end is 4.7 V
and that is tighter than the habit.

Project 3 measures boot energy with **the nRF PPK2 as the supply**, with
the micro USB port empty, feeding the board through the header. The PPK2's
source meter tops out at **5.0 V** (its user guide, read Tuesday 6 October
2026, states 0.8 V to 5.0 V). So the measuring rig starts the board at the
very top of what the instrument can do and only **300 mV above the bottom
of what the board accepts**, before any drop in the leads, the connector
or the instrument's own output impedance at an inrush.

That is not a verdict. It is a thing to check, and **the obvious way to
check it is not available on this bench.** The PPK2 sets an output voltage
and measures current; it does not measure the voltage present at the
board. Project 3's own `DESIGN.md` says exactly that, and there is no
multimeter here. So the direct reading cannot be taken.

What can be done without a voltmeter:

1. set the PPK2 source to 5.0 V deliberately, and record that it was 5.0 V
   rather than a round 5 V chosen by habit
2. keep the supply leads short, which project 3 already does because the
   drop biases the energy figure, and which is now **also a validity
   requirement** rather than only an accuracy one
3. look in the recorded current trace for the signature of a board that
   browned out and restarted: a second inrush peak, or a boot that begins
   twice
4. read the console log for a repeated banner, which is the same event
   seen from the other side

**And then say which it was.** If none of those four shows anything, the
honest sentence is that no brown-start was observed, not that the board
stayed above 4.7 V. Those are different claims and this bench cannot yet
make the second one. It is one more row in the case for buying a
multimeter.

**What is new here is not the drop, it is what the drop now threatens.**
Project 3 already names the lead drop as a systematic error in `E`,
because the energy figure assumes 5.0 V at the header. With 4.7 V known to
be the floor, the same tens of millivolts are also a question about
whether the device under test stayed inside its specification while being
measured. One number turned an accuracy footnote into a validity
condition, which is a fair return on reading a wiki page.

**Why this was not noticed before.** The DESIGN.md rule says never power
through the header while micro USB is connected, which is about having one
source rather than two. It is a good rule and it is about the wrong
hazard. The second hazard is that the one source you are left with is
weaker, and nothing in the project said what the board needs. Now
something does.

## The debug header, confirmed by the vendor

`DESIGN.md` Figure 2 has carried this four pin table since the project was
written. The wiki now confirms it:

| Pin | Wiki name | What DESIGN.md calls it | Agreement |
|---|---|---|---|
| 1 | GND | GND | yes |
| 2 | VDD_5V | 5 V, not connected, taped back | yes |
| 3 | UART_TXD0/GPIOA4 | TX, to the cable's white RX lead | yes |
| 4 | UART_RXD0/GPIOA5/PWM0 | RX, to the cable's green TX lead | yes |

Two things the confirmation adds.

**Pin 4 is also PWM0.** On a board whose debug console is its only way in
when the network is not up, the receive pin doubles as a pulse width
output. Nothing here configures it that way, and that is worth keeping
true: a device tree that claims PWM0 takes the console's receive line with
it, and the symptom is a console that prints and cannot be typed into,
which is a slow thing to diagnose from the outside.

**The wiki does not state a baud rate.** `DESIGN.md` says 115200 8N1 and
is right, but the basis is not a document: it is
[`bootlog-sd.txt`](bootlog-sd.txt) and
[`bootlog-emmc.txt`](bootlog-emmc.txt) in this directory being legible
text rather than noise. That is `measured`, which is a stronger evidence
level than `vendor page`, and it should be labelled as what it is rather
than passed off as specified.

## The 24 pin header, and the resemblance that could cost a board

Full table, from the wiki.

| Pin | Name | Linux gpio | | Pin | Name | Linux gpio |
|---|---|---|---|---|---|---|
| 1 | SYS_3.3V | | | 2 | VDD_5V | |
| 3 | I2C0_SDA / GPIOA12 | | | 4 | VDD_5V | |
| 5 | I2C0_SCL / GPIOA11 | | | 6 | GND | |
| 7 | GPIOG11 | 203 | | 8 | UART1_TX / GPIOG6 | 198 |
| 9 | GND | | | 10 | UART1_RX / GPIOG7 | 199 |
| 11 | UART2_TX / GPIOA0 | 0 | | 12 | GPIOA6 | 6 |
| 13 | UART2_RTS / GPIOA2 | 2 | | 14 | GND | |
| 15 | UART2_CTS / GPIOA3 | 3 | | 16 | UART1_RTS / GPIOG8 | 200 |
| 17 | SYS_3.3V | | | 18 | UART1_CTS / GPIOG9 | 201 |
| 19 | SPI0_MOSI / GPIOC0 | 64 | | 20 | GND | |
| 21 | SPI0_MISO / GPIOC1 | 65 | | 22 | UART2_RX / GPIOA1 | 1 |
| 23 | SPI0_CLK / GPIOC2 | 66 | | 24 | SPI0_CS / GPIOC3 | 67 |

**Now put that beside a Raspberry Pi header.** Pin 1 is 3.3 V on both.
Pins 2 and 4 are 5 V on both. Pins 6, 9, 14 and 20 are ground on both. Pin
17 is 3.3 V on both. I2C sits on pins 3 and 5 on both. A UART sits on pins
8 and 10 on both. SPI sits on 19, 21, 23 and 24 on both, in the same
order: MOSI, MISO, clock, chip select.

That is eighteen of twenty four pins agreeing, which is not an accident.
Evidence level `inferred`, because FriendlyELEC's page does not claim
compatibility anywhere that was read; the inference is from laying the two
tables side by side.

**And here is why the resemblance is the dangerous part.**

```
    Raspberry Pi 40 pin              NanoPi NEO Air 24 pin

      1  3V3    5V    2                1  3V3    5V    2
      3  GPIO2  5V    4                3  I2C0   5V    4
      5  GPIO3  GND   6                5  I2C0   GND   6
      7  GPIO4  TXD0  8                7  GPIOG11 UART1_TX  8
      9  GND    RXD0  10               9  GND    UART1_RX   10
     ...                              ...
     23  SCLK   CE0   24              23  SPI0_CLK SPI0_CS  24
     25  GND    ...   26               -- nothing here at all --
     ...
     39  GND    GPIO21 40
```

- the header is **24 pins, not 40**. A HAT seated on it hangs over the
  edge of the board, and every pin a HAT uses above 24 is simply absent
- the UART on pins 8 and 10 is **UART1**, not UART0. The console is not
  here; it is on the separate four pin debug header
- the GPIO numbering is Allwinner's, in banks: `GPIOG11` is Linux gpio
  203, not 11. Any script carrying a Raspberry Pi pin number writes to a
  different pin, silently
- there is no HAT identification EEPROM and no pins reserved for one

So the rule for this board is the inverse of the usual one: **the things
that look the same are the same, and the things that look similar are
not.** Power and ground can be trusted across the two boards. Nothing that
carries a signal can.

## The 12 pin header is a USB breakout, and should be treated as one

| Pin | Name | Note |
|---|---|---|
| 1 | VDD_5V | **5 V out** |
| 2, 3 | USB-DP2, USB-DM2 | second USB port, raw differential pair |
| 4, 5 | USB-DP3, USB-DM3 | third USB port, raw differential pair |
| 6 | GPIOL11 / IR-RX | |
| 7 | SPDIF-OUT / GPIOA17 | |
| 8 to 11 | PCM0 and I2S0 lines | sync, clock, data out, data in |
| 12 | GND | 0 V |

Pin 1 is 5 V and pin 12 is ground, at opposite ends of a twelve pin
double row. A jumper placed one row out at the wrong end is a short across
the supply. **Nothing in this project uses this header**, and the right
treatment for an unused header carrying a supply is to say so in writing
rather than to leave it unmentioned, which reads as "nobody checked".

## What the wiki does not say, and what has since answered it

| Question | Why it matters | Status |
|---|---|---|
| the Wi-Fi and Bluetooth part number | the driver and the firmware blob depend on it | **closed Friday 9 October 2026**: `AP6212`, from the schematic |
| the antenna connector type | `DESIGN.md` requires the antenna attached before first power | **closed Friday 9 October 2026**: one `IPX` connector, `ANT1`, shared by both radios |
| current drawn, idle or peak | project 3 measures this, so it has no figure to be checked against | open; nowhere, and it is a measurement this bench can make |
| GPIO voltage thresholds and drive | the same gap as on the Raspberry Pi 3 | open; the Allwinner H3 datasheet, `NOT READ` |
| the console baud rate | established by measurement here, not by document | open, and no document will close it |

**The second row said it was the one to close first and that it needed no
document.** That was half right: a photograph would have done it, and so
did the schematic, which arrived first. The rule in `DESIGN.md` is right
for a good reason, that running a transmitter into an open circuit is
avoidable, and it could not previously be checked by anyone who had not
already seen the board. Now it can, because the connector has a name.

**And the fourth row's phrasing is now wrong in an instructive way.** It
calls the GPIO gap "the same gap as on the Raspberry Pi 3". The Raspberry
Pi 3 gap turned out not to exist: the figures are in the GPIO section of
Raspberry Pi's documentation, as
[docs/HARDWARE.md](../../../docs/HARDWARE.md) records. **The NEO Air gap
is real**, and the lesson from the Raspberry Pi applies to it anyway:
before concluding a fact is unpublished, check that the search was for the
fact and not for a document type.

## The schematic is read, and it closes three of the four open rows

**Source: FriendlyELEC, "NanoPi NEO Air", schematic revision V1.1 1708,
thirteen sheets, title block dated Friday 13 October 2017.** Read Friday
9 October 2026, from the URL Joseph supplied that day.

Its own revision history, on sheet 1:

| Revision | Change |
|---|---|
| 1608 | first release |
| 18 May 2017 | rename net `PWM1/GPIOA6` to `GPIOA6` |
| 1708 | change the TF card; add the 2.54 mm audio header |

**The first of those is worth noticing**, because it means the board on
this bench may have `PWM1` on that net or may not, depending on which
revision it is. The wiki's 24 pin table lists pin 12 as `GPIOA6` with no
PWM, which matches 1708.

### The Wi-Fi part, which the wiki would not name

**`U19` is an `AP6212`**, on sheet 13, whose title block names the sheet
"14:AP6212". The block diagram on sheet 2 says the same, with the part
sitting on the H3's `SDIO`.

That closes the first row of this page's open table. The wiki gives
"802.11 b/g/n" and "Bluetooth 4.0 dual mode" and never names the chip;
the schematic names it twice.

**It also explains the architecture.** One part carries both radios: the
Wi-Fi side goes to the H3 over **SDIO**, four data lines plus clock and
command, with `R145`, a 22 ohm series resistor, on the clock. The
Bluetooth side goes over **UART3**, with hardware flow control, plus a
`PCM` group for audio.

### Bluetooth has its own UART here, which is the opposite of project 9

This is the finding worth carrying off this board.

On a Raspberry Pi, Bluetooth takes the PL011, which is why `disable-bt`
exists and why [project 9](../../09-kernel-debug/docs/hardware.md) spent
an evening on a console that was never muxed.

**On the NEO Air there is no such contest.** Sheet 13 wires the AP6212's
Bluetooth to **`UART3_TX`, `UART3_RX`, `UART3_RTS` and `UART3_CTS`**. The
debug console is on **`UART0`**, on its own four pin header. Two different
peripherals, two different pin groups, nothing to disable.

**So a serial console and working Bluetooth coexist on this board without
a device tree argument**, which is not true of any Raspberry Pi here. If
project 17's BLE gateway ever wanted a host whose console is not in
tension with its radio, this is that host.

### The antenna connector is `IPX`, and there is one of it

Sheet 13: **`ANT1`, an `IPX` connector**, its signal pin carrying the net
`WL_BT_ANT` from pin 2 of the AP6212, with its two shield tabs to ground.

Two things follow, and both matter for the rule in `DESIGN.md` that the
antenna is attached before the board is first powered.

1. **`IPX` is the U.FL-compatible miniature coaxial family.** It mates by
   pressing straight down, it is rated for very few mating cycles, and it
   is removed by lifting vertically with a proper tool or by the plug
   body, never by pulling the cable.
2. **There is exactly one connector and it is shared.** The net is
   `WL_BT_ANT`: Wi-Fi and Bluetooth come out of the same pin into the same
   antenna. So the rule protects both radios at once, and there is no
   second connector anybody could mistake it for.

**That closes the second open row**, and it does so in a way that was
asked for: this page said the rule "cannot be checked by anyone who has
not already seen the board". Now it can. The connector has a name, a
designator and a count.

### The rails, and one number project 3 should have

Sheet 8, "POWER 02": `VDD_SYS_3.3V` is generated from `VDD_5V` by **`U6`,
an `RT8059` switching regulator**, with the net annotated **3.3 V / 1 A**.

So the 3.3 V that reaches the 24 pin header's pins 1 and 17, and every
sensor hung off it, comes from a 1 A buck converter rather than from the
input directly.

**The micro USB input is protected, but differently from a Raspberry
Pi's.** Sheet 8 shows the connector's lines going through four
`AVRL5V0A5R1KTB` parts, which are 5 V chip varistors, and then `VDD_5V` is
reached through `Q1`, an `AO3415A` P-channel MOSFET, with a `BCM856BS`
transistor pair and 10 kohm resistors around it. `U5`, an `SY6280` current
limited load switch with `R241` setting the limit, sits on the `VBUS` path
driven by `GPIOL2/USB0-DRVVBUS`.

**What this page will not claim.** The Raspberry Pi's equivalent is simple
to read: one polyfuse, one transient suppressor, in series. This
arrangement is a MOSFET and two transistors whose exact function, ideal
diode, reverse polarity protection, OTG VBUS switching, or some
combination, **is not something a page-resolution read of one sheet
settles**. What is certain is that varistors are present on the connector
and that the path to `VDD_5V` is active rather than a plain wire.

**For project 3, which feeds `VDD_5V` at header pin 2**, the practical
consequence is the same shape as on the Raspberry Pi: that supply enters
**after** whatever the micro USB path does, not through it. Evidence level
`inferred`, from net naming across two sheets.

### Both headers confirmed, net by net

Sheet 10 draws `CON1`, the 24 pin header, and `CON2`, the 12 pin header,
with every net labelled. **Every row of the wiki's two tables, which this
page reproduced on Wednesday 7 October 2026, appears on the schematic
under the same name.** `I2C0_SDA` and `I2C0_SCL` on pins 3 and 5,
`GPIOG11` on 7, `UART1_TX/GPIOG6` and `UART1_RX/GPIOG7` on 8 and 10, the
`UART2` group, the `SPI0` group on 19, 21, 23 and 24, and `VDD_SYS_3.3V`
on pin 1 with `VDD_5V` on pin 2.

**A vendor page confirmed by that vendor's own schematic is the strongest
agreement available short of a measurement**, and it is worth saying so
rather than quietly upgrading the evidence column.

**One thing could not be resolved.** The connector's footprint annotation
beside `CON1` read as `HDR-2.54mm-2x13P` at page resolution, which would
be twenty six positions, while the drawn pins run 1 to 24 and the wiki
lists twenty four. Either the annotation is `2x12P` and was misread, or
there are two unused positions. **Counting the pins on the board settles
it in a second** and nothing depends on the answer.

### The debug header, confirmed a third time

Sheet 10's `DBG` block shows `GND`, `VDD_5V`, `UART0_TX` and `UART0_RX`,
in that order, with `R98`, a 4.7 kohm resistor, on the receive side.

So the four pin table in `DESIGN.md` Figure 2 is now confirmed by the
wiki **and** by the schematic, and the schematic adds the series resistor
the wiki does not mention.

**The pin 2 warning on this page stands undisturbed**, and is now sourced
from the drawing as well: pin 2 is `VDD_5V` and pins 3 and 4 are UART0 at
3.3 V. The red lead stays taped.

### Both LEDs are GPIO driven, and the schematic says which GPIO

Sheet 11:

| LED | Colour | Net | Resistor |
|---|---|---|---|
| `PWR` | red | `GPIOL10/PWR-LED` | `R206`, 1 kohm, from `VDD_SYS_3.3V` |
| `STAT` | green | `GPIOA10/STATUS-LED` | `R203`, 1 kohm, from the same rail |

**Compare this with the Raspberry Pi.** Project 19's page records that the
Pi 3B+ schematic shows its two LEDs switched by transistors from nets
called `STATUS_LED_R` and `STATUS_LED_G`, and that **where those nets
originate was not legible**. Here the equivalent question is answered on
the face of the drawing: the green LED is driven by `GPIOA10` and nothing
else.

**So on this board a beating status LED is a GPIO being toggled**, and the
software that toggles it can be found. That is a stronger statement than
anything available for the Raspberry Pi, and it is available because
FriendlyELEC publishes a full schematic where Raspberry Pi publishes a
reduced one.

**And it is directly useful to project 3**, which hangs an LK-LED10 on the
board as a visible marker. There is already a GPIO driven green LED on
`GPIOA10`. Whether to use it instead of a module is a design question this
page does not settle; what it removes is the assumption that the board had
no such LED.

### What is still `NOT READ`

| Document | What it would settle |
|---|---|
| Allwinner H3 datasheet | the GPIO voltage thresholds and drive currents, which no FriendlyELEC document gives. Joseph supplied four mirror URLs on Friday 9 October 2026 |
| AP6212 datasheet | the radio's own supply and timing, and whether `WIFI_32K` on `LPO` is required or optional |

**Everything else on this page's open list is closed.** The Wi-Fi part is
named, the antenna connector is named, and the current consumption remains
what it always was: a measurement this bench can make rather than a
document to find.

## Reflections on the wiring, and on not rewiring it

**The red lead is taped, and the tape is the design.** `DESIGN.md` does not
merely leave pin 2 unconnected; the cable's red lead is physically taped
back so it cannot be the lead that finds a pin. That is a decision worth
defending out loud, because it looks like fussiness and is not: pin 2 is
5 V, pins 3 and 4 are 3.3 V logic with nothing in between, and a connector
seated one position out is the ordinary failure, not the exotic one.
**The tape converts a mistake that destroys a board into a mistake that
does nothing.**

**Nothing here has been rewired, and that is the finding.** Across this
bench, the wiring that has caused trouble is the wiring that was changed
while a fault was being chased: project 9 spent an evening moving console
leads that were correct from the start. This board's console has been
connected the same way since the project began and has never been the
suspect. The two facts are related. A connection that is specified in a
figure, taped where it must not be used, and confirmed afterwards against
the vendor's own table, is a connection nobody needs to touch when
something else goes wrong.

**The one change worth making is to the supply, not to the signals.**
Everything above about 4.7 V is about the power lead, which is the one
conductor the console cable does not exercise and the one no continuity
check can vouch for. That is the same lesson the ADXL345 module taught in
[project 5's page](../../05-iio-adxl345/docs/hardware.md), arriving from a
completely different direction.
