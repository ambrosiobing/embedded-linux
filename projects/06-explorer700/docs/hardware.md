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
| Maxim DS3231, document 19-5170, revision 10, March 2015 | `datasheet` | **read Thursday 8 October 2026** |
| Bosch BMP280, `BST-BMP280-DS001-26`, revision 1.26, October 2021 | `datasheet` | **read Thursday 8 October 2026** |
| NXP PCF8591, revision 7, 27 June 2013 | `datasheet` | **read Thursday 8 October 2026** |

## The host of this project, and a correction to what this page said about it

This project runs on a **Raspberry Pi 3**, not a 3B+. The Raspberry Pi 3
Model B has **no product brief and no datasheet**: its product page gives
a bulleted specification list and nothing else, and does not even link a
PDF, only two package change notices.

**This page then drew the wrong conclusion from that, on Wednesday
7 October 2026, and carried it for two days.** It said that every
electrical claim about a Pi 3 GPIO therefore has to come from the Pi 4
datasheet or from the Broadcom peripherals document. **Corrected Friday
9 October 2026:** Raspberry Pi publishes the Pi 3's GPIO electrical
specification in the **GPIO section of its documentation**, which names
BCM2835, BCM2836, BCM2837 and RP3A0 explicitly. The figures and the full
correction are in [docs/HARDWARE.md](../../../docs/HARDWARE.md). The
mistake was searching for a datasheet rather than for the fact.

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

**So the right figures for this board are the Pi 3 ones**, not the Pi 4's,
and they differ where it matters: input high is 1.6 V minimum on a Pi 3
against 2.0 V on a Pi 4, and output high is stated outright as 3.0 V
minimum at 2 mA. That matters here because this project puts eleven
peripherals on one header and reasons about pull state and drive on
several of them.

**And the I2C question is settled in the project's favour.** The GPIO
documentation states that **GPIO2 and GPIO3 have fixed pull-up
resistors**, which is header pins 3 and 5, the bus this HAT uses. So that
bus is never on an internal pull-up, whatever the HAT does or does not
fit. If the HAT fits its own as well, the two sit in parallel and the bus
is pulled harder rather than more weakly, which is the safe direction.

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

## The HAT's own silicon, which is now sourced

The pin map is complete about **which line goes where**. It is explicitly
not a source for **what each part does**. Until Thursday 8 October 2026
nothing was: this section used to be headed "still unsourced" and listed
what three unread datasheets would settle. All four parts are now read and
each has its own section below.

| Part | Role on the HAT | Document |
|---|---|---|
| DS3231 | real time clock | revision 10, March 2015, **read Thursday 8 October 2026** |
| PCF8574 | 8-bit I2C expander | revision 5, 27 May 2013, **read Thursday 8 October 2026** |
| PCF8591 | 8-bit I2C ADC and DAC | revision 7, 27 June 2013, **read Thursday 8 October 2026** |
| BMP280 | pressure and temperature | revision 1.26, October 2021, **read Thursday 8 October 2026** |

**The PCF8574 was the one this page said to read first, and the reasoning
was right for the wrong size of reason.** It said a quasi-bidirectional
output cannot sink and source like a normal GPIO, so code that drives it
as though it could works for LEDs and fails for anything needing a strong
high. That understated it twice over: the ratio between the two directions
is a hundred to one, and one of the two directions can damage the part.

**The BMP280 was not on that list at all**, and it turned out to carry the
single most useful byte on the board. Reading the three you expect to need
and then reading the fourth anyway is the whole lesson of this afternoon.

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

## The DS3231 is read, and it refines a pattern this page stated too confidently

**Source: Maxim Integrated DS3231, "Extremely Accurate I2C-Integrated
RTC/TCXO/Crystal", document 19-5170, revision 10, March 2015.** Read
Thursday 8 October 2026.

**Provenance.** `analog.com` timed out again, as it has in every session.
The datasheet was read from a copy served by Adafruit. It carries Maxim's
own document number and revision on page 1, which is what makes that
acceptable and what any other copy can be checked against.

### Why a DS3231 and not anything cheaper, in one number

This page used to say its accuracy "is the only reason to fit a DS3231
rather than anything cheaper", without a figure. Here is the figure, from
the Electrical Characteristics on page 3, with the aging offset at `00h`:

| Temperature range | Frequency stability |
|---|---|
| 0 to +40 C | **plus or minus 2 ppm** |
| above +40 to +70 C, and -40 to below 0 C | plus or minus 3.5 ppm |

**Two parts per million is about 63 seconds per year.** A plain crystal
oscillator without temperature compensation drifts by tens of ppm, which
is minutes per month. That is the whole argument for the part, and it is
now a number rather than an adjective.

The compensation is the reason the temperature sensor exists at all, which
leads directly to the next point.

### The temperature reading is a by-product, and it is not a thermometer

The features list on page 1 gives "Digital Temp Sensor Output: plus or
minus 3 C Accuracy", and page 3's table confirms temperature accuracy of
-3 to +3 C.

**Three degrees is poor**, and it is fine, because the sensor exists to
compensate a crystal rather than to measure a room.

**This matters for this project specifically.** The Explorer700 also
carries a BMP280, and project 6 binds the DS3231 through `rtc`, which on
Linux exposes its temperature under `hwmon` alongside everything else.
**Two temperature readings will appear, from two parts, and they are not
of comparable quality.** Anything that reports a bench temperature should
use the BMP280 and say so; the DS3231's number belongs next to the clock
it compensates.

That is the kind of thing nobody decides wrongly on purpose. It gets
decided by whichever `hwmon` entry a script happens to find first.

### The bus speed story completes, and the slowest part wins

Page 1: the DS3231 has a **Fast (400 kHz) I2C Interface**.

Put that beside the two NXP parts above and the Explorer700's bus has a
clear ranking:

| Part | Maximum I2C speed | Source |
|---|---|---|
| DS3231 | **400 kHz** | features, page 1 |
| PCF8591 | no clock of its own; converts as fast as the bus reads it | features, page 1 |
| **PCF8574** | **100 kHz, Standard-mode only** | Table 6, page 14 |

**So the bus runs at 100 kHz, and two of the three parts could go four
times faster.** The expander is the constraint, and it constrains an ADC
whose sample rate is nothing but the bus speed.

**Nothing here is wrong and nothing needs changing.** A clock, a joystick
and four screw terminals do not need 400 kHz. The value of knowing it is
that if anybody ever wants the ADC faster, **the thing to remove is the
expander**, which is not where they would look.

### The limit this page got slightly wrong

The PCF8574 section above observed that three parts from three
manufacturers state a maximum input voltage of the form "VSS minus a bit
to VDD plus a bit", and concluded that a pattern holding three times is a
reason to expect a fourth and not a citation for it. **The fourth part
does something else**, and the difference is instructive.

| Document | What it states |
|---|---|
| Absolute Maximum Ratings, page 2 | voltage on any pin relative to ground: **-0.3 V to +6.0 V**, a flat figure, not referenced to VCC |
| Recommended Operating Conditions, page 2 | `V_IH` minimum 0.7 x VCC, **maximum VCC plus 0.3 V** |

**Both are true and they are different questions.** The absolute maximum
is where the part is damaged; the recommended operating condition is where
it is guaranteed to work. The DS3231 survives 6 V on a pin at any supply
and is only specified to work up to VCC plus 0.3 V.

**So the pattern holds for the recommended condition and not for the
absolute maximum**, and this page's three-attestation paragraph was
reasoning about two different rows as though they were one. Corrected
here rather than quietly: **when carrying a rule of this shape between
parts, carry the row it came from as well.**

### The rest, briefly, and one thing for the instrument

From pages 2 and 3:

| Quantity | Value |
|---|---|
| supply voltage `V_CC` | 2.3 V min, 3.3 V typical, 5.5 V max |
| battery voltage `V_BAT` | 2.3 V min, 3.0 V typical, 5.5 V max |
| power-fail voltage `V_PF`, where it switches to battery | 2.45 to 2.70 V, 2.575 V typical |
| active supply current | 200 microamp max at 3.63 V |
| standby supply current | 110 microamp max at 3.63 V |
| temperature conversion current | 575 microamp max at 3.63 V |
| **timekeeping battery current** | **0.84 microamp typical, 3.0 microamp max** at 3.63 V |
| data retention current, oscillator stopped | 100 nanoamp |
| output frequency | 32.768 kHz |
| crystal aging | plus or minus 1.0 ppm in the first year, plus or minus 5.0 ppm over 0 to 10 years |
| operating temperature | 0 to +70 C for the DS3231S, -40 to +85 C for the DS3231SN |

**The battery current is right at the edge of what this bench can
measure**, which makes it a useful calibration of the instrument's own
limits. The PPK2 measures from 500 nanoamp with a 0.2 microamp step in its
finest range, so 0.84 microamp is measurable and **carries roughly a
quarter of its own value as quantisation**. Compare the SHT40's 0.08
microamp idle current, recorded in
[project 10's page](../../10-iio-iks4a1/docs/hardware.md), which is below
the floor entirely. Three parts, three verdicts: the LEDs at milliamps are
comfortably measured, this is marginally measured, and that one cannot be
measured at all.

**Which variant is fitted is unknown**, and it decides the operating
temperature range. `DS3231S` is the commercial part at 0 to +70 C and
`DS3231SN` the industrial one at -40 to +85 C. Nothing on this bench
depends on the difference, and it is a line of silkscreen on the chip if
it ever does.

## The BMP280 settles the manual's own contradiction, in one register

**Source: Bosch Sensortec BMP280 data sheet, document
`BST-BMP280-DS001-26`, revision 1.26, October 2021.** Read Thursday
8 October 2026.

### The contradiction, restated

[pin-map.md](pin-map.md) records that the JOY-iT manual says three
different things about this part: a component callout on page 2 saying
**BMP280**, a block diagram on page 3 saying **BMP 180** at address
`0x76`, and a chapter heading and code on page 11 saying **BMP280** and
using Adafruit's BMP280 library. The overlay ships `bosch,bmp280` at
`0x76` because two of the three say so, including the one that actually
talks to the part, and the pin map notes that `bmp280` in the kernel
handles both and a change would be one line.

**That is a sound decision made without a source. Here is the source.**

### The test, from section 4.3.1 on page 24

> The "id" register contains the chip identification number chip_id[7:0],
> which is 0x58. This number can be read as soon as the device finished
> the power-on-reset.

The register is at address **`0xD0`**, from the memory map in Table 18 on
the same page, which also gives its reset state as `0x58`.

So:

```
   i2cget -y 1 0x76 0xD0

     0x58   ->  it is a BMP280.  The manual's page 2 and page 11 are
                right and its page 3 block diagram is wrong.

     anything else  ->  it is not a BMP280, and identifying what it
                        actually is needs that part's own datasheet,
                        which is not read here.
```

**One command, one byte, and a three-way contradiction becomes a fact.**
This is the strongest form of what [docs/DATASHEETS.md](../../../docs/DATASHEETS.md)
calls a check that can fail: it has a published expected value, it
distinguishes the right answer from every wrong one, and it costs nothing.

**Note what it does and does not prove.** Reading `0x58` confirms a
BMP280. Reading something else refutes it without saying what is there
instead, because this reading did not cover any other Bosch part's
identification value. That asymmetry is worth stating, because a
disappointed test tempts people to guess.

### Where this sits beside the rest of the bench

This is the fourth identification register now sourced on this bench, and
the pattern across them is worth seeing together:

| Part | Register | Expected | Where it came from |
|---|---|---|---|
| BMP280, project 6 | `0xD0` | `0x58` | Bosch datasheet, section 4.3.1 |
| LSM6DSV16X, project 10 | `0x0F` | `0x70` | ST's own register header |
| LSM6DSO16IS, project 10 | `0x0F` | `0x22` | the same |
| LIS2MDL, project 10 | `0x4F` | `0x40` | the same |
| SHT40, project 10 | none | a per-unit serial via `0x89` | Sensirion datasheet |
| ADXL345, projects 5 and 11 | **unknown** | **unknown** | nowhere; still `NOT READ` |
| the LCD controller, project 7 | **unknown** | **unknown** | nowhere; the vendor never names the part |

**The last two rows are the open ones**, and they are open for different
reasons: Analog Devices' document cannot be fetched from this bench, and
Waveshare simply does not say what its panel controller is.

### Two numbers from the interface table, page 31

**Table 26** gives an internal pull-up of **70 kohm minimum, 120 kohm
typical, 190 kohm maximum** to `VDDIO`. The table's condition column does
not say which pins that applies to in the part read, so it is recorded
without a claim about `SDA` and `SCL`.

It also gives the **I2C bus load capacitance as 400 pF maximum** on `SDI`
and `SCK`, which is the ordinary I2C figure.

**Put that beside the arithmetic in
[project 10's page](../../10-iio-iks4a1/docs/hardware.md)** and the
picture is complete: the bus is permitted 400 pF, and a host's 47 kohm
internal pull-up permits 7.5 pF. The two numbers are from different
manufacturers about different things and they bracket the problem exactly.
A designed board fits 10 kohm and lives comfortably inside 400 pF; a
hand-wired bus on internal pull-ups does not.

### The registers the overlay depends on, for the record

From section 4.2, Table 18, page 24, and sections 4.3.3 to 4.3.7:

| Register | Address | What it is |
|---|---|---|
| `id` | `0xD0` | chip identification, `0x58` |
| `reset` | `0xE0` | writing `0xB6` performs a full power-on reset; any other value does nothing, and it always reads `0x00` |
| `status` | `0xF3` | bit 3 `measuring`, bit 0 `im_update` |
| `ctrl_meas` | `0xF4` | temperature and pressure oversampling, and the power mode |
| `config` | `0xF5` | standby time, IIR filter time constant, and a 3-wire SPI enable |
| `press` | `0xF7` to `0xF9` | 20-bit raw pressure |
| `temp` | `0xFA` to `0xFC` | 20-bit raw temperature |
| calibration | `0xA1` to `0xA8` and others | per-device calibration data |

**Nothing in this project writes any of them.** The kernel's `bmp280`
driver owns the part entirely, which is the design's whole point. The
table is here so that a reader debugging with `i2cget` knows which
addresses are safe to read and which one, `0xE0`, resets the device if
written carelessly.

**And the calibration row is the reason not to write any of them.** The
part carries per-device calibration data that the driver reads at probe
and uses in every conversion. A raw pressure register read without it is
not a pressure.

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

## What the four component datasheets each turned out to be for

All four were unread on Wednesday 7 October 2026 and all four are read.
None of them said what was expected of it, which is the argument for
reading rather than skimming.

| Part | What it was expected to settle | What it actually gave |
|---|---|---|
| PCF8574 | the address straps and the quasi-bidirectional output | a hundred to one drive asymmetry, the one write that can damage the part, and a 100 kHz cap on the whole bus |
| PCF8591 | the reference arrangement and the conversion time | that a read returns the **previous** conversion, which is the worst defect on this HAT |
| DS3231 | the alarm registers and the ageing offset | the 2 ppm that justifies the part, and that its temperature sensor is plus or minus 3 C and therefore not a thermometer |
| BMP280 | nothing; it was not even on the list | **the one byte that settles the manual's three way contradiction about which part this is** |

**The BMP280 is the one worth dwelling on.** It was not in the "still
unread" table at all, because the pin map had already made a sound
decision about it from the manual's internal majority. Reading it anyway
turned a well-reasoned guess into a one-command test.

## Still `NOT READ`

| Document | Why it matters |
|---|---|
| the BMP180 datasheet | would say what `0xD0` returns on that part, so that a failed BMP280 identification could name what is there instead rather than only what it is not |
| ~~a Raspberry Pi 3 Model B electrical specification~~ | **it exists**, in the GPIO documentation rather than in a datasheet, and was found on Friday 9 October 2026 after this page spent two days calling the gap permanent |
