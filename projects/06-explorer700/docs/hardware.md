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
| NXP PCF8574; PCF8574A, revision 5, 27 May 2013 | `datasheet` | **read Thursday 8 October 2026** |
| Raspberry Pi 3 Model B product page | `vendor page` | **read Wednesday 7 October 2026**, and it is thin, see below |
| Raspberry Pi 4 Model B datasheet, release 1.1 | `datasheet` | **read**, and it is the nearest thing to an electrical specification this host has |
| DS3231 datasheet, the real time clock on the HAT | `datasheet` | **`NOT READ`** |
| NXP PCF8591, revision 7, 27 June 2013 | `datasheet` | **read Thursday 8 October 2026** |

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
| PCF8574 | 8-bit I2C expander | **read Thursday 8 October 2026**, revision 5 of 27 May 2013, worked through below |
| PCF8591 | 8-bit I2C ADC and DAC | **read Thursday 8 October 2026**, revision 7 of 27 June 2013, worked through below |

**The PCF8574 row was the one worth reading first, and it has now been
read.** The reasoning for putting it first was that a quasi-bidirectional
output cannot sink and source like a normal GPIO, so code that drives it
as though it could works for LEDs and fails for anything needing a strong
high. That turned out to understate it: the ratio between the two
directions is a hundred to one, and one of the two directions can damage
the part. The next section is what the datasheet says.

## The PCF8574 is read, and it is an asymmetric driver

**Source: NXP PCF8574; PCF8574A product data sheet, revision 5,
27 May 2013.** Read Thursday 8 October 2026.

This was the row this page said to read first, because a
quasi-bidirectional output is not an ordinary one. It was the right call,
and the datasheet is blunter about it than expected.

### What a pin can actually do, in two numbers

| Direction | What the part provides | Source |
|---|---|---|
| **writing 0**, pulling low | a strong sink transistor, **10 mA per bit minimum guaranteed at 5 V** | section 10.3, page 14 |
| **writing 1**, pulling high | a **weak 100 microamp current source** to VDD, plus a brief "accelerator" pull-up that is active only during the HIGH time of the acknowledge clock cycle | section 8.1, pages 6 and 7 |

**That is a ratio of a hundred to one**, and it is the whole character of
the part. The datasheet says why in its own words: the p-channel
transistor to VDD is small, which saves die area, so an LED is expected to
hang from VDD through a resistor and be sunk to ground by the expander.

**So every load on this expander is driven active low**, and that includes
the two this project binds:

| Line | Net | What follows |
|---|---|---|
| P4 | LED2 | **writing 0 lights it**, writing 1 does not, because 100 microamps will not light a 10 mm LED |
| P7 | Buzz | the same: 0 sounds it |

**That is a prediction and it can fail**, which is the point of writing it
down. `gpioset` on the expander's line 4 with value 0 and then value 1
settles it in two commands, and if the LED lights on 1 instead then
something about the board is not what this page thinks.

**Writing 0 is safe on this line and not on every line**, which the
section after next explains. P4 drives an LED, so nothing external is
pulling it high and there is nothing for the sink transistor to fight.
P5 and P6 are the lines where direction is unknown, and they are the ones
`gpioset` must stay away from.

**And it is the opposite convention to the rest of this bench.** The
LK-LED10 modules in projects 1, 4 and 9 are **sourced**: the header pin
drives high and the LED lights, as
[docs/HARDWARE.md](../../../docs/HARDWARE.md) records from a measurement
on Friday 2 October 2026. Two LED conventions on one bench, in opposite
directions, is exactly the sort of thing that produces a confident wrong
patch six months later.

### The power-on state is safe, and it is worth knowing why

Section 8.4, page 9: the internal power-on reset initialises **all I/Os as
inputs with the weak 100 microamp current source to VDD**. So every line
comes up weakly high.

For an active-low load that is **off**. For a load wired the other way it
is 100 microamps, which is also effectively off. **Either way the board
powers up quiet**, before any driver has loaded, and that is a property
worth having in a project that binds eleven peripherals through one
overlay.

### The damage mechanism behind this page's existing caution

[pin-map.md](pin-map.md) declines to bind L3 and L4 on P5 and P6, because
the manual's diagram draws arrows **out** of the expander and the part is
quasi-bidirectional so the diagram cannot settle direction. That caution
was right and it was general. The datasheet gives it a mechanism, in
section 8.1 on page 7, under **Output LOW**:

> A large current may flow into the port, which could potentially damage
> the part if the master writes a 0 to the register and an external source
> is pulling the port HIGH at the same time.

**So the hazard is specifically `gpioset ... =0` on a line something else
is driving high.** Writing 1 is harmless in every case, because a 100
microamp source loses to anything.

**Which makes `gpioget` on those two lines safe for a precise reason**,
not merely a cautious one: requesting a line as an input through
`gpio-pcf857x` writes 1 to it, which is the weak state, and then reads
what the pin actually sits at. That is exactly the probe
[BRINGUP.md](BRINGUP.md) already carries as an optional step.

**The rule, stated so it survives this page:** on this expander, reading
is always safe and writing 0 is the one move that can damage the part.
Probe with `gpioget`, never with `gpioset`.

### One number that caps the whole bus

The PCF8574 is a **100 kHz** part. Table 6 on page 14 says so, in the
migration table that offers the PCA8574 at 400 kHz as the newer
alternative.

**The slowest device sets the bus speed.** This project puts eleven
peripherals behind one overlay and several of them share I2C1. Whatever
else is on that bus, it runs at 100 kHz because this part is on it.

That is not a problem for a joystick, a buzzer and an LED. It is worth
knowing before anybody wonders why the bus is not faster, and it is the
sort of fact that is invisible until somebody reads the slowest
datasheet.

### Limits, for the before-power question

Table 7, Limiting values, page 15:

| Parameter | Limit |
|---|---|
| supply voltage | -0.5 V to +7 V |
| **input voltage** | **VSS minus 0.5 V to VDD plus 0.5 V** |
| input current | plus or minus 20 mA |
| output current | plus or minus 25 mA |
| power dissipation per output | 100 mW |
| total power dissipation | 400 mW |
| **total package sink current** | **80 mA**, Table 6 page 14 |
| ambient temperature | -40 to +85 C |

**The input voltage row is the third attestation of one form on this
bench.** The SHT4x datasheet gives the same shape, VSS minus 0.3 V to VDD
plus 0.3 V, and
[project 5's page](../../05-iio-adxl345/docs/hardware.md) carries the same
rule for the ADXL345 marked `inferred` because its datasheet is unread.
Three parts from three manufacturers state it; the ADXL345 row is still
`inferred` and should stay so until somebody reads Analog's document. **A
pattern that holds three times is a good reason to expect the fourth and
not a citation for it.**

**And the 80 mA total is a real budget, not a formality.** Section 10.3
notes that up to five pins may be tied together to drive 80 mA, which is
the device's recommended total limit, and that each pin needs its own
limiting resistor so that the part is not damaged when they are not all
turned on together. Nothing here does that. It is recorded because the
number bounds anything anybody later wants to hang off this expander.

### The address, and why the two variants cannot collide

[pin-map.md](pin-map.md) puts the expander at **0x20**, from the manual.
That is consistent with the **PCF8574**, the non-A part, with all three
address pins tied to VSS.

Table 5 on page 6, which was read, gives the **PCF8574A** range as 7-bit
**0x38 to 0x3F**. The non-A part has its own table on page 5, which was
**not read**. What the two tables establish between them is that the
variants occupy different ranges, so a PCF8574 and a PCF8574A can share
one bus, and that the address seen on a scan identifies **which variant is
fitted** as well as how its pins are strapped.

So `i2cdetect` answering at `0x20` is weak confirmation that the part is a
non-A PCF8574, which is what the manual says, and the kind of agreement
worth noting rather than assuming.

## The PCF8591 is read, and it returns the previous conversion

**Source: NXP PCF8591 8-bit A/D and D/A converter product data sheet,
revision 7, 27 June 2013.** Read Thursday 8 October 2026.

This row was listed third and it should have been second, because it
contains the one behaviour on this HAT most likely to produce a confident
wrong number.

### The pipelined read, which is the finding

**Section 8.4, page 8**, in the datasheet's own words: an A/D conversion
cycle is always started after sending a valid read mode address, it is
triggered at the trailing edge of the acknowledge clock pulse, and it

> is executed while transmitting the result of the previous conversion

Figure 8 on the same page labels the three bytes of a three byte read as
"transmission of previously converted byte", then byte 1, then byte 2.

**So the first byte you read is stale.** Not noisy, not approximate:
**it is the result of the conversion before this one.**

```
   write control byte, selecting channel 2
   read 1 byte   ->  the value of whatever channel was selected BEFORE
   read 1 byte   ->  channel 2, at last
```

**Why this is the worst kind of defect.** It does not fail. The read
succeeds, the byte is a plausible eight-bit number, and it is from the
wrong channel. Anything that selects a channel and reads once is reporting
the previous channel, every time, and the only way to notice is to change
one input and watch the wrong reading move.

**Two ways to get it right**, both cheap: read two bytes and discard the
first, or issue one priming read after selecting a channel and use the
second.

**Which of those the kernel does is a two minute check nobody has made.**
This project binds the part through `CONFIG_SENSORS_PCF8591`, set in
`meta-bench/recipes-kernel/linux/files/explorer.cfg`, with the node
`adc@48` in `bench-explorer700-overlay.dts`. That is the hwmon driver at
**`drivers/hwmon/pcf8591.c`** in the kernel tree. Whether it discards a
stale byte after a channel change is a question that file answers
outright, and the tree to read it in is on JPTOUPM678.

**Until somebody reads it, every number this part reports is unverified in
a specific way**, and that is a better statement than "the kernel probably
handles it". The driver very likely does; this repository's own history
says that "very likely" is where its wrong claims come from.

**It compounds with what [pin-map.md](pin-map.md) already says.** All four
analog inputs leave this board through a screw terminal, so unterminated
channels produce "plausible, drifting, non-zero numbers". Add a stale
first byte and there are now **two independent ways** for this part to
report a believable wrong value, from two different causes. The pin map's
rule, that `explorer-verify` reports a measurement only for a channel the
operator has declared wired, handles the first. The second needs a change
in how the read is done.

### The control byte, and what the four inputs can be

**Figure 4, page 6.** One byte, written before any read:

| Bits | Meaning |
|---|---|
| 7 | always 0 |
| 6 | analog output enable: the DAC buffer is on when this is 1 |
| 5 and 4 | **analog input programming**, four arrangements, below |
| 3 | always 0 |
| 2 | auto-increment flag, active when 1 |
| 1 and 0 | A/D channel number, 0 to 3 |

The four input arrangements:

| Bits 5 and 4 | Arrangement |
|---|---|
| `00` | **four single-ended inputs**, AIN0 to AIN3 as channels 0 to 3 |
| `01` | three differential inputs |
| `10` | two single-ended, AIN0 and AIN1, plus one differential from AIN2 and AIN3 |
| `11` | two differential inputs |

**[pin-map.md](pin-map.md)'s table assumes `00`**, four single-ended
channels mapping one to one onto the four screw terminal positions, and
that is the right default for a board that brings all four out
separately. It is worth knowing it is a **choice** written into a control
byte rather than a property of the board: the same hardware reads as two
differential pairs if a different byte is sent, and nothing physical
changes.

**And a differential reading is two's complement.** Section 8.4, page 8.
So code that treats every reading as unsigned is correct for the
single-ended arrangement this project uses and silently wrong for any
other, which is one more reason to write the arrangement down rather than
leave it implied.

### The two parts on this HAT limit each other

**Features, page 1:** the maximum sampling rate is given by the maximum
speed of the I2C bus. The part has no sample clock of its own at all;
it converts while the previous result is being shifted out.

**And the bus on this HAT is capped at 100 kHz by the PCF8574**, which is
a Standard-mode part, as the section above records.

So the chain is:

```
   PCF8574 is 100 kHz only   ->   the bus runs at 100 kHz
                             ->   the PCF8591 converts no faster
                                  than a 100 kHz bus can read it
```

An eight-bit read is roughly twenty bit times of address and data, so the
ceiling is of the order of a few thousand samples per second, and well
under that in practice once the kernel's overhead is counted. **That is an
order of magnitude rather than a specification**, and it is stated as one.

For a board whose analog inputs go to a screw terminal and a sensor
header, a few kilosamples per second is ample. The reason to write it down
is that it is a **ceiling set by a different chip**, which is not where
anybody would look for it.

### The DAC, which this project does not use

AOUT is a 256-tap resistor divider between `VREF` and `AGND`, with the
output buffered by an auto-zeroed unity gain amplifier that the control
byte's bit 6 switches on and off. **Figure 6, page 7** gives the output:

```
   V_AOUT  =  V_AGND  +  (V_VREF - V_AGND) / 256  *  the DAC byte
```

The analog voltage range is `VSS` to `VDD`, and the supply is 2.5 V to
6.0 V.

**Nothing in this project drives it**, and [pin-map.md](pin-map.md)
records AOUT as leaving the board at screw terminal position 5, marked
`DOUT`. It is recorded here because the same unity gain amplifier is
borrowed during A/D conversion, with a track and hold circuit to free it,
which is why the two functions cannot run at full speed at once.

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
| ~~PCF8574 datasheet~~ | **done.** It turned out to say more than expected, including the one move that can damage the part |
| ~~PCF8591 datasheet~~ | **done**, and it carried the worst defect on this HAT: a read returns the previous conversion |
| a Raspberry Pi 3 Model B electrical specification | does not exist; the gap is permanent and should be named rather than closed |
