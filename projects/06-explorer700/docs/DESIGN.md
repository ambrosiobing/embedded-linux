# Design: Project 06, the Explorer 700 bound by one overlay

Written before any recipe, which is the order Project 15 established and
Project 04 confirmed. The value of writing it first is not the document. It
is that the specification and the hardware get read against each other
while both are still cheap to change, and on this project that turned out
to matter more than on any previous one: **five of the specification's
eleven rows are wrong for the board actually on the bench**, and one of
them is wrong in a way no amount of careful implementation would have
rescued.

Related: [BRINGUP.md](BRINGUP.md), [pin-map.md](pin-map.md),
[bindings.md](bindings.md), [../JOURNAL.md](../JOURNAL.md),
[DECISIONS.md](../../../walkthrough/DECISIONS.md).

## What the product is

One device-tree overlay that binds eleven peripherals of a JOY-iT
RB-Explorer700 to in-tree drivers, so that user space sees `/dev/rtc0`, a
hwmon directory, an IIO device, a DRM device, an input device, a 1-Wire
slave and an LED class device, and never an I2C register.

There is no application. The deliverables are a hardware description, a
document saying how each line in it was established, and a script that
checks every one of them on the board.

That makes this project unusual in the set in a way worth stating plainly:
**its entire risk is in the accuracy of about twenty numbers.** Nothing
here is algorithmically difficult. A wrong GPIO number produces a joystick
that reports Left when pushed Up, or an LED that never lights, or a 1-Wire
bus with no slaves, and every one of those reads as a driver problem to
whoever meets it next.

## The evidence, and what it overturned

The specification's pin-map table is explicitly labelled as hypothesis:
"Treat every GPIO number as a hypothesis until it is checked against the
schematic". Joseph supplied the vendor manual, which is the document that
table was waiting for:

> Joy-it, RB-Explorer700 manual, published 16 November 2020.
> `https://www.joy-it.net/files/files/Produkte/RB-Explorer700/RB-Explorer700-Manual-16.11.2020.pdf`

Its page 3 is a per-peripheral block diagram with the Raspberry Pi BCM
numbers on every signal, and page 2 states the convention: "All pins listed
here refer to the GPIO/BCM pins of the Raspberry Pi." That is the primary
source for everything in [pin-map.md](pin-map.md).

Five rows of the specification do not survive it.

| # | Specification says | The manual shows | Cost of not having checked |
|---|---|---|---|
| 1 | OLED on **I2C1 at 0x3C**, driver `ssd1307fb`, output on `/dev/fb1` | OLED on **SPI0**: CS on GPIO8, D/C on GPIO16, RESET on GPIO19, clock and data on SPI0 | Total. `FB_SSD1307` is `depends on FB && I2C` in the kernel source, so the specified driver cannot bind an SPI panel at all, at any address, with any property set |
| 2 | Pressure sensor **BMP180 at 0x77**, `bosch,bmp180` | **0x76**, and the part is called BMP280 twice and BMP180 once in the same manual | A node that never probes, and a blank row in the acceptance table |
| 3 | Joystick on expander **P0..P4 = up, down, left, right, press** | **P0=Left, P1=Up, P2=Down, P3=Right**, and **press is not on the expander**: it is on GPIO20 | Three of five directions reported wrong, and a fifth key that simply does not exist. This is the failure that looks most like a working system |
| 4 | Expander interrupt "not necessarily routed to a Pi GPIO", so use `gpio-keys-polled` | **INT is on GPIO21** | Nothing breaks. The specification's own stretch goal becomes available on day one instead |
| 5 | PCF8591 inputs "tied on some board revisions to a potentiometer, an LDR and a thermistor" | AIN0..AIN3 go to a **screw terminal and a header**, and nothing else | Four floating inputs read as four working measurements. A number that is really noise is worse than a blank |

Row 1 is the one that justifies the whole practice. Reading the
specification and writing the recipe would have produced an I2C node at an
address where nothing answers, bound to a driver that physically cannot
drive this display, and the debugging would have started at the overlay
syntax and the bus speed rather than at the bus.

Row 5 is the one that would have shipped. Floating CMOS inputs produce
plausible, drifting, non-zero readings.

## What is still a hypothesis after reading the manual

Honesty about the remaining gaps is the point of this section, because the
temptation after finding a good source is to treat everything in it as
settled.

| Open question | Why it is still open | What settles it, and how fast |
|---|---|---|
| Is the pressure part a BMP180 or a BMP280? | The manual says both. Page 2 calls it "BMP280: pressure sensor", chapter 11 is titled "BAROMETER - BMP280" and uses Adafruit's BMP280 library, and the page 3 block calls it "BMP 180" | The driver itself. Both are `bmp280` with different chip IDs; a mismatch is a probe failure naming the ID it read. One boot |
| Is the address 0x76 or 0x77? | The manual says 0x76; the specification says 0x77; the part supports both by a pin strap | `i2cdetect -y 1`. Seconds, and it is step 1 of the bring-up |
| Which joystick contact is which direction? | Read off a rendered page of a PDF at screen resolution, not off a schematic net list | `evtest` and a thumb. Under a minute, and it is the only way to be sure regardless of the source |
| Are L3 and L4 inputs or outputs? | Two buttons are silkscreened on the back of the board and the manual wires them to expander P5 and P6, but its block diagram draws arrows out of the expander, not into it | `gpioget` on both lines while pressing. The expander is quasi-bidirectional, so the wrong guess costs nothing but a wrong label |
| Does the 1-Wire header carry a pull-up resistor? | Not shown. Waveshare's Explorer 700 fits 4.7 kOhm; whether this clone does is not stated | `w1_master_slave_count`. If it is 0 with a probe fitted, the pull-up is the first suspect |
| Is the CP2102 on GPIO14 and GPIO15? | Inferred, not read. The block diagram does not draw the CP2102's Pi-side signals. The inference is from chapter 6's note that "pin14 and 15 are connected with its own Bluetooth" on a 3B, which is only a reason to mention them if the bridge uses them | A login prompt on the PC. It is acceptance criterion 8 either way |

Every one of those is recorded in [pin-map.md](pin-map.md) with the same
distinction the specification asked for: documented, versus confirmed, and
by what method.

## Architecture

Redrawn from the specification's `p06_arch` figure, corrected for the OLED
bus.

```
  RB-Explorer700                     Raspberry Pi 3                user space
  ------------------------------     -------------------------     ------------------

  DS3231  --------.
  PCF8574 -------- +--- I2C1 ------> rtc-ds1307                --> /dev/rtc0
  PCF8591 --------'    (GPIO2/3)     gpio-pcf857x              --> /dev/gpiochipN
  BMP280  --------'                  pcf8591                   --> /sys/class/hwmon
                                     bmp280                    --> /sys/bus/iio

  SSD1306 -------------- SPI0 -----> ssd130x-spi (DRM)         --> /dev/dri/card0
    CS   GPIO8  (CE0)                                              /dev/fbN via the
    D/C  GPIO16                                                    fbdev emulation
    RES  GPIO19
    SCLK GPIO11, MOSI GPIO10

  DS18B20 -------------- GPIO4 ----> w1-gpio + w1_therm        --> /sys/bus/w1/devices
  LFN0038K ------------- GPIO18 ---> gpio-ir-recv + NEC/RC5    --> /dev/input, /sys/class/rc
  LED1 ----------------- GPIO26 ---> gpio-leds                 --> /sys/class/leds
  Joystick push -------- GPIO20 ---.
  Joystick U/D/L/R ---- P1/P2/P0/P3 +-> gpio-keys-polled       --> /dev/input/eventN
  LED2 ----------------- P4 -------> gpio-leds                 --> /sys/class/leds
  Buzzer --------------- P7 -------> gpio-beeper               --> /dev/input/eventN, EV_SND
  L3, L4 --------------- P5, P6 ---> (unbound: see pin-map)
  PCF8574 INT ---------- GPIO21 ---> (available, not used by default)

  CP2102 --------------- GPIO14/15 -> pl011 (getty)            --> COMx on the PC
```

Two things in that picture are the design, rather than the hardware.

**The joystick's fifth key is on a different controller from the other
four**, and it is in the same input device anyway. `gpio-keys-polled` polls
descriptors, and a descriptor from an I2C expander and one from the SoC are
the same kind of object to it. Splitting them into two nodes would have
produced two event devices for one physical joystick, which every consumer
of this project, the specification's own acceptance criterion included,
would then have to know about.

**The expander's interrupt is deliberately unused in the default
configuration**, and the wire that would use it is described in
[pin-map.md](pin-map.md) and left for a parameter. The reason is in the
ownership table below.

## Ownership

The table that earns its place, because the failures it prevents are the
ones that look like something else.

| Resource | Owner | Who must not touch it | Why it matters here |
|---|---|---|---|
| I2C1, GPIO2 and GPIO3 | the kernel's `i2c-bcm2835`, enabled by `dtparam=i2c_arm=on` | any user-space `smbus` program, which is what the vendor demo code is made of | The whole argument of the project. Two I2C masters on one bus is not a race that fails cleanly; it corrupts transfers on both |
| SPI0, GPIO7 to GPIO11 | `spi-bcm2835`, and the `ssd130x-spi` device on CE0 | anything claiming `spidev` on CE0 | Project 8 shipped an image asking for `spidev` without the controller behind it. Here the opposite mistake is available: `spidev0.0` and the OLED both want chip select 0 |
| GPIO8 (SPI0 CE0) | the SPI controller, as a chip select | the overlay, as a plain GPIO | It is the display's chip select **because the controller drives it**, not because anything in the overlay does. There is no `cs-gpios` line and there should not be one |
| GPIO16, GPIO19 | the `ssd130x-spi` node, as `dc-gpios` and `reset-gpios` | `gpio-leds`, `gpio-keys`, anything else | `dc` is not optional: the driver does `devm_gpiod_get(dev, "dc", ...)` and fails probe without it. `reset` is `_optional` and is wired here, so it is declared |
| GPIO4 | `w1-gpio` | the 1-Wire bus is bit-banged by the kernel, so nothing else may hold this line for a microsecond | A second consumer here does not produce an error. It produces intermittent CRC failures that look like a bad probe or a long cable |
| GPIO18 | `gpio-ir-recv` | the PWM driver, which also wants GPIO18 | On this bench that is a live conflict, not a theoretical one: the specification's own fallback for the buzzer is `pwm-beeper` on GPIO12, 13, 18 or 19, and two of those four are already spoken for on this board |
| GPIO14, GPIO15 | the PL011 and its `getty`, once `disable-bt` moves the radio off it | any project wanting the UART for a peripheral | Project 17's design document has the same row with the opposite conclusion, and the two are not in the same image |
| GPIO20, GPIO26 | `gpio-keys-polled` and `gpio-leds` | each other | Both are plain SoC lines and the failure of swapping them is a key that never fires and an LED that flickers when you push the stick |
| PCF8574 lines P0..P7 | the expander's gpiochip, consumed by `gpio-keys-polled`, `gpio-leds` and `gpio-beeper` by phandle | user space through `/dev/gpiochipN` | A line claimed by a kernel consumer is not available to `gpioset`, which is correct and will look like a permissions bug to somebody trying the vendor demo |
| PCF8574 INT, GPIO21 | **nobody, by default** | see below | This is the entry worth the table |
| `/dev/rtc0` and the system clock | `rtc-ds1307`, plus systemd | `fake-hwclock`, which is not in this image | Two things restoring a clock at boot is the classic version of this bug and it is why the specification says to disable the fake one |

**Why the interrupt line is owned by nobody.** GPIO21 is wired to the
expander's INT output and the driver supports it: `gpio-pcf857x` installs
an interrupt chip whenever `client->irq` is set, and `gpio-keys` can then
use expander lines as interrupt sources instead of polling them. That is
the specification's stretch goal and the manual has already answered the
question it was conditional on.

It is still off by default, for the reason the skill file states about
hardware the software cannot verify: **a wrong interrupt is not a failure
that announces itself.** If the line is not actually pulled up, or the
polarity is inverted, or the resistor is unfitted on this revision, the
symptom is a key that works most of the time, and a floating open-drain
input with an edge-triggered handler on it is an interrupt storm rather
than a silence. Polled keys at 20 ms cost one I2C transaction per poll and
are correct without knowing any of that. The cost of the default is
measurable and is recorded; the cost of the alternative is a bug that takes
a week to see.

**And it is not an overlay parameter, which is a deliberate narrowing of
what parameters are for.** The first draft of this document said it would
be one, on the strength of a firmware feature that enables and disables
whole fragments from a parameter. That feature is not documented in the
kernel tree: `arch/arm/boot/dts/overlays/README` in `rpi-6.6.y` is 258 KB
of parameter lists and does not mention `__overrides__` at all, and the
authoring syntax lives only on a documentation website. Writing it from
memory would have produced a parameter that silently does nothing, which is
the exact failure `references/traps.md` opens with for Kconfig symbols.

So the rule this project adopts: **a parameter covers what a board revision
changes, and a source edit covers what the design changes.** Pin numbers,
the pressure sensor's address, the poll interval, the pull settings and the
beeper's polarity are properties of the hardware in front of you and are
parameters. Polled versus interrupt-driven keys is a decision about the
driver, and it is a four-line diff printed in full in
[BRINGUP.md](BRINGUP.md), taken after `gpiomon` on GPIO21 has shown that
edges actually arrive.

## Data flow

The specification's ASCII figure, corrected in the same five places.

```
  device       DT node (overlay)          driver            user space
  -----------  -------------------------  ----------------  ----------------------------
  DS3231       i2c1/rtc@68                rtc-ds1307        /dev/rtc0, hwclock
  PCF8574      i2c1/gpio@20 (label)       gpio-pcf857x      /dev/gpiochipN, 8 lines
    joystick   /keys -> &pcf8574 0..3     gpio-keys-polled  /dev/input/eventN
               + &gpio 20                 (one node, five keys)
    LED2       /leds -> &pcf8574 4        gpio-leds         /sys/class/leds/explorer:led2
    buzzer     /beeper -> &pcf8574 7      gpio-beeper       /dev/input/eventN, EV_SND
  PCF8591      i2c1/adc@48                pcf8591 (hwmon)   /sys/class/hwmon/hwmonN/in0_input
  BMP280       i2c1/pressure@76           bmp280 (iio)      /sys/bus/iio/devices/iio:deviceN
  SSD1306      spi0/oled@0                ssd130x-spi (drm) /dev/dri/card0, /dev/fbN
  DS18B20      /onewire (GPIO4)           w1-gpio, w1_therm /sys/bus/w1/devices/28-*/temperature
  LFN0038K     /ir-receiver (GPIO18)      gpio-ir-recv      /dev/input/eventN, /sys/class/rc/rc0
  LED1         /leds/led1 (GPIO26)        gpio-leds         /sys/class/leds/explorer:led1
  CP2102       &uart0 + disable-bt        pl011             /dev/ttyAMA0 getty, COMx on the PC
```

## How the address of the vendor prefix works, since one row depends on it

`pcf8591` is a hwmon driver with **no `of_device_id` table at all**. It has
only an `i2c_device_id` whose name is `pcf8591`. A node in an overlay
therefore looks like it cannot bind, and it does bind, through a mechanism
worth naming because the next person to read the driver will have the same
doubt:

`of_i2c_get_board_info` fills `info->type` from
`of_alias_from_compatible`, which is four lines in `drivers/of/base.c`: it
takes the first compatible string, finds the comma, and copies what is
after it. So `nxp,pcf8591` becomes the client name `pcf8591`, and
`i2c_match_id` matches it against the driver's table.

This is checked in [bindings.md](bindings.md) with the file and line rather
than asserted, because the specification asserted it and an assertion that
happens to be right is indistinguishable from one that is not.

## Kernel configuration

Opt in, behind `BENCH_EXPLORER_KERNEL`, following the pattern the bbappend
already uses five times. The reason to opt in here is the OLED: binding it
means DRM, and DRM in an image that has no display is a subsystem, a
`/dev/dri` node and a backlight class for nobody.

Every symbol was checked against the 6.6 source before it was written, per
`references/traps.md`, and the check is recorded in
[evidence/kconfig-check.txt](evidence/kconfig-check.txt). The one that
matters most is the negative result:

```
FB_SSD1307   depends on FB && I2C      <- cannot bind an SPI panel. Not used.
DRM_SSD130X_SPI   depends on DRM_SSD130X && SPI
```

## What this design does not claim

- **Nothing here has been on hardware.** Every measurement column in
  [../README.md](../README.md) is blank, and stays blank until it is taken.
- The IR keymap in `config/rc_keymap.toml` cannot be written in advance.
  Scancodes are a property of a remote, not of a protocol, so the file
  shipped is a worked example with the scancodes from the manual's own
  output and a comment saying to replace them.
- The overlay is written for a Raspberry Pi 3. `compatible = "brcm,bcm2835"`
  is the family string every Pi overlay uses and the firmware accepts it on
  a 4 as well, but the CP2102 console argument depends on `disable-bt`,
  which is a different trade on a board whose Bluetooth is wanted.
