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
| Raspberry Pi 4 datasheet | Pi 4B | projects using the Pi 4 | no | `https://datasheets.raspberrypi.com/rpi4/raspberry-pi-4-datasheet.pdf` |
| BCM2711 peripherals | Pi 4 SoC | register level work on the Pi 4 | no | `https://datasheets.raspberrypi.com/bcm2711/bcm2711-peripherals.pdf` |
| Raspberry Pi 3B+ datasheet | Pi 3 Model B Plus | the Project 9 board | no | `https://datasheets.raspberrypi.com/rpi3/raspberry-pi-3-b-plus-datasheet.pdf` |
| BCM2835 and BCM2837 peripherals | Pi 3 SoC | GPIO function select, UART, SPI, I2C registers | **partial** | `https://datasheets.raspberrypi.com/bcm2835/bcm2835-peripherals.pdf` |
| Official 7 inch DSI product brief | DSI panel | project 13 | no | `https://datasheets.raspberrypi.com/display/7-inch-display-product-brief.pdf` |
| NanoPi NEO Air schematic V1.1 | NEO Air | project 2 | no | `https://wiki.friendlyelec.com/wiki/images/7/70/Schematic_NanoPi-NEO-Air-V1.1_1708.pdf` |
| Allwinner H3 datasheet Rev 1.2 | NEO Air SoC | project 2 | no | `https://archive.org/details/allwinner-h3-datasheet` |
| Nordic PPK2 user guide | power profiler | projects 3 and 16, and every current measurement | no | `https://docs.nordicsemi.com/bundle/ug_ppk2/page/UG/ppk/PPK_user_guide_Intro.html` |

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

## HATs, displays and bridges

| Document | Part | For | Read | URL |
|---|---|---|---|---|
| JOY-iT RB-Explorer700 manual, 16 November 2020 | Explorer700 | project 6 | **yes** | `https://www.joy-it.net/files/files/Produkte/RB-Explorer700/RB-Explorer700-Manual-16.11.2020.pdf` |
| DS3231 | real time clock on the Explorer700 | project 6 | no | `https://www.analog.com/media/en/technical-documentation/data-sheets/DS3231.pdf` |
| CP2102 | USB to UART bridge | console adapters | no | `https://www.silabs.com/documents/public/data-sheets/CP2102-9.pdf` |
| Waveshare 3.5 inch RPi LCD (A) wiki | LCD | project 7 | **yes** | `https://www.waveshare.com/wiki/3.5inch_RPi_LCD_(A)` |
| ILI9486 | the LCD's controller | project 7 | no | `https://www.waveshare.com/w/upload/4/4e/ILI9486_Datasheet.pdf` |

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
| SIM7600E-H HAT manual | 4G HAT | project 15 | no | `https://www.waveshare.com/w/upload/6/6d/SIM7600E-H-4G-HAT-Manual-EN.pdf` |
| SIM7600E-H module manual | the module itself | project 15 | no | `https://fccid.io/2AJYU-8PYA009/User-Manual/User-Manual-4814639.pdf` |
| SIM7070G wiki | Cat-M, NB-IoT, GPRS HAT | project 16 | **yes** | `https://www.waveshare.com/wiki/SIM7070G_Cat-M/NB-IoT/GPRS_HAT` |
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
| LSM6DSO16IS | IMU | 6-axis, with ISPU | no | `https://www.st.com/resource/en/datasheet/lsm6dso16is.pdf` |
| LSM6DSV16X | IMU | 6-axis, with sensor fusion | no | `https://www.st.com/resource/en/datasheet/lsm6dsv16x.pdf` |
| LIS2MDL | magnetometer | 3-axis | no | `https://www.st.com/resource/en/datasheet/lis2mdl.pdf` |
| LIS2DUXS12 | accelerometer | 3-axis, low power | no | `https://www.st.com/resource/en/datasheet/lis2duxs12.pdf` |
| LPS22DF | pressure | barometric | no | `https://www.st.com/resource/en/datasheet/lps22df.pdf` |
| STTS22H | temperature | digital | no | `https://www.st.com/resource/en/datasheet/stts22h.pdf` |
| SHT40 | humidity and temperature | Sensirion, not ST | no | `https://sensirion.com/media/documents/33FD6951/624C4357/Sensirion_Humidity_Sensors_SHT4x_Datasheet.pdf` |

**One thing these seven settle that is already known to matter.** A
project 10 acceptance criterion asks for a 416 Hz output data rate, which
belongs to the LSM6DSO family. The part on this shield offers powers of
two and tops out at 960. That criterion is marked defective rather than
unmet, and these datasheets are what makes the restatement citable instead
of remembered.

## Loose parts

| Document | Part | For | Read | URL |
|---|---|---|---|---|
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
