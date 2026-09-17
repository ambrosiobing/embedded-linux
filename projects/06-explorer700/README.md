# Project 06: the Explorer 700, bound by one device tree overlay

**Board:** Raspberry Pi 3 with a JOY-iT RB-Explorer700. **Theme:** device
tree composition, in-tree drivers, and the rtc, gpio, hwmon, iio, drm, w1,
rc, leds and input subsystems.

Eleven peripherals, no driver of our own and no vendor library at all. The
vendor's software for this board is Python talking to `smbus` and
`RPi.GPIO`; every one of these parts already has a driver in the kernel,
so the engineering task is to describe the hardware once and let the
kernel bind them. The product is a hardware description plus the evidence
for each number in it.

That makes the risk unusual for this repository. Nothing here is
algorithmically hard. **The entire risk is the accuracy of about twenty
numbers**, and a wrong one does not crash: it gives a joystick that reports
Left when pushed Up, or an LED that never lights, and both read as driver
problems to whoever meets them next.

## The specification is wrong about this board in five places

The project specification labels its own pin table a hypothesis and asks
for it to be checked against the schematic. The vendor manual is that
check, and it overturns five rows. One of them could not have been
rescued by careful implementation:

| Specification | This board | Consequence |
|---|---|---|
| OLED on I2C at 0x3C, driver `ssd1307fb` | **OLED on SPI0**: CS GPIO8, D/C GPIO16, RESET GPIO19 | `FB_SSD1307` is `depends on FB && I2C` in the kernel source. The named driver cannot bind an SPI panel at any address with any property set |
| BMP180 at 0x77 | **0x76**, and the manual calls the part a BMP280 twice and a BMP180 once | A node that never probes |
| Joystick P0..P4 = up, down, left, right, press | **P0=Left, P1=Up, P2=Down, P3=Right**, and press is on **GPIO20** | Three directions permuted and a fifth key that is not where it is looked for |
| Expander interrupt "not necessarily routed" | **INT is on GPIO21** | The specification's stretch goal is available on day one |
| ADC inputs maybe on a pot, an LDR and a thermistor | All four leave through a **screw terminal** | Four floating inputs that read as four working measurements |

[docs/DESIGN.md](docs/DESIGN.md) has the argument,
[docs/pin-map.md](docs/pin-map.md) has every line with its evidence, and
[docs/bindings.md](docs/bindings.md) cites the driver source for each
binding rather than recalling what it looks like.

## What a clone gives you

**No image is published.** This directory carries the recipes, the overlay,
the programs, the tests and the evidence.

**If the software is what interests you, no hardware is required.** Two
suites run on any machine in seconds, 96 assertions between them:
`explorer-verify` against a tree of directories shaped like sysfs,
including all six ways this board fails that look identical from a
distance; and the overlay against the pin map, the kernel fragment and the
image recipe, which is where a document and the thing it describes are
stopped from drifting apart.

**If you want to run it, you need the HAT.** An RB-Explorer700 or a
Waveshare Explorer 700, a Pi 3, a USB cable for the CP2102 and any IR
remote.

## What this project adds to the repository

| Piece | What it is |
|---|---|
| `meta-bench/recipes-bench/bench-explorer700/` | the overlay: five fragments, eleven peripherals, eight parameters |
| `meta-bench/recipes-kernel/linux/files/explorer.cfg` | 26 symbols, every one of them `=y`, and the reason |
| `meta-bench/recipes-bench/bench-explorer/` | `explorer-verify`, `explorer-oled`, `explorer-beep`, the udev rule, the keymap example |
| `meta-bench/recipes-core/images/bench-explorer-image.bb` | the image, and **no** `kernel-module-*` lines at all |
| `kas/bench-explorer.yml` | Pi 3, both buses on, `disable-bt` for the console, no DSI panel |
| two suites under `tests/` | 96 assertions, no hardware |

## Running it

```sh
./go check                      # the suites, no board and no HAT
./go ksym -f explorer           # after the kernel unpacks, before it compiles
./go explorer                   # bench-explorer-image
./go flash /dev/sdX
```

On the board, in the order in [docs/BRINGUP.md](docs/BRINGUP.md), which is
sequenced so that each step fills as many rows of the pin map as it can for
the effort it costs:

```sh
i2cdetect -y 1                  # four addresses in one command
explorer-verify                 # eleven rows, the acceptance test
evtest /dev/input/explorer-joystick
explorer-oled
ir-keytable -p nec,rc-5,rc-6 -t
```

## Acceptance

Two columns of meaning. **Configured** is what a file says; **measured** is
what a board did. They are kept apart on purpose, and the second column is
empty because the HAT has not been powered with this overlay on it.

| # | Criterion | Configured | Measured |
|---|---|---|---|
| 1 | `explorer-verify` prints eleven rows with nothing `absent` after a clean boot | overlay binds eleven peripherals; 45 assertions against a fake sysfs | |
| 2 | `hwclock -r` matches `date` within 2 s after a reboot with the network down | `rtc-ds1307` on `maxim,ds3231`; no `fake-hwclock` in the image | |
| 3 | `evtest` reports the five joystick keys with the right codes, and the buzzer sounds on `SND_BELL` | five keys, five distinct codes, one input device across two GPIO controllers | |
| 4 | `ir-keytable -t` decodes the remote, and a loaded keymap gives named keys | `gpio-ir-receiver` on GPIO18, three protocol decoders built in | |
| 5 | DS18B20 changes by more than 2 degrees in a minute held between two fingers; BMP280 within 3 kPa of the local report | `w1-gpio` on GPIO4 with the internal pull-up; `bosch,bmp280` at 0x76 | |
| 6 | Text written to the framebuffer is readable, and `con2fbmap` moves the console there | `ssd130x-spi` plus `DRM_FBDEV_EMULATION`; `explorer-oled` finds the node by name | |
| 7 | `docs/pin-map.md` has a confirmed entry for every GPIO, with the method | the column exists and **every row says no** | |
| 8 | A login prompt on the PC over the CP2102 | `disable-bt` ahead of the overlay, console at 115200 | |

**Criterion 7 is the honest one and it is worth reading twice.** The
column exists so that "nothing is confirmed yet" can be a stated fact
rather than an absence a reader has to notice. The evidence behind every
pin is a vendor manual's block diagram, which is the best source short of a
net list and is not a net list.

### Two deviations from the specification's wording

**Criterion 6 names `/dev/fb1` and this project does not.** With `vc4`
absent from the image there may be no HDMI framebuffer at all, which makes
the OLED `fb0`. `explorer-oled` and `explorer-verify` both find it by
driver name instead, and the specification's 1 bit per pixel layout is also
wrong for the DRM path: `drm_fbdev_generic_setup(drm, 32)` makes it 32 bits
per pixel and the kernel converts.

**The LED class device is `explorer:led1`, not `explorer:user`.** There are
two LEDs on this board and "user" does not distinguish them, so they are
named for the silkscreen. The second, `explorer:led2`, is on expander line
P4, which is where the specification expected the joystick's fifth key.

## What has not been done

- **Nothing has been on hardware.** No build has been run either: the
  symbols in `explorer.cfg` are checked against the 6.6 source
  ([docs/evidence/kconfig-check.txt](docs/evidence/kconfig-check.txt)) and
  not yet against a `.config`, which is a different question with a
  different tool.
- The IR keymap cannot be written in advance. Scancodes are a property of a
  remote, so the shipped file is an example with the manual's own output in
  it and a comment saying to replace it.
- L3 and L4, two buttons on the back of the board, are left unbound.
  Their direction is not established and binding them on a guess would put
  two keys into the input device that might be driving something instead.
- Interrupt-driven keys are available and off.
  [docs/BRINGUP.md](docs/BRINGUP.md) has the four-line change and the test
  to run before making it.

## Journal

[JOURNAL.md](JOURNAL.md) is what actually happened, including the things
that were wrong first. The entries worth reading if you read only two are
3, on a driver that could not have worked, and 6, on the two defects the
test suite found in its own subject on the first run.
