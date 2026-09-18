# Project 07: a 3.5 inch SPI display as a DRM panel with touch

**Board:** Raspberry Pi 3B+. **Theme:** DRM/KMS tiny drivers, the input
subsystem, device tree overlays for SPI slaves, fbcon.

The usual way to install a Waveshare 3.5 inch RPi LCD (A) is to run a
vendor script that copies a precompiled overlay and an `fbtft`
configuration into `/boot`. It works, it teaches nothing, and it produces a
framebuffer that no Wayland compositor can use.

This project does the same job through the modern path. The panel becomes a
DRM/KMS device driven by the in-kernel `ili9486` tiny driver, the resistive
touch controller becomes an evdev input device through `ads7846`, and both
are described by an overlay written here and explicable line by line.

Among the twenty projects this is the only one that goes below the graphics
stack. Project 13 builds a Wayland kiosk on a DSI touchscreen and takes DRM
for granted; this one is the driver side, including the difference between
a framebuffer that is memory and a framebuffer that is a stream of SPI
transactions with damage tracking. Project 6 introduced the overlay
technique for I2C peripherals; this applies it to two SPI chip selects on
one bus, one of them with an interrupt line.

**State: software complete, no board work yet.** The image has never been
built and no board has been powered on. Everything below that says
"measured" says so; everything else says what it actually is.

## What makes this panel not routine

The board does not wire the ILI9486's serial interface to SPI. It carries
shift registers that turn the SPI stream into the controller's 16-bit
parallel bus, so every command and every data byte has to be sent as a
16-bit word. That one hardware fact decides the whole software stack:

- the generic `panel-mipi-dbi` driver cannot drive it, because it sends
  8-bit commands
- the `ili9486` tiny driver can, because its command function widens every
  byte before handing it to the MIPI DBI helpers
- the `fbtft` fallback `fb_ili9486` works for the same reason by a
  different route, `regwidth = <16>`

Read out of the driver rather than recalled:

```
drivers/gpu/drm/tiny/ili9486.c, v6.12

static const struct of_device_id ili9486_of_match[] = {
        { .compatible = "waveshare,rpi-lcd-35" },
        { .compatible = "ozzmaker,piscreen" },
        {},
};
```

The full reasoning, with all four design figures, is in
[docs/DESIGN.md](docs/DESIGN.md).

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-bench/bench-lcd35a-overlay/` | The overlay, compiled with `dtc-native` and deployed to the FAT boot partition |
| `meta-bench/recipes-bench/bench-lcd35a/` | `drmfill`, `lcd35a-corners`, `lcd35a-verify` |
| `meta-bench/recipes-kernel/linux/files/lcd35a.cfg` | Nine kernel symbols, all `=y`, behind `BENCH_LCD35A_KERNEL` |
| `meta-bench/recipes-core/images/bench-lcd35a-image.bb` | The image, from `bench-image` |
| `kas/bench-lcd35a.yml` | Machine, `config.txt`, the kernel command line |
| `tests/lcd35a-overlay-test.sh` | 48 assertions across the overlay, fragment, image, kas file and design |
| `tests/lcd35a-corners-test.sh` | 15 assertions on the calibration arithmetic |

## Running it

```sh
./go check          # everything provable without a board
./go lcd35a         # build bench-lcd35a-image for the Raspberry Pi 3B+
./go flash          # write the card
```

Then on the board, over SSH:

```sh
lcd35a-verify       # what can be checked from the board itself
drmfill             # paint a gradient, finding the panel by driver name
lcd35a-corners -h   # how to calibrate touch
```

## Acceptance criteria

The six criteria this project is specified against, written out in full so
that nothing outside this repository has to be consulted to judge whether
it is finished. "Configured" means a file says so; "measured" means a board
did so.

| # | Criterion | State |
|---|---|---|
| 1 | `ls /sys/bus/spi/drivers/ili9486/` shows `spi0.0` and `ls /sys/bus/spi/drivers/ads7846/` shows `spi0.1` after a cold boot, with no vendor script involved | **Configured.** The overlay binds both and disables both `spidev` nodes; asserted as text in `tests/lcd35a-overlay-test.sh`, and `lcd35a-verify` checks it on the board. Never observed |
| 2 | A login prompt appears on the panel within 10 s of power-on, and `dmesg` scrolls readably in the 8x8 font | **Configured, with one guess in it.** `fbcon=map:1 fbcon=font:VGA8x8` is on the kernel command line, and the `1` assumes the panel is `fb1`, which is true with `vc4` active and false without it. `con2fbmap` settles it at run time. Not measured |
| 3 | `modetest -v` reports at least 8 frames per second at 32 MHz, and the achieved SPI clock matches the overlay | **Not measured.** `libdrm-tests` is in the image. The ceiling is arithmetic: a 480x320 RGB565 frame is 2.46 Mbit, so 32 MHz allows about 12 full frames per second and nothing beats that |
| 4 | `drmfill` paints the gradient from an SSH session, and a run against the other card fails with a clear error rather than painting the wrong output by accident | **Half met without a board.** `drmfill` finds the panel by driver name and refuses an explicit device whose driver is not `ili9486`, so the second half is structural rather than hoped for. The painting has never happened |
| 5 | After calibration, `libinput debug-events` reports each of the four corners within 3 pixels and the centre within 2 pixels | **Not measured, and it needs a finger.** The arithmetic that turns four raw readings into a matrix is `lcd35a-corners`, which is fully tested |
| 6 | The overlay compiles without warnings under `dtc -@`, and the `speed`, `rotate` and `swapxy` overrides take effect from `config.txt` | **Half met.** The three overrides are asserted present. The compile is asserted by the test suite only where `dtc` exists, which is CI and not the authoring laptop. Whether the overrides take effect needs a board |

## What is tested without hardware

Project 7 has almost no application. Its product is a hardware description
and a kernel configuration, and every way it can fail is a way a build
cannot see: a fragment line Kconfig drops, a device tree property read at
the wrong width, a pin claimed by two drivers. None of those produce an
error anywhere.

| Check | Command | Covers |
|---|---|---|
| Overlay, fragment, image and design against each other | `sh tests/lcd35a-overlay-test.sh` | Both `spidev` nodes disabled, `/bits/ 16` on all six `ti,*` properties, every symbol `=y`, `bench-status` removed, the driver name agreeing across three files, every GPIO present in the design's wiring table, `dtc -@` where `dtc` exists |
| Calibration arithmetic | `sh tests/lcd35a-corners-test.sh` | The identity case, the overlay's own limits, five refusals, and the warning that fires when the matrix says the overlay is wrong |
| Compile | `./go check` | `drmfill` with `-Werror` against the host libdrm |

Each of the four sharpest assertions was proved by breaking the thing it
checks and watching it fail, then restoring it. A check that has never
failed is not a check that is working.

## The three sharp edges, and what guards each

| Edge | What it does when you get it wrong | Guard |
|---|---|---|
| `spidev0` or `spidev1` left enabled | The panel node never binds. `dmesg` says only that chip select 0 is already in use, which does not sound like what it is | Two assertions, one per node, because disabling only the first loses touch and keeps the panel |
| A `ti,*` property without `/bits/ 16` | The binding declares 16-bit cells and the driver reads with `device_property_read_u16`. Without the prefix it reads the wrong half, so touch reports nonsense rather than failing to probe | One assertion per property, all six |
| `CONFIG_HWMON=m` | `TOUCHSCREEN_ADS7846` is `depends on HWMON = n \|\| HWMON`, so the `=y` line is not a valid configuration, Kconfig drops it silently, and there is no touch input with nothing in any log | `CONFIG_HWMON=y` pinned in the fragment, explained in the fragment, the bbappend and the design, and asserted by the suite |

The third is reasoning from the Kconfig stanza, not an observation. Nobody
has read what `HWMON` is in the Raspberry Pi 3 defconfig, because that
needs a kernel tree. `./go ksym -f lcd35a` on the build host settles it.

## Where this differs from the original plan

The project was scoped against Raspberry Pi OS. Six steps do not survive a
Yocto image, and the translation is a table in
[docs/DESIGN.md](docs/DESIGN.md). Three further differences are choices
rather than translations:

1. **`drmfill` finds the card instead of taking a path.** The original
   opens `/dev/dri/card1`, which is the panel when `vc4-kms-v3d` is active
   and the HDMI output when it is not. A hard-coded path is a program that
   paints the wrong output on a differently configured board, silently.
   This one matches on the driver name and refuses a device that is not the
   panel, which is also what makes criterion 4 checkable.
2. **Calibration is a libinput matrix, and no rule is shipped.** The
   classic answer is `tslib`: `ts_calibrate` writes `/etc/pointercal`,
   which tslib programs read and nothing else does. A libinput matrix in a
   udev property is applied by every compositor, which makes calibration
   data rather than a patched application. No rule file is shipped, because
   the matrix is a property of one panel and one rotation; shipping the
   identity would change nothing and look like calibration.
3. **`bench-status` is removed from this image.** Project 1's status daemon
   holds GPIO17, which is this panel's pen-down interrupt. Two drivers
   asking for one line is a probe failure on whichever loses, and the loser
   would look like a touch fault rather than a conflict.

## Deferred, with reasons

| Item | Why | Where it goes |
|---|---|---|
| The `fbtft` comparison | The specification offers `fb_ili9486` as a fallback and asks for a written comparison of both paths with measured frame rates and CPU load. It needs the board twice, once per driver, and the board has not been powered on once | `docs/fbdev-vs-drm.md`, after the first boot |
| The serial console | The panel covers header pins 8 and 10 when plugged on, so there is no USB/TTL console. SSH over Ethernet is the console here, which is also the path whose prerequisite is known to work: the serial console has been unproven on this bench since Project 1 for want of a working cable | Jumper wiring, at 16 MHz, if it is ever needed |
| A PWM backlight | The "A" board has no backlight control input at all. The 5 V pin feeds the LED directly | Documented as a limitation, not a task |

## Sources

- Kernel DRM documentation, https://docs.kernel.org/gpu/drm-kms.html
- libinput absolute axes and calibration,
  https://wayland.freedesktop.org/libinput/doc/latest/absolute-axes.html
- Raspberry Pi device trees, overlays and parameters,
  https://www.raspberrypi.com/documentation/computers/configuration.html
- Waveshare 3.5 inch RPi LCD (A),
  https://www.waveshare.com/wiki/3.5inch_RPi_LCD_(A)
