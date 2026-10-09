# Hardware sources for projects 5 and 11

Both projects use the same part, so this page serves both: project 5
writes an in-kernel IIO driver for it, project 11 a packaged userspace
library.

[docs/DESIGN.md](DESIGN.md) already carries the wiring as observed on two
dated occasions, the pad
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
| the die | Analog Devices ADXL345 | ADXL345 Rev G datasheet | **read Friday 9 October 2026** |

**Nearly every surprise on this bench has been at the module layer**, not
the die layer, which is why the schematic was worth reading first. The
module facts are in [docs/HARDWARE.md](../../../docs/HARDWARE.md) in full;
the short version is that the silkscreen pad order and the schematic's own
`J1` numbering disagree, there is a `BL8555-30` regulator between the
header and the die that makes two vendor pages give different supply
ranges and both be right, and there is not a single resistor on the board,
so a two-wire bus built from it has only the host's internal pull-ups.

## The missing pull-up now has a number, and the number predicts a failure

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

**Which made the remedy look concrete.** Two resistors of about 4.7 kohm
from `SDA` and `SCL` to 3V3 would put the bus inside the condition with
room to spare, and this page listed them as a shopping item.

**Withdrawn on Friday 9 October 2026, for the Raspberry Pi case.**
Raspberry Pi's GPIO documentation states that **GPIO2 and GPIO3 have
fixed pull-up resistors**, which is header pins 3 and 5, the primary I2C
bus. A Raspberry Pi's I2C bus is therefore never on the internal pull-up,
the arithmetic above never applied to it, and buying those two resistors
for a Pi would buy nothing. The full correction is in
[docs/HARDWARE.md](../../../docs/HARDWARE.md).

**Where the arithmetic does still apply**, unchanged: a bit-banged I2C bus
on any other Pi GPIO, and any host that fits no pull-ups of its own. This
module has been exercised on a Nucleo as well as on a Pi, and what the
Nucleo fits is `NOT READ`.

**The shape of the error is worth more than the error.** The working was
sound, the formula was the manufacturer's, the number was the right number
for an internal pull-up, and the conclusion was still wrong, because
nobody had asked whether the bus in question used the internal pull-up at
all. **An arithmetic result inherits every assumption in its inputs**, and
the assumption here was never written down, which is exactly why it went
unexamined.

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
was that a reader could not check any of them, and the project's own
`DESIGN.md` is scrupulous about marking its other inferences, so these
were marked too rather than passing as settled.

**That caution was worth its keep.** When the datasheet finally arrived,
four of the five were right and **one had the wrong constant in it**. The
next section has all five with page numbers.

**The datasheet could not be fetched until Friday 9 October 2026.** Three
attempts to `analog.com` on Wednesday 7 October 2026 returned a connection
reset and two timeouts, and a fourth on Friday timed out again. It was
read from a mirror that day.

## The ADXL345 datasheet is read, and it closes every open row

**Source: Analog Devices ADXL345, "3-Axis, +/-2 g/+/-4 g/+/-8 g/+/-16 g
Digital Accelerometer", data sheet Rev. G, 36 pages.** Read Friday
9 October 2026.

**Provenance.** `analog.com` timed out again, as it has in every session
since Tuesday 6 October 2026. Joseph supplied the route on Friday
9 October 2026: the document is mirrored, and the copy read carries
"Rev. G" and "analog.com" on every page footer, which is the revision this
repository's source index has always named.

### The five rows, settled

This page listed five claims the project relies on and marked them all
`inferred` or unsourced. All five are now cited, and **one of them was
wrong**.

| Claim as this page stated it | Verdict |
|---|---|
| a digital pin's absolute maximum is VDD I/O plus 0.3 V, **or 3.6 V**, whichever is less | **right in shape, wrong in the constant.** Table 2, page 5: "-0.3 V to VDD I/O + 0.3 V or **3.9 V**, whichever is less" |
| `SDO` low selects one I2C address and high the other | **confirmed**, page 17: ALT ADDRESS high gives 7-bit `0x1D`, grounding `SDO`/ALT ADDRESS gives `0x53` |
| `CS` high selects I2C rather than four-wire SPI | **confirmed**, page 17: "With `CS` tied high to VDD I/O, the ADXL345 is in I2C mode" |
| the device identification register and its fixed value | **confirmed**, Table 19 page 23: `DEVID` at address `0x00`, read only, reset value `11100101`, which is **`0xE5`** |
| the available output data rates and the g ranges | **confirmed**, and bounded by the bus rather than the part; see below |

### The one that was wrong, and why it still gave the right answer

This page said the limit is "VDD I/O plus 0.3 V, or **3.6 V**, whichever is
less". The datasheet says **3.9 V**.

**And the practical conclusion was right anyway.** With VDD I/O at 3.3 V,
the two branches are 3.6 V and 3.9 V, and "whichever is less" picks 3.6 V.
So the wrong constant happened to equal the right answer **at this
particular supply voltage**, which is exactly the kind of coincidence that
keeps an error alive.

**Where it would have bitten:** at any VDD I/O below 3.6 V the two branches
separate, and a reader using the misremembered rule would compute a limit
too low rather than too high. That is the safe direction, which is the
only reason this is a correction rather than an incident.

**The general form, which this bench keeps meeting:** an inference can be
right in structure and wrong in a constant, and a single test case can
agree with both. The fix is not to be more careful about remembering; it
is to mark the row `inferred` and read the document, which is what this
page did.

### What `CS` and `SDO` turn out to be, which is stronger than "selects"

Page 17, and this is worth quoting because it changes the straps from a
configuration choice into a requirement:

> There are no internal pull-up or pull-down resistors for any unused
> pins; therefore, there is no known state or default state for the `CS`
> or ALT ADDRESS pin if left floating or unconnected. It is required that
> the `CS` pin be connected to VDD I/O and that the ALT ADDRESS pin be
> connected to either VDD I/O or GND when using I2C.

**So the orange and brown leads are not optional and not merely
conventional.** A floating `CS` leaves the part with no defined interface
mode, and a floating `SDO` leaves it with no defined address. `DESIGN.md`
straps both, which was right, and the reason is now the manufacturer's
rather than this bench's.

**And it interacts with the friction-contact warning on this page.** The
module's header is not soldered, so any one of six contacts can be open at
any moment. Two of those six are the straps. **An intermittent strap does
not produce intermittent data; it produces a part in an undefined mode**,
which is a different and worse symptom than a missing reading.

### The output data rate is limited by the bus, not by the part

Page 17, in its own words: the maximum output data rate when using 400 kHz
I2C is **800 Hz**, and it scales linearly with the communication speed, so
100 kHz I2C limits the maximum ODR to **200 Hz**. Operating above the
recommended maximum "may result in undesirable effect on the acceleration
data, including missing samples or additional noise".

| I2C clock | Maximum ODR the datasheet recommends |
|---|---|
| 100 kHz | 200 Hz |
| 400 kHz | 800 Hz |

**This is a constraint the project did not have.** The IIO driver will
happily expose output data rates up to 3200 Hz, because the part supports
them over SPI. **Over I2C at 100 kHz, anything above 200 Hz is outside the
manufacturer's recommendation**, and the failure mode named is missing
samples and extra noise rather than an error.

**That is this repository's favourite failure shape again**: a setting
that is accepted, produces numbers, and produces worse numbers than the
reader believes. Any acceptance figure from this project should record the
I2C clock alongside the ODR, because one bounds the other.

**And this project already sets the clock, which makes the ceiling
800 Hz.** `kas/bench-adxl345.yml` carries
`RPI_EXTRA_CONFIG = "dtparam=i2c_arm_baudrate=400000"`, and so do
`kas/bench-userdrv.yml` for project 11 and `kas/bench-iio.yml` for project
10. At 400 kHz the datasheet's recommended maximum output data rate is
**800 Hz**, not the 200 Hz a default 100 kHz bus would give.

**That is what the recipe sets, which is not the same as what is running.**
The clock on a particular card is whatever image was flashed onto it, and
[docs/HARDWARE.md](../../../docs/HARDWARE.md) carries the general rule:
a document records what was built, not what is connected now. `i2cdetect
-y 1` and the kernel log settle the running case.

### The electrical check against a Pi 3B+, both directions

The host's figures now come from the right document and the right board:
Raspberry Pi's GPIO documentation, BCM283x table, which covers the Pi 3B+.
The sensor's come from Table 11, page 17, at VDD I/O = 3.3 V.

| Direction | Driver guarantees | Receiver needs | Margin |
|---|---|---|---|
| Pi `SDA`/`SCL` high into the ADXL345 | 3.0 V minimum at 2 mA | `V_IH` 0.7 x VDD I/O = **2.31 V** | 0.69 V |
| Pi `SDA`/`SCL` low into the ADXL345 | 0.14 V maximum at 2 mA | `V_IL` 0.3 x VDD I/O = **0.99 V** | 0.85 V |
| ADXL345 pulls `SDA` low | **400 mV maximum** at 3 mA | Pi `V_IL` 0.9 V maximum | 0.5 V |
| ADXL345 `INT1` high into GPIO23 | 0.8 x VDD I/O = **2.64 V** at 150 microamp | Pi `V_IH` **1.6 V** minimum | 1.04 V |
| ADXL345 `INT1` low into GPIO23 | 0.2 x VDD I/O = **0.66 V** at 300 microamp | Pi `V_IL` 0.9 V maximum | 0.24 V |

**All five clear.** The tightest is the interrupt's low level at 0.24 V,
and it is tight because the interrupt pin is weak: Table 13 page 19 gives
its drive as 300 microamp sinking and 150 microamp sourcing, three orders
of magnitude less than a Raspberry Pi pin.

**Two consequences of that weakness.** `INT1` must drive nothing except
that one Pi input, and a long lead costs real time: the datasheet gives a
rise time of 210 ns into a 150 pF load, and the pin itself contributes
8 pF. For an interrupt that is irrelevant; it is recorded so that nobody
later hangs an LED on it.

**And the interrupt pins are push-pull**, page 19, not open drain, with
the default polarity **active high**, changeable by `INT_INVERT` in
`DATA_FORMAT` at address `0x31`. So no pull-up belongs on that line, and
any device tree that declares the interrupt active low is asking for a
register write the driver must actually perform.

### The pull-up question, finally closed from the sensor's side as well

Page 17: "External pull-up resistors, `R_P`, are necessary for proper I2C
operation." Table 12, page 18, bounds the bus: `C_b` 400 pF maximum per
line, rise time 300 ns maximum when receiving, `f_SCL` 400 kHz maximum.

**The wiring as built satisfies this and the reason is the host.** The
leads run to header pins 3 and 5, GPIO2 and GPIO3, and Raspberry Pi's GPIO
documentation states those two pins have **fixed pull-up resistors fitted
to the board**. The external pull-ups the datasheet requires are already
there.

**This is where the shopping item died.** This page recommended buying two
resistors of about 4.7 kohm on Thursday 8 October 2026 and withdrew the
recommendation on Friday 9 October 2026. The sensor's own datasheet agrees
with the withdrawal: it asks for external pull-ups, and the board fits
them.

### The identification test, which is one command and can fail

`DEVID` is at `0x00` and reads `0xE5`. The device is at `0x53` because
`SDO` is grounded. So:

```
   i2cget -y 1 0x53 0x00
```

| Result | Meaning |
|---|---|
| `0xe5` | an ADXL345 is answering at `0x53`. The part, the address strap, the interface strap, both bus leads and the supply are all good |
| any other value | something answered and it is not an ADXL345 |
| a read error | nothing is answering; suspect the supply first, then the six friction contacts |

**This is the probe this page has been asking for since it was written.**
It replaces "the connections are in place" with a value from the vendor's
own register map, and unlike the panel controller in project 7, this part
publishes the constant.

**One thing it does not prove**, and the distinction matters on this
module: a successful `DEVID` read exercises `SDA`, `SCL`, `CS`, `SDO`, the
supply and ground. It does **not** exercise `INT1`, which is the sixth
lead and the one project 5's driver depends on for its trigger.

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

## The bring-up tools are built and shipped to no board

**Found on Friday 9 October 2026**, by trying to use one of them, which is
the only way this class of defect ever surfaces.

### What happened

The SEN0032 was wired to the Raspberry Pi 3B+ and `i2cget -y 1 0x53 0x00`
returned `Could not open file /dev/i2c-1`. Two read-only commands located
the fault without touching a lead:

| Command | Answer | Reading |
|---|---|---|
| `ls /sys/bus/i2c/devices/` | empty | no I2C controller had probed |
| `cat /proc/device-tree/soc/i2c@7e804000/status` | `disabled` | the firmware had been told nothing, so the controller stayed off |
| `grep -i i2c /boot/config.txt` | four commented template lines | this image writes no `dtparam=i2c_arm=on` |
| `ls /sys/bus/platform/drivers/ \| grep i2c` | `i2c-bcm2835` | the controller driver **is** in this kernel |

So the device tree was the only thing holding the bus off, and adding
`dtparam=i2c_arm=on` and `dtparam=i2c_arm_baudrate=400000` to
`/boot/config.txt` enabled it. Then:

```
   modprobe i2c-dev
   modprobe: FATAL: Module i2c-dev not found in directory /lib/modules/6.6.63-v8
```

### The defect

`meta-bench/recipes-kernel/linux/files/bench.cfg` is added to the kernel
unconditionally, for every image in the tree, and it contains:

```
   CONFIG_SPI_SPIDEV=m
   CONFIG_I2C_CHARDEV=m
```

with a comment saying they are raw SPI and I2C access from user space, for
bring-up before a driver exists, and that they are modules rather than
built in because "they are debugging tools, not part of the running
system. (Projects 3, 6, 11)".

**No image in this tree installs them.** `kernel-modules` appears in
exactly one image recipe, `bench-kiosk-image.bb`, which needs the whole
set for its graphics drivers. Every other image installs only the specific
`kernel-module-` packages it names, and none of them names these two.

**So both tools are configured, compiled, packaged and never shipped.**

### Why it went unnoticed for so long

**Because the userspace half is present everywhere.** `i2c-tools` is in
`bench-image.bb`, the base every image requires, so `i2cget`,
`i2cdetect` and `i2cset` are on every board on this bench. The command
exists, runs, and fails with a message about a missing file, which reads
as a wiring or configuration problem rather than a packaging one.

**That is the sharpest form of this repository's recurring complaint.** A
check that cannot run looks exactly like a check that fails, and here the
tool that would do the checking is the thing that is missing.

**And this bench has met the shape before.** `bench-gadget-image.bb`
carries a comment headed "no kernel-modules line here, and that is the
finding", about project 14. The same omission, found a second time, in a
different place, by a different route.

### Who else this affects

The fragment's own comment names **projects 3, 6 and 11**, and the attempt
that found it was for **project 5**. Four projects expect a tool that
reaches no board.

| Project | What it expects | What it would get |
|---|---|---|
| 3, boot energy | `spidev` for bring-up | `/dev/spidev*` absent |
| 5, IIO driver | `/dev/i2c-1` to probe before the driver exists | `ENOENT` |
| 6, Explorer 700 | raw I2C to check eleven peripherals by hand | the same |
| 11, userspace library | `/dev/i2c-1`, which its own kas file names | the same |

**Project 11's recipe predicted the message.** `kas/bench-userdrv.yml`
says in a comment that without the dtparam "there is no `/dev/i2c-1` and
the library's open fails with `ENOENT`, which reads as" a different fault.
It was right about the message and attributed it to the device tree alone;
the packaging is a second, independent cause of the same message.

### Three ways to fix it, and which was chosen

**This is a build-affecting change and the decision is Joseph's.** All
three work; they differ in blast radius.

| Option | Change | Cost |
|---|---|---|
| **A** | `CONFIG_I2C_CHARDEV=y` and `CONFIG_SPI_SPIDEV=y` in `bench.cfg` | one fragment, every image, no packaging question. Contradicts the fragment's stated reason for choosing `=m`, which deserves rewriting rather than ignoring |
| **B** | add `kernel-module-i2c-dev` and `kernel-module-spidev` to the images that need them | precise, and repeated in four or more recipes, each of which can be forgotten |
| **C** | add `kernel-modules` to those images | one line each, pulls every module built, and inflates the rootfs this bench works hard to keep small |

**The argument for A**, which is the one worth writing down: the fragment
chose `=m` so the tools would not be "part of the running system". A
module that no image installs is not absent from the running system by
design, it is absent from the board entirely, which is a different and
unintended outcome. If the reason for `=m` cannot be made to hold, the
reason should change rather than the outcome persist.

**Joseph chose A on Friday 9 October 2026**, and `bench.cfg` now carries
`CONFIG_SPI_SPIDEV=y` and `CONFIG_I2C_CHARDEV=y` with the reasoning above
rewritten into the fragment's own comment, so the next reader of that
file meets the defect and not only the setting.

**The check that proves it** is the one that failed here: on a freshly
flashed image whose `config.txt` carries `dtparam=i2c_arm=on`,
`ls /dev/i2c-1` exists with no `modprobe`. It failed on Friday 9 October
2026 and it must not fail on the next build of `bench-adxl345-image`. A
check that has never failed is not known to work; this one has, which is
the only reason to trust it when it passes.

### What this said about the wiring, and what the board then said

This section stood for most of Friday 9 October 2026 saying the six
leads to the SEN0032 remained completely untested, because every command
above had exercised only the kernel's view of itself. That evening the
rebuilt image reached the board and the wire was finally asked.

**The first answer was that the record was wrong.** Read off the board
pin by pin: four leads, not seven. `VCC`, `GND`, `SDA` and `SCL` where
the 3 October table puts them; `CS`, `SDO`, `INT1` and `INT2` connected
to nothing. The straps whose necessity page 17 of the datasheet is
quoted for, twelve paragraphs above this one, were not fitted.

**The scans showed what page 17 predicts, before the wiring was read.**
Twenty-one scans of bus 1 in that state:

| What a scan showed | How often | What the datasheet says it is |
|---|---|---|
| nothing at all | most of them | `CS` floating: no defined interface mode, so the part may be in SPI mode and silent on I2C |
| `0x53` alone | several | `SDO` drifted low: the address this bench expects |
| `0x1d` alone | two in a row | `SDO` drifted high: the other address the part has, and the one that confirms the pin is floating |
| a block of thirty or more addresses | twice | a data line held at the wrong level for a moment, which is a contact, not a device; the breakout sits in a breadboard under a cushion |

A part that answers at both of its possible addresses in one sitting has
an address pin connected to nothing. That inference was made from the
scans and the datasheet before the wiring was read, and the wiring then
confirmed it.

**With power off, `CS` to pin 17 and `SDO` to pin 6, every jumper
pressed home.** Three scans: `0x53` each time, nothing else. Then the one
command this page said could fail:

```
i2cget -y 1 0x53 0x00
0xe5
```

Which, by the table in the identification section above, means the part,
the address strap, the interface strap, both bus leads and the supply
are all good, at 100 kHz, on this card. The 400 kHz line is absent from
this card for the reason in decision 119 and the test does not depend
on it.

**Two rows stay open from that evening**, recorded as open rather than
filled in: the colours of the two strap wires, and the three header pins
the serial console's leads sit on, which are not pins 6, 8 and 10 as the
3 October table says, because pin 6 now carries `SDO` and the console
kept working.

**What this is worth.** The rule above, ask the source whether it is
driving before asking the wire whether it is carrying, held again: the
kernel side was proved on a fresh image before a single scan, so the
scans could only be about wire. And the rule it adds is the one in the
design document's wiring section: a wiring table is an observation with
a date, never a standing state. This one was six days stale and said
"as built".

## The one purchase that would change this project

**A soldering iron and one 8-pin 2.54 mm male header.** With a fitted
header the friction-contact caveat disappears entirely, and with it the
whole class of intermittent failures above. There is no soldering iron on
this bench. A multimeter ranks ahead of it overall, but for this project
specifically the header is the thing.

## What was to be done when the datasheet arrived, and what was done

This page carried a three item list for the day the document turned up.
It arrived on Friday 9 October 2026 and all three are done.

| Planned | Outcome |
|---|---|
| fill the five rows with page numbers and change `inferred` to `datasheet` | **done**, and one of the five had the wrong constant |
| check the absolute maximum against the actual rail | **done.** `DESIGN.md` reasoned that `INT1` cannot be driven above 3V3 because the module is powered from 3V3. Table 2 page 5 gives the digital pin maximum as VDD I/O plus 0.3 V or 3.9 V, whichever is less, so at a 3.3 V rail the limit is 3.6 V and the argument is now cited rather than merely good |
| record the identification register so a probe becomes a measurement | **done**: `DEVID` at `0x00` reads `0xE5`, and the one line command is in the section above |

**The fourth thing was not on the list and is the most useful.** The
datasheet bounds the output data rate by the I2C clock, 200 Hz at 100 kHz
and 800 Hz at 400 kHz, which is a constraint this project did not know it
had and which no amount of careful wiring would have revealed.
