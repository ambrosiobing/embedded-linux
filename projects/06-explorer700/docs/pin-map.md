# Pin map: RB-Explorer700 on a Raspberry Pi 3

Every line here is a claim, and every claim says where it came from and
whether anything has checked it. That distinction is the deliverable. The
specification asked for a "confirmed" column and this document is mostly
that column.

## How to read the evidence column

| Level | Means |
|---|---|
| `manual p3` | Read off the per-peripheral block diagram on page 3 of the vendor manual, which labels each signal with its Raspberry Pi BCM number. Primary source, and the best available without a net list |
| `manual ch.N` | Stated in the manual's prose, chapter N |
| `inferred` | Not stated anywhere. Reasoning is given in the row, and the row is a hypothesis |
| `observed` | Seen on this bench, with the command that saw it. **No row carries this yet** |
| `traced` | Continuity checked with the board unpowered. No row carries this yet |

The source for every `manual` row:

> Joy-it, RB-Explorer700 Manual, published 16 November 2020.
> `https://www.joy-it.net/files/files/Produkte/RB-Explorer700/RB-Explorer700-Manual-16.11.2020.pdf`

Page 2 states the convention that fixes everything else: "All pins listed
here refer to the GPIO/BCM pins of the Raspberry Pi."

## I2C1, on GPIO2 and GPIO3

| Peripheral | Address | Driver | Evidence | Confirmed |
|---|---|---|---|---|
| DS3231 real-time clock | 0x68 | `rtc-ds1307` | manual p3, and the specification agrees | no |
| PCF8574 I/O expander | 0x20 | `gpio-pcf857x` | manual p3, and the specification agrees | no |
| PCF8591 8-bit ADC and DAC | 0x48 | `pcf8591` (hwmon) | manual p3, and the specification agrees | no |
| Pressure sensor | **0x76** | `bmp280` (IIO) | manual p3. The specification says 0x77 | no |

`i2cdetect -y 1` settles all four at once and is step 1 of the bring-up.

**The pressure sensor is the one unresolved part identity on this board.**
The manual contradicts itself three times over:

| Where | Says |
|---|---|
| page 2, component callout | "BMP280: pressure sensor, I2C interface" |
| page 3, block diagram | "BMP 180", address 0x76 |
| chapter 11 heading and code | "BAROMETER - BMP280", using Adafruit's BMP280 library |

Two of three say BMP280, including the chapter that actually talks to it,
so the overlay ships `bosch,bmp280` at 0x76. Both parts are handled by the
same kernel driver and differ by chip ID, so the wrong guess is a probe
failure that names the ID it read, not a silence. `docs/BRINGUP.md` has the
one-line change if it turns out to be a BMP180.

## SPI0, and the OLED

This is the block the specification gets wrong in full. It describes an
I2C panel at 0x3C; the board has a 4-wire SPI panel.

| Signal | BCM | Role | Evidence | Confirmed |
|---|---|---|---|---|
| CS | 8 | SPI0 chip select 0, driven by the controller | manual p3 | no |
| RES | 19 | reset, `reset-gpios` | manual p3 | no |
| D/C | 16 | data/command, `dc-gpios` | manual p3, printed "DNC" | no |
| SCLK | 11 | SPI0 clock | manual p3, labelled "SCK" | no |
| MOSI | 10 | SPI0 data out | manual p3 | no |

Notes on two of those.

**"DNC" on the block diagram is D/C.** A 4-wire SPI SSD1306 has exactly
one control line besides chip select and reset, and it is data/command.
"DNC" normally means do-not-connect, which cannot be right for a pin the
diagram draws a net to. Marked `inferred` in effect, and it is confirmed by
the display working at all: without a correct D/C the panel receives its
commands as pixels.

**Chapter 16 confirms the bus independently of the diagram.** It says "make
sure the I2C and SPI are activated" before running the OLED examples. An
I2C panel would not need SPI.

The kernel consequence is in [DESIGN.md](DESIGN.md): `FB_SSD1307` is
`depends on FB && I2C` in the 6.6 source, so the driver the specification
names cannot bind this panel. The overlay uses the DRM driver
`ssd130x-spi`, compatible `solomon,ssd1306`.

## Plain SoC GPIO lines

| Peripheral | BCM | Active | Driver | Evidence | Confirmed |
|---|---|---|---|---|---|
| DS18B20 1-Wire data | 4 | n/a | `w1-gpio` | manual p3, and the specification agrees | no |
| IR receiver output (LFN0038K) | 18 | low | `gpio-ir-recv` | manual p3, and the specification agrees | no |
| LED1 | 26 | high | `gpio-leds` | manual p3, and the specification agrees | no |
| Joystick, push | **20** | low | `gpio-keys-polled` | manual p3. The specification puts this on the expander | no |
| PCF8574 INT | **21** | low | unused by default | manual p3. The specification says it may not be routed | no |
| CP2102 to the Pi | 14, 15 | n/a | `pl011` | **inferred** | no |
| Sensor header D0..D3 | 5, 6, 13, 12 | n/a | unbound | manual p3 | no |

**The DS18B20 is not on the board.** Chapter 13: the sensor "is included in
the scope of delievery, must be connected seperately and is not on the
board", into the 3-pin 1-Wire header, flat side facing the display. So an
empty `/sys/bus/w1/devices` has two very different causes and the
verification script has to tell them apart: no `w1_bus_master1` at all
means the overlay or the kernel; a master with
`w1_master_slave_count` of 0 means no probe is plugged in, or no pull-up.

**Whether the 1-Wire header has a pull-up is not documented.** Waveshare's
Explorer 700 fits 4.7 kOhm on the data line. The overlay enables the SoC's
internal pull-up as well, which is about 50 kOhm and therefore changes a
fitted 4.7 kOhm by about eight percent and rescues the case where none is
fitted. It is an overlay parameter either way.

**GPIO14 and GPIO15 are inferred, not read.** The block diagram does not
draw the CP2102's Pi-side signals at all. The inference is from chapter 6,
which warns that "The serial port of the Raspberry Pi 3B is not available
because pin14 and 15 are connected with its own Bluetooth" and then tells
you to enable the serial hardware anyway: those two pins are only worth
mentioning in a manual for this board if the onboard bridge is on them. A
login prompt on the PC confirms it and is acceptance criterion 8 regardless.

## PCF8574 expander lines

The manual's block diagram labels the expander's pins with net names and
then shows where those nets go. Both halves are reproduced, because the
join is where the specification went wrong.

| Line | Net | Goes to | Driver | Evidence | Confirmed |
|---|---|---|---|---|---|
| P0 | A | Joystick **Left** | `gpio-keys-polled` | manual p3 | no |
| P1 | B | Joystick **Up** | `gpio-keys-polled` | manual p3 | no |
| P2 | C | Joystick **Down** | `gpio-keys-polled` | manual p3 | no |
| P3 | D | Joystick **Right** | `gpio-keys-polled` | manual p3 | no |
| P4 | LED2 | LED2 | `gpio-leds` | manual p3 | no |
| P5 | L3 | button L3, on the back of the board | none | manual p3 | no |
| P6 | L4 | button L4, on the back of the board | none | manual p3 | no |
| P7 | Buzz | buzzer input | `gpio-beeper` | manual p3 | no |

The specification's version was P0 to P4 as up, down, left, right, press.
**Three of the four directions differ and the fifth key is on the SoC.**

This is the row most worth checking by hand rather than by document,
because it is read off a rendered page at screen resolution and because
`evtest` plus a thumb settles it in under a minute. It is also the failure
that hides best: a joystick whose axes are permuted works, responds and is
wrong.

**L3 and L4 are left unbound on purpose.** Two buttons are silkscreened on
the back of the board and wired to P5 and P6. They are not in the
specification's eleven peripherals, they have no documented function, and
the manual's diagram draws its arrows out of the expander rather than into
it, which would make them outputs. The PCF8574 is quasi-bidirectional so
the diagram cannot settle it. Binding them as keys on a guess would put two
keys into the input device that might be driving something instead.
`gpioget` on both while pressing is the cheap answer and it is in
`docs/BRINGUP.md` as an optional step.

## PCF8591 analog inputs

| Channel | Connected to | Evidence |
|---|---|---|
| AIN0 | screw terminal position 1, and sensor header A0 | manual p3 |
| AIN1 | screw terminal position 2, and sensor header A1 | manual p3 |
| AIN2 | screw terminal position 3, and sensor header A2 | manual p3 |
| AIN3 | screw terminal position 4, and sensor header A3 | manual p3 |
| AOUT | screw terminal position 5, marked DOUT | manual p3 |

**There is nothing on board for the ADC to measure.** The specification
speculated about a potentiometer, a light-dependent resistor and a
thermistor "on some board revisions". On this one all four inputs leave the
board.

That changes what a reading means. Four floating CMOS inputs produce four
plausible, drifting, non-zero numbers, and a verification script that
prints them without saying so is manufacturing evidence. `explorer-verify`
reports the ADC as present and its inputs as unterminated, and reports a
measurement only for a channel the operator has declared wired.

## Not used by this overlay

| Thing | Why not |
|---|---|
| Sensor header D0 to D3, on GPIO5, 6, 13, 12 | General purpose header pins with nothing attached. They belong to whatever is plugged into them, which is Project 13's problem |
| Screw terminal | Same |
| L3, L4 buttons | Direction unknown, see above |
| PCF8574 INT on GPIO21 | Available and deliberately unused. [DESIGN.md](DESIGN.md) has the argument; [BRINGUP.md](BRINGUP.md) has the four-line source change that uses it, and the test to run first |

## Summary: what is confirmed

**Nothing.** Every row above is `manual` or `inferred`, and the column
exists so that this sentence can be written honestly rather than implied by
an absence. The board has not been powered with this overlay on it.

The first bring-up session fills the column, and the order that fills the
most rows for the least effort is in [BRINGUP.md](BRINGUP.md): `i2cdetect`
settles four addresses in one command, `evtest` settles five joystick rows
in one minute, and a login prompt settles the console.
