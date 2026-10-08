# Datasheets and primary sources

Every primary document for the parts on this bench, in one place, so that
no claim in this repository has to be made from memory and no URL has to
be hunted twice.

**How to use this page.** Before writing a project's hardware notes, open
the documents for the parts it touches and cite them by name, page and
date in [docs/HARDWARE.md](HARDWARE.md) or in the project's own
`docs/`. The evidence vocabulary is defined at the top of that page: a
claim is `datasheet` only once somebody has actually opened the document,
and `NOT READ` until then. **This index existing does not make anything a
`datasheet` row.** Reading does.

The **Read** column tracks that honestly:

| Mark | Means |
|---|---|
| `yes` | opened, and something in this repository cites it |
| `partial` | opened for one question, not worked through |
| `no` | listed here and not yet opened |

## How to cite one of these, and what not to copy

**Cite by document, publisher, date, table or section, and page**, so a
reader can open the original at the right place:

> BCM2835 ARM Peripherals, Broadcom, 6 February 2012, Table 6-31, page 102

A URL alone is not a citation. URLs rot, documents get revised, and page
numbers move between revisions, which is why the date belongs in the
citation and the revision belongs in it too when the document carries one.

**Do not copy figures, tables or extended text out of these documents into
this repository.** They are the manufacturers' copyright, and this is a
public repository. Three things work better anyway:

- **Redraw it.** The figures under each project's `docs/figures/` are
  original TikZ, and `uart-mux.tex` in project 9 is the worked example: it
  takes four tables from the Broadcom document and draws the one path
  through them that the surrounding text is about. A vendor table answers
  every question at once; a figure here should answer the question being
  asked.
- **Quote the value, not the page.** A specific number, address or
  register name used to support a claim is ordinary citation. A
  reproduction of the table it sits in is not.
- **Photograph the bench instead**, where the bench can answer. A
  photograph of a chip marking settles a part identification better than
  any datasheet, and
  [`projects/01-yocto-image/docs/figures/leds-lit.jpg`](../projects/01-yocto-image/docs/figures/leds-lit.jpg)
  is the precedent: it corrected a belief that three projects had already
  been designed around.

## Hosts and SoCs

| Document | Part | For | Read | URL |
|---|---|---|---|---|
| Raspberry Pi 4 Model B datasheet, release 1.1, 12 March 2024 | Pi 4B | projects using the Pi 4 | **yes** | `https://datasheets.raspberrypi.com/rpi4/raspberry-pi-4-datasheet.pdf` |
| BCM2711 peripherals | Pi 4 SoC | register level work on the Pi 4 | no | `https://datasheets.raspberrypi.com/bcm2711/bcm2711-peripherals.pdf` |
| Raspberry Pi 3 Model B+ product brief, published October 2025 | Pi 3 Model B Plus | the Project 9 board | **yes** | `https://datasheets.raspberrypi.com/rpi3/raspberry-pi-3-b-plus-product-brief.pdf` |
| Raspberry Pi 3 Model B+ reduced schematic, V1.0, 19 March 2018 | Pi 3 Model B Plus | header pin functions, power protection | **yes** | `https://datasheets.raspberrypi.com/rpi3/raspberry-pi-3-b-plus-reduced-schematics.pdf` |
| Raspberry Pi 3 Model B product page | Pi 3, the host of projects 6, 18, 19 and 20 | the only document that exists for it | **yes**, and it is a bullet list | `https://www.raspberrypi.com/products/raspberry-pi-3-model-b/` |
| BCM2835 and BCM2837 peripherals | Pi 3 SoC | GPIO function select, UART, SPI, I2C registers | **partial** | `https://datasheets.raspberrypi.com/bcm2835/bcm2835-peripherals.pdf` |
| Raspberry Pi Touch Display product brief, April 2024 | DSI panel | project 13 | **yes** | `https://datasheets.raspberrypi.com/display/7-inch-display-product-brief.pdf` |
| FriendlyELEC wiki, NanoPi NEO Air, modified 14 November 2023 | NEO Air | project 2 | **yes** | `https://wiki.friendlyelec.com/wiki/index.php/NanoPi_NEO_Air` |
| NanoPi NEO Air schematic V1.1 | NEO Air | project 2 | no | `https://wiki.friendlyelec.com/wiki/images/7/70/Schematic_NanoPi-NEO-Air-V1.1_1708.pdf` |
| Allwinner H3 datasheet Rev 1.2 | NEO Air SoC | project 2 | no | `https://archive.org/details/allwinner-h3-datasheet` |
| PPK2 user guide v1.0.1, document 4461_012, PDF | power profiler | projects 3 and 16, and every current measurement | **yes**, sections 6 and 8 | `https://mm.digikey.com/Volume0/opasdata/d220001/medias/docus/7735/PPK2_User_Guide.pdf` |
| Nordic PPK2 user guide, HTML | the same guide, abridged | see the warning in project 3 | **yes** | `https://docs.nordicsemi.com/bundle/ug_ppk2/page/UG/ppk/PPK_user_guide_Intro.html` |

**The same resistor passed and failed on one afternoon, and the difference
is the lesson.** The Raspberry Pi's 47 kohm internal pull-up fails an I2C
bus by more than an order of magnitude, as project 10's arithmetic shows.
TI specifies the ADS7846's `PENIRQ` output low voltage **with a 50 kohm
pull-up**, so the same 47 kohm is within six per cent of that part's own
test condition and is entirely right there. A pull-up is not strong or
weak in the abstract; it is strong or weak against a rise time budget, and
an interrupt that falls once when a finger lands has no such budget. Both
verdicts, side by side, are in
[project 7's hardware page](../projects/07-lcd35-drm/docs/hardware.md).

**Treating a figure that failed in one place as a figure that fails
everywhere is as expensive as the original mistake**, which is why both
are recorded rather than only the alarming one.

**An identification register is not always a part number, and project 7 is
the case that proves it.** The ILI controller datasheet is read, and it
defines two identification commands, `04h` and `D3h`, and publishes an
expected value for **neither**: both are given as `XX`. Its own
description says why. `ID1` is the **LCD module's manufacturer** ID, not
the controller's, so the value is whatever the module maker programmed.
The BMP280 answers `0x58` because Bosch says so; this part answers
whatever Waveshare put there, and Waveshare does not say. **So project 7's
identification question cannot be closed by reading a datasheet**, and the
page now says that rather than leaving the document on a list it would
never satisfy.

**Two smaller findings came with it.** The index's URL was dead, pointing
at `/4/4e/` where the live file is `/7/78/`; corrected above. And the file
Waveshare serves as `ILI9486_Datasheet.pdf` is a datasheet for the
**ILI9486L**, a different part number, on all 219 of its pages. Three
names are now in play for one chip: `ILI9486` in the design, `ili9486.c`
in the kernel, and `ILI9486L` in the vendor's own file.

**This document also carries the sharpest copyright notice met so far**, on
every page, forbidding reproduction in whole or in part without written
permission. The citation convention in this file exists for exactly that,
and project 7's section is written to it: command codes, section numbers,
page numbers, and no reproduced table.

**Project 6's four component datasheets are all read, and none said what
was expected of it.** The DS3231 gave the 2 ppm that justifies fitting it
and the warning that its temperature sensor is plus or minus 3 C, so it is
not a bench thermometer. The BMP280, which was not even on the unread
list, gave the one byte that settles the JOY-iT manual's three way
contradiction about which part is on the board: register `0xD0` returns
`0x58` on a BMP280 and the test costs one `i2cget`.

**`analog.com` timed out again**, so the DS3231 was read from a copy
served by Adafruit. It carries Maxim's own document number and revision on
page 1, which is what makes that acceptable.

**And the bus speed story on that HAT completes.** The DS3231 does 400
kHz, the PCF8591 has no clock of its own and converts as fast as the bus
reads it, and the PCF8574 is Standard-mode only. So the bus runs at 100
kHz, two of the three parts could go four times faster, and the thing to
remove if the ADC is ever wanted faster is the expander, which is not
where anybody would look.

**The two NXP parts on the Explorer700 are read, and the smaller one held
the larger finding.** The PCF8574's outputs sink 10 mA and source 100
microamps, a ratio of a hundred to one, so every load on it is driven
active low, which is the opposite of the LK-LED10 convention everywhere
else on this bench. Writing 0 to a line something else is driving high can
damage the part, which is the mechanism behind a caution project 6 already
had for the right reasons. And the part is Standard-mode only, so it caps
its whole bus at 100 kHz.

**The PCF8591 returns the previous conversion.** Its datasheet says so in
section 8.4: the conversion is executed while the result of the previous
one is transmitted. So a read that follows a channel change reports the
old channel, successfully, with a plausible number. Combined with four
unterminated analog inputs that project 6 already documents, that part has
two independent ways to report a believable wrong value. Both are in
[project 6's hardware page](../projects/06-explorer700/docs/hardware.md),
along with the exact kernel file that would say whether the driver already
handles it.

**One datasheet closed a four project argument with a formula.** The
Sensirion SHT4x datasheet, version 6.4, bounds the bus capacitance for a
given pull-up and rise time, `C_b < t_rise / (0.8473 * R_p)`. Put the
Raspberry Pi's 47 kohm internal pull-up into it and the permitted bus
capacitance is **7.5 pF in fast mode and 25 pF in standard mode**, against
the fifty to a hundred that a few centimetres of jumper wire presents. So
a hand-wired bus on internal pull-ups does not merely look marginal; it
fails a manufacturer's stated condition by more than an order of
magnitude. The working is in
[project 10's hardware page](../projects/10-iio-iks4a1/docs/hardware.md)
and the consequence for projects 5 and 11 is in
[theirs](../projects/05-iio-adxl345/docs/hardware.md), where the remedy is
now a specific purchase: two resistors of about 4.7 kohm.

**That is what reading a datasheet is for.** The claim went from "there
are no resistors on this module" in September, to "47 kohm, five to twenty
five times weaker than usual" in the morning, to an inequality that can be
evaluated and fails, in the afternoon. Three documents from three vendors,
none of which was about the part that started the argument.

**ST's documents are unreachable and ST's register maps are not.** Every
PDF fetch from `st.com` has failed on this bench, across several sessions.
ST also publishes each sensor's register map as a C header in its own
GitHub repository, `STMicroelectronics/<part>-pid`, containing
`<part>_reg.h`, and those carry the I2C addresses, the `WHO_AM_I` register
and the expected identification value. Eight were read on Wednesday
7 October 2026 and they unblocked projects 10, 12 and 17.

**Two warnings travel with them**, both in
[project 10's hardware page](../projects/10-iio-iks4a1/docs/hardware.md).
The headers give **8-bit** addresses, shifted left by one; Linux,
`i2cdetect` and device tree use **7-bit**, so `0xD5` is `0x6A`. And
`WHO_AM_I` identifies a **family**, not a part: it separates the two IMUs
on the IKS4A1 because they are different families, and it would not
separate an LSM6DSV16X from an LSM6DSV32X, which both answer `0x70`.

**What the headers do not contain is everything electrical.** Supply
ranges, absolute maxima, timing and noise are in the datasheets and
nowhere else, and those are still `NOT READ`.

**The three documents to ask Joseph for, in order:** UM3239 for the
IKS4A1, UM2408 for the Nucleo-144, and the IKS5A1 user manual. All three
are board-level documents, and the board is where every address strap and
every level translation actually happens.

**How to cite an absence.** Project 20 needs to establish that the Pi 3
has no secure boot, no hardware unique key and no memory firewall, and no
manufacturer's document says what a part does **not** have. The answer was
not a datasheet: it was the OP-TEE project's own platform page, which
states in capitals that the port is not secure, names the missing
mechanisms, and says the package is for education and prototyping. **When
the thing to establish is an absence, look for somebody who tried to build
on the part and documented what they could not do.** For hardware security
that is a porting project; for a peripheral it is usually a driver's
comments. Worked through in
[project 20's hardware page](../projects/20-optee-keystore/docs/hardware.md).

**And two projects rest on a part with no document and no name.** Projects
1 and 19 both depend on a microSD card, and this repository records the
make, model, capacity and speed class of **no card at all**. For project 1
that costs the reproducibility of a timing figure; for project 19, whose
U-Boot writes a 16 KiB environment on every boot, it leaves a wear
question that cannot even be asked. Identifying the cards needs no
download and is the cheapest open item in the index.

**The Raspberry Pi 3 Model B has no product brief and no datasheet.** Its
product page gives a bullet list, links no PDF, and is the whole of what
Raspberry Pi publishes about the board that four projects on this bench
run on. It does name the wireless chip, `BCM43438`, which the 3B+ brief
does not; the 3B+ brief names the bands, which the Pi 3 page does not.
Each states exactly what the other omits, which is worked through in
[project 18's hardware page](../projects/18-edge-ap-mqtt/docs/hardware.md).

**The driver names the part and the manufacturer does not. Four times
now.** The ILI9486 in project 7, the FT5406 in project 13, the dual-role
`dwc2` port in project 14 and the BCM43455 in project 18 are all
identified from Linux rather than from the vendor. It is a reliable
pattern and it is not a citation, and every one of those rows says so.

**The MCC 118 datasheet specifies amplitude to four significant figures
and its time base not at all.** Gain error, offset, absolute accuracy,
both temperature coefficients and the noise are all given. The internal
scan clock gets a rate range and no accuracy and no stability. For a
project that uses this instrument as its independent time reference, that
is the missing number, and
[project 8's hardware page](../projects/08-preempt-rt/docs/hardware.md)
works out what survives it: the comparison between two kernels does, an
absolute latency in microseconds does not. Its pin list also confirms,
from the vendor, every row of that project's "do not touch" table and the
freedom of the one pin it uses.

**`files.digilent.com` returned 403 twice**, so the datasheet was read from
a distributor's copy. It carries no revision number or date, which is
worth recording: there is no way to tell from it whether a newer version
says anything different.

**Two HATs from one vendor are not equally documented, and nothing says
so.** The SIM7600E-H has a PDF manual and a wiki page; the SIM7070G
appears to have only a wiki page, and that page carries no pin table, no
PWRKEY polarity, no flight mode pin and no peak current. It does carry one
live hazard: the host logic voltage is set by a **0 ohm resistor** rather
than a jumper, the page does not say which way it is fitted, and there is
no soldering iron on this bench to move it.
[Project 16's hardware page](../projects/16-nbiot-tracker/docs/hardware.md)
records what follows, including that the first action with that board is a
photograph rather than a download.

**The SIM7600E-H HAT's manual and its wiki disagree about PWRKEY, and the
disagreement is the finding.** The 2018 manual says to strap `PWR` to
**GND** to power the module on automatically; the wiki, describing the
board after 2021, says `PWR` is strapped to **3V3** by default for the
same purpose. Both are presumably true of their own revision and neither
mentions the other. Worked through, with the consequence for anyone
wiring a Raspberry Pi GPIO to that pin, in
[project 15's hardware page](../projects/15-lte-router/docs/hardware.md).
The same reading found that the HAT's CP2102 can be jumpered to the
Raspberry Pi's own UART, which gives this bench the known-pinout console
adapter project 9 went without.

**Two documents from one vendor are two sources.** Where both exist, read
both and diff them. On this HAT the wiki has the pin table and the current
figures, the manual has the jumper block and the board inventory, and
neither is sufficient alone.

**The PPK2's HTML guide and its PDF guide are not the same document, and
the difference changed a design.** The HTML pages give the headline
figures and nothing else; the PDF's section 8 holds the source meter
current limit of 600 mA, the per range accuracy, the logic port voltage
range, the digital sampling rate, the host USB requirement and the
instrument's own temperature range. Project 3's design had said 1 A, which
is the ampere meter figure, for a project that runs in source meter mode.
The correction and its consequences are in
[project 3's hardware page](../projects/03-boot-energy/docs/hardware.md).

**The lesson is general enough to go in this file.** Where a vendor
publishes both a web page and a PDF of "the same" document, read the PDF.
The web version has been the shorter one every time it has been checked
here, and it never says what it has left out.

**The NanoPi NEO Air wiki is read, and it carried one number worth the
trip.** FriendlyELEC states an input range of 4.7 V to 5.6 V rather than a
bare 5 V. Project 3 supplies that board from the PPK2, whose source meter
tops out at 5.0 V, so the measuring rig starts 300 mV above the bottom of
the board's range before any lead drop. That is worked through in
[project 2's hardware page](../projects/02-neo-air-mainline/docs/hardware.md),
along with the vendor's confirmation of the four pin debug header and the
twenty four pin header's deliberate and partial resemblance to a
Raspberry Pi's. The schematic and the Allwinner H3 datasheet remain
`NOT READ`, and between them they hold the Wi-Fi part number, the antenna
connector and every GPIO electrical figure.

**There is no Raspberry Pi 3B+ datasheet, and the URL that claimed one is
dead.** The index carried
`https://datasheets.raspberrypi.com/rpi3/raspberry-pi-3-b-plus-datasheet.pdf`
until Wednesday 7 October 2026, when it returned 404. What Raspberry Pi
publishes for this board is a five page **product brief** and a one sheet
**reduced schematic**, both now read and both worked through in
[docs/HARDWARE.md](HARDWARE.md). The brief states the processor, the
power input, the temperature range and the warnings; **it states nothing
at all about GPIO electrical behaviour**, which is the single most useful
thing this round of reading established.

**Watch the redirects on the Raspberry Pi document host.** Every
`datasheets.raspberrypi.com` link above now redirects twice, through
`pip.raspberrypi.com` to `pip-assets.raspberrypi.com`, and the final
filename carries a document number and a revision, for example
`RP-008341-DS-1-raspberry-pi-4-datasheet.pdf`. Cite the stable short URL,
and record the revision from page 1 of the document itself, because the
revision is the part that changes what the numbers say.

**The BCM2835 peripherals document was the one to read first, and chapter
6 now is read.** Broadcom, 6 February 2012. Tables 6-1, 6-2, 6-3 and 6-31,
pages 90 to 103, are cited in
[project 9's hardware page](../projects/09-kernel-debug/docs/hardware.md),
which was previously written from memory. The rest of the document, the
UART, SPI, I2C, DMA and timer chapters, is still unread.

Two notes for whoever opens it next. **It redirects twice**, ending at
`pip-assets.raspberrypi.com`, and the final PDF does not convert to text,
so it has to be read as pages rather than searched. And **it is the
BCM2835 document while the bench boards are BCM2836 and BCM2837**: the bus
addresses beginning `0x7E` are the same, but the ARM physical base moves
from `0x2000 0000` to `0x3F00 0000`, so an address copied straight out of
the PDF reads the wrong place on a Pi 3 and does so without complaining.

**The PPK2 user guide, Nordic Semiconductor, read Wednesday 7 October
2026**, and it changed a number this repository had already published.

| Figure | Value |
|---|---|
| modes | source meter, which supplies and measures; ampere meter, which measures a board powered elsewhere |
| source meter output | 0.8 V to 5.0 V, software configurable |
| current range | 500 nA to 1 A |
| **accuracy** | **"better than plus or minus 20 per cent (average currents measurement)"** |
| resolution | down to 0.2 microamp, accurate to about 200 nA |
| sampling | 100 kS/s |
| digital port | 8 pin, for digital tracing |

**The accuracy figure matters more than the rest.** Current measurements
in this repository were being quoted to four significant figures, which
implies a precision the instrument does not claim. They are the
instrument's readout, and any value derived from them, a resistance or a
forward voltage, inherits the same uncertainty. Every such table now says
so.

**One gap worth naming**: the guide does not state a voltage limit for the
eight pin digital port. So what may safely be connected to it is `NOT
READ`, and a 5 V logic signal should not meet it on the strength of
assumption.

The note that the PPK2 cannot read the voltage at an arbitrary node stays
`inferred`: it follows from the instrument being a source meter and an
ampere meter, and the guide does not spell it out.

**The Touch Display product brief, Raspberry Pi Ltd, April 2024**, read
Wednesday 7 October 2026 and worked through in
[project 13's hardware page](../projects/13-wayland-kiosk/docs/hardware.md).
It gives 800 by 480 on a 7 inch TFT, capacitive multi-touch to ten points,
and the connection arrangement: an adapter board, power from the GPIO
port, and a ribbon to the DSI connector.

**It names neither the touch controller nor the backlight arrangement**,
both of which `DESIGN.md` identifies from the kernel driver instead. That
is the same pattern as the Waveshare LCD, and worth noticing: for display
hardware on this bench, the Linux driver has been a better source of part
identity than the manufacturer's own document. It is still not a citation.

It also carries a manufacturer's instruction worth lifting into the bench
rules: shut the Raspberry Pi down and disconnect it from external power
**before** connecting the display. And a condition of use this bench does
not meet, since the brief requires a suitable enclosure with no part of
the circuit board accessible in operation, and the panel here sits bare on
a desk.

## HATs, displays and bridges

| Document | Part | For | Read | URL |
|---|---|---|---|---|
| JOY-iT RB-Explorer700 manual, 16 November 2020 | Explorer700 | project 6 | **yes** | `https://www.joy-it.net/files/files/Produkte/RB-Explorer700/RB-Explorer700-Manual-16.11.2020.pdf` |
| MCC 118 datasheet, DS-MCC-118, Measurement Computing | DAQ HAT | project 8, the external instrument | **yes** | `https://files.digilent.com/datasheets/DS-MCC-118.pdf` |
| MCC DAQ HAT library, C API reference | the same HAT's software | project 8 | **yes** | `https://mccdaq.github.io/daqhats/c.html` |
| Maxim DS3231, document 19-5170, revision 10, March 2015 | real time clock on the Explorer700 | project 6 | **yes** | `https://www.analog.com/media/en/technical-documentation/data-sheets/DS3231.pdf` |
| Bosch BMP280, `BST-BMP280-DS001-26`, revision 1.26, October 2021 | pressure sensor on the Explorer700 | project 6 | **yes** | `https://www.bosch-sensortec.com/media/boschsensortec/downloads/datasheets/bst-bmp280-ds001.pdf` |
| NXP PCF8574; PCF8574A, revision 5, 27 May 2013 | I/O expander on the Explorer700 | project 6 | **yes** | `https://www.nxp.com/docs/en/data-sheet/PCF8574_PCF8574A.pdf` |
| NXP PCF8591, revision 7, 27 June 2013 | ADC and DAC on the Explorer700 | project 6 | **yes** | `https://www.nxp.com/docs/en/data-sheet/PCF8591.pdf` |
| CP2102 | USB to UART bridge | console adapters | no | `https://www.silabs.com/documents/public/data-sheets/CP2102-9.pdf` |
| Waveshare 3.5 inch RPi LCD (A) wiki | LCD | project 7 | **yes** | `https://www.waveshare.com/wiki/3.5inch_RPi_LCD_(A)` |
| ILI9486**L**, ILI Technology Corp., version 0.06 | the LCD's controller, probably | project 7 | **yes** | `https://www.waveshare.com/w/upload/7/78/ILI9486_Datasheet.pdf` |
| TI ADS7846, `SBAS125H`, revised January 2005 | the LCD's touch controller | project 7 | **yes** | `https://www.ti.com/lit/ds/symlink/ads7846.pdf` |

**Two things the Waveshare LCD wiki does not say**, read Wednesday 7
October 2026 and recorded in
[project 7's hardware page](../projects/07-lcd35-drm/docs/hardware.md).
It **never names the panel controller**, so the ILI9486 identification in
that project rests on the kernel driver rather than on the manufacturer.
And it gives only a partial pin list rather than a table, naming 26 of the
40 pins as occupied without enumerating all of them.

What it does give: 480 x 320, SPI, `ADS7846` touch, 3.3 V and 5 V both
used, about 150 mA, and "compatible with any version of Raspberry Pi".

The Explorer700 manual is the one document already worked through, in
[project 6's pin map](../projects/06-explorer700/docs/pin-map.md), which
also records the three places it contradicts itself about one sensor.

## Modems

| Document | Part | For | Read | URL |
|---|---|---|---|---|
| SIM7600E-H 4G HAT manual, Waveshare, Rev 1.0, 8 June 2018 | 4G HAT | project 15 | **yes** | `https://www.waveshare.com/w/upload/6/6d/SIM7600E-H-4G-HAT-Manual-EN.pdf` |
| Waveshare wiki, SIM7600E-H 4G HAT | the same HAT, a later revision | project 15 | **yes** | `https://www.waveshare.com/wiki/SIM7600E-H_4G_HAT` |
| SIM7600E-H module manual | the module itself | project 15 | no | `https://fccid.io/2AJYU-8PYA009/User-Manual/User-Manual-4814639.pdf` |
| Waveshare wiki, SIM7070G Cat-M/NB-IoT/GPRS HAT | Cat-M, NB-IoT, GPRS HAT | project 16 | **yes**, and it answers very little | `https://www.waveshare.com/wiki/SIM7070G_Cat-M/NB-IoT/GPRS_HAT` |
| SIM7020E wiki | NB-IoT HAT | | no | `https://www.waveshare.com/wiki/SIM7020E_NB-IoT_HAT` |
| SIMCom SIM7000 series documents | AT command sets | project 16 | no | `https://simcom.ee/documents?dir=SIM7000x` |

**The SIM7070G wiki, read Wednesday 7 October 2026**, gives the baud
rates from 300 to 3,686,400 with the usual 9600 to 115200, a 5 V supply
with about 41 mA idle, an onboard USB interface that is optional when
driving it over UART from the Pi, and `AT+CGREG?`, `AT+CGNAPN` and
`AT+CNACT=0,1` for registration, APN query and network activation.

**Two cautions from it.** There is **no pin table in BCM numbering**: the
one pin it names, `PWRKEY`, is given as "P7 (wiringPi number)", which is a
third numbering scheme beside BCM and physical and a reliable source of
wrong connections. And the logic level is "default 3.3 V, can be set to
5 V via jumper resistor", so **the level is a board modification rather
than a fixed property** and should be confirmed before it meets a Pi
header.

## STM32 and ST expansion boards

| Document | Part | For | Read | URL |
|---|---|---|---|---|
| UM2408, STM32H7 Nucleo-144 MB1363 | NUCLEO-H7A3ZI-Q | the firmware volume | no | `https://www.st.com/resource/en/user_manual/um2408-stm32h7-nucleo144-boards-mb1363-stmicroelectronics.pdf` |
| STM32H7A3ZI product page | the MCU | the firmware volume | no | `https://www.st.com/en/microcontrollers-microprocessors/stm32h7a3zi.html` |
| UM3239, getting started with X-NUCLEO-IKS4A1 | IKS4A1 shield | project 10 | no | `https://www.st.com/resource/en/user_manual/um3239-getting-started-with-the-xnucleoiks4a1-motion-mems-and-environmental-sensor-expansion-board-for-stm32-nucleo-stmicroelectronics.pdf` |
| X-NUCLEO-IKS5A1 product page | IKS5A1 shield | | no | `https://www.st.com/en/evaluation-tools/x-nucleo-iks5a1.html` |
| STEVAL-STWINBX1 product page | STWIN.box | project 17 | no | `https://www.st.com/en/evaluation-tools/steval-stwinbx1.html` |

**Note on st.com, updated Wednesday 7 October 2026.** The authoring laptop
gets no PDF from st.com in a browser, and **the same is true of the fetch
route used for the other documents here**: three attempts on that day
returned a connection reset each time. So having the URLs did not solve
it.

**These need downloading by hand and sending**, the way the two Joy-it
documents were on Tuesday 6 October 2026, which worked first time. Until
then, ST register layouts come from ST's own header repositories on
GitHub, and a project document quoting one should say which header file it
came from rather than implying a datasheet.

## Sensors on the X-NUCLEO-IKS4A1

Project 10's shield. Seven parts, seven documents.

| Document | Part | What it is | Read | URL |
|---|---|---|---|---|
| LSM6DSO16IS | IMU | 6-axis, with ISPU | datasheet **no**, register map **yes** | `https://www.st.com/resource/en/datasheet/lsm6dso16is.pdf` |
| ST register headers, `STMicroelectronics/<part>-pid` | eight sensors | projects 10, 12 and 17 | **yes**, read 7 October 2026 | `https://github.com/STMicroelectronics` |
| LSM6DSV16X | IMU | 6-axis, with sensor fusion | no | `https://www.st.com/resource/en/datasheet/lsm6dsv16x.pdf` |
| LIS2MDL | magnetometer | 3-axis | no | `https://www.st.com/resource/en/datasheet/lis2mdl.pdf` |
| LIS2DUXS12 | accelerometer | 3-axis, low power | no | `https://www.st.com/resource/en/datasheet/lis2duxs12.pdf` |
| LPS22DF | pressure | barometric | no | `https://www.st.com/resource/en/datasheet/lps22df.pdf` |
| STTS22H | temperature | digital | no | `https://www.st.com/resource/en/datasheet/stts22h.pdf` |
| Sensirion SHT4x datasheet, version 6.4, November 2023 | humidity and temperature | Sensirion, not ST | **yes** | `https://sensirion.com/media/documents/33FD6951/6555C40E/Sensirion_Datasheet_SHT4x.pdf` |

**One thing these seven settle that is already known to matter.** A
project 10 acceptance criterion asks for a 416 Hz output data rate, which
belongs to the LSM6DSO family. The part on this shield offers powers of
two and tops out at 960. That criterion is marked defective rather than
unmet, and these datasheets are what makes the restatement citable instead
of remembered.

## Loose parts

| Document | Part | For | Read | URL |
|---|---|---|---|---|
| OP-TEE documentation, Raspberry Pi 3 platform page | the Pi 3 as a TEE host | project 20 | **yes** | `https://optee.readthedocs.io/en/latest/building/devices/rpi3.html` |
| ADXL345 Rev G | accelerometer | projects 5 and 11 | no | `https://www.analog.com/media/en/technical-documentation/data-sheets/ADXL345.pdf` |

**The ADXL345 datasheet could not be fetched on Wednesday 7 October
2026.** Two attempts to `analog.com` returned a connection reset and then
a timeout. The URL is believed good and the failure looks transient, so
this is a retry rather than a dead end; it is recorded because an
unexplained `no` in the Read column invites somebody to assume the
document was simply skipped.

The **SEN0032** is the DFRobot module that carries this part. Its own
schematic is the source for the board level facts in
[docs/HARDWARE.md](HARDWARE.md): the silkscreen pad order, the `BL8555-30`
regulator, the complete absence of pull-ups, and the digital pin limit.
**The ADXL345 datasheet is the source for the die**, including the
absolute maximum ratings that make a 3.3 V host sit exactly at the limit,
and that is the row most worth upgrading from inference to citation.

## Already cited from a schematic rather than listed here

Two parts whose primary source is a schematic PDF rather than a datasheet,
both read Tuesday 6 October 2026:

- **Waveshare WS-28164**, the RS232, RS485, CAN and CAN FD board.
  `https://www.waveshare.com/wiki/RS232-RS485-CAN-Board` and
  `https://files.waveshare.com/wiki/RS232-RS485-CAN-Board/RS232_RS485_CAN_Board_Sch.pdf`
- **TI SLOS346O**, the SN65HVD230 datasheet, for the loop delay figures
  that transmitter delay compensation needs.

## What is still missing from this list

Named so that the gaps are visible rather than implied:

- **MCC 118 DAQ HAT.** No document listed. It is a Measurement Computing
  part with its own library, and the specification work for it has been
  done from the library rather than from a datasheet.
- **Joy-it SBC-ESP8266-PROG socket pinout.** Its manual and its datasheet
  were both read on Tuesday 6 October 2026 and **neither publishes one**,
  nor does the product page. The only authority is the silkscreen on the
  board.
- **Joy-it LK-LED10.** No datasheet found. Everything known about these is
  measured on this bench, which for a part this simple is arguably better.
