# Design: Project 07, a 3.5 inch SPI panel as a DRM device

Written before any recipe, which is the order Projects 15, 04 and 06
established. The value is not the document. It is that the specification and
the hardware get read against each other while both are still cheap to
change.

On this project that reading has already paid twice, before a single line of
recipe exists:

1. Four kernel symbols were checked against the mainline source rather than
   recalled. All four exist, and one of them carries a dependency that would
   have made a fragment line silently do nothing. See
   [Kernel configuration](#kernel-configuration).
2. The specification is written for Raspberry Pi OS, with `apt`, a vendor
   `/boot` and `dtc` run on the target. None of that exists here. What
   changes and what does not is in
   [What this bench does differently](#what-this-bench-does-differently),
   written down rather than discovered during a build.

Related: [../JOURNAL.md](../JOURNAL.md),
[DECISIONS.md](../../../walkthrough/DECISIONS.md).

## What the product is

One device tree overlay that binds a Waveshare 3.5 inch RPi LCD (A) to two
in-tree drivers, so that user space sees a real DRM device and a real input
device:

| User space sees | Because of | Not because of |
|---|---|---|
| `/dev/dri/cardN`, one connector, one CRTC, one plane | `ili9486`, a tiny DRM driver in mainline | any vendor kernel |
| `/dev/fbN`, usable by `fbcon` | `CONFIG_DRM_FBDEV_EMULATION` on top of that DRM device | `fbtft`, which is staging |
| `/dev/input/eventN` with `ABS_X`, `ABS_Y`, `ABS_PRESSURE` | `ads7846`, in-tree | a userspace touch daemon |

The product is the hardware description and the kernel configuration behind
it. There is no application. The usual way to install this panel is a vendor
script that copies a precompiled overlay and an `fbtft` configuration into
`/boot`; that works and teaches nothing, and it produces a framebuffer that
no Wayland compositor can use.

**What makes this panel interesting rather than routine.** The board does
not wire the ILI9486's serial interface to SPI. It carries shift registers
that turn the SPI stream into the controller's 16-bit parallel bus, so every
command and every data byte has to be sent as a 16-bit word. That single
hardware fact decides the whole software stack:

- the generic `panel-mipi-dbi` driver with a firmware init file cannot drive
  it, because it sends 8-bit commands
- the `ili9486` tiny driver can, because its command function widens every
  byte to 16 bits before handing it to the MIPI DBI helpers, and it carries
  `waveshare,rpi-lcd-35` in its compatible list for exactly this board
- the `fbtft` fallback `fb_ili9486` works for the same reason and by a
  different route, `regwidth = <16>`

Confirmed by reading the driver, not from memory:

```
drivers/gpu/drm/tiny/ili9486.c, v6.12

static const struct of_device_id ili9486_of_match[] = {
        { .compatible = "waveshare,rpi-lcd-35" },
        { .compatible = "ozzmaker,piscreen" },
        {},
};
```

## Acceptance criteria

The six criteria this project is specified against, written out in full so
that nothing outside this repository has to be consulted to judge whether it
is finished. "Configured" means a file says so; "measured" means a board did
so. Nothing below has been measured yet, because no board has been powered
on for this project.

| # | Criterion | State |
|---|---|---|
| 1 | `ls /sys/bus/spi/drivers/ili9486/` shows `spi0.0` and `ls /sys/bus/spi/drivers/ads7846/` shows `spi0.1` after a cold boot, with no vendor script involved | Not started |
| 2 | A login prompt appears on the panel within 10 s of power-on, and `dmesg` scrolls readably in the 8x8 font | Not started |
| 3 | `modetest -v` reports at least 8 frames per second at 32 MHz on a plugged-on panel, and the achieved SPI clock matches the overlay | Not started |
| 4 | `drmfill` paints its gradient from an SSH session, and a second run against the other card fails with a clear error rather than painting the wrong output by accident | Not started |
| 5 | After calibration, `libinput debug-events` reports each of the four corners within 3 pixels and the centre within 2 pixels of the true position | Not started |
| 6 | The overlay compiles without warnings under `dtc -@`, and the `speed`, `rotate` and `swapxy` overrides take effect from `config.txt` | Not started |

Criterion 3 has an arithmetic ceiling worth writing down before measuring
anything, so that a number can be recognised as wrong: a 480x320 RGB565
frame is 2.46 Mbit, so 32 MHz allows about 12 full frames per second and
nothing will beat that. A result far below 8 points at the SPI controller
falling back to interrupt-driven transfers, or at a clock lower than the one
the overlay asked for, and both are visible rather than mysterious.

## Figure 1: System architecture

Two SPI slaves on one bus, two subsystems that never meet in the kernel. The
panel is a DRM device with fbdev emulation on top; the touch controller is
an evdev input device. They share only the bus and the fact that one overlay
describes both.

```
  USER SPACE
  +-------------------+  +-------------------+  +----------------------+
  | modetest, drmfill |  | fbcon / getty     |  | libinput, evtest     |
  | libdrm, dumb bufs |  | /dev/fb1, VT1     |  | calibration matrix   |
  +---------+---------+  +---------+---------+  +-----------+----------+
            | ioctl               | write                   ^ evdev
  ==========|=====================|=========================|===========
  KERNEL    |                     |                         |
            v                     v                         |
  +---------+---------+  +--------+---------+     +---------+---------+
  | DRM core          |  | fbdev emulation  |     | input core        |
  | atomic, damage    |  | /dev/fbN shim    |     | /dev/input/eventN |
  +---------+---------+  +--------+---------+     +---------+---------+
            |                     |                         |
            +----------+----------+                         |
                       v                                    |
            +----------+-----------+              +---------+---------+
            | ili9486 tiny driver  |              | ads7846           |
            | simple pipe          |              | threaded IRQ      |
            | 16-bit commands      |              | X, Y, pressure    |
            +----------+-----------+              +---------+---------+
                       |                                    |
                       v                                    |
            +----------+-----------+                        |
            | MIPI DBI helpers     |                        |
            | shadow buffer        |                        |
            | CASET, RASET, RAMWR  |                        |
            +----------+-----------+                        |
                       |                                    |
                       v                                    |
            +----------+--------------------------+---------+---------+
            | spi-bcm2835    CE0 = panel, CE1 = touch, DMA            |
            +----------+--------------------------+--------------------+
                       | CE0, DC, RST                | CE1      ^ PENIRQ
  =====================|=============================|==========|=======
  WAVESHARE 3.5 INCH RPi LCD (A)                     |          | GPIO17
                       v                             v          |
            +----------+-----------+       +---------+----------+
            | SPI to 16-bit        |       | XPT2046            |
            | parallel bridge      |       | resistive touch    |
            | shift registers      |       | ADS7846 compatible |
            +----------+-----------+       +--------------------+
                       v
            +----------------------+
            | ILI9486  480x320     |
            | RGB565               |
            +----------------------+
```

The bridge is the whole reason this project is not a five line overlay. It
is also why the two halves of the board need different drivers from
different subsystems: the touch controller is wired to SPI directly and is
an ordinary ADS7846, while the panel is behind a parallel bus that only
looks like SPI from the outside.

## Figure 2: Wiring and schematic

The panel's 26-pin socket normally sits straight on header pins 1 to 26. The
table gives the same eleven signals for a jumper-wired setup, which is the
only way to keep the serial console available.

```
  Raspberry Pi 3B+                        3.5 inch RPi LCD (A)
  40-pin header                           26-pin socket
  +---------------------------+           +--------------------------+
  | pin 1  3V3      >---------|-----------|--->  3V3 logic           |
  | pin 2  5V       >---------|-----------|--->  5V backlight        |
  | pin 6  GND      >---------|-----------|--->  GND                 |
  |                           |           |                          |
  | pin 19 GPIO10 MOSI >------|-----------|--->  MOSI  (shared)      |
  | pin 21 GPIO9  MISO <------|-----------|<---  MISO  (touch only)  |
  | pin 23 GPIO11 SCLK >------|-----------|--->  SCLK  (shared)      |
  | pin 24 GPIO8  CE0  >------|-----------|--->  LCD_CS              |
  | pin 26 GPIO7  CE1  >------|-----------|--->  TP_CS               |
  |                           |           |                          |
  | pin 18 GPIO24      >------|-----------|--->  LCD_RS  (DC)        |
  | pin 22 GPIO25      >------|-----------|--->  LCD_RST             |
  | pin 11 GPIO17      <------|-----------|<---  TP_IRQ  (PENIRQ)    |
  +---------------------------+     |     +--------------------------+
                                    |
                            10k pull-up to 3V3
                            on the panel board
```

| Panel signal | Header pin | BCM GPIO | Note |
|---|---|---|---|
| 3V3 logic | 1 | | Controller and bridge supply |
| 5V backlight | 2 | | Backlight LED only. The "A" board has no backlight control input |
| GND | 6 | | Also 9, 14, 20 and 25 when the panel is plugged on |
| TP_IRQ (PENIRQ) | 11 | GPIO17 | Falling edge, pull-up on the panel |
| LCD_RS (data/command) | 18 | GPIO24 | `dc-gpios` |
| MOSI | 19 | GPIO10 | Shared by panel and touch |
| MISO | 21 | GPIO9 | Used by the touch controller only |
| LCD_RST | 22 | GPIO25 | `reset-gpios`, driven low by `mipi_dbi_hw_reset` |
| SCLK | 23 | GPIO11 | Shared |
| LCD_CS | 24 | GPIO8 | SPI0 CE0 |
| TP_CS | 26 | GPIO7 | SPI0 CE1 |

All signals are 3.3 V. The 5 V pin feeds the backlight and nothing else.

**The panel covers the UART pins.** When it is plugged on, header pins 8 and
10 are under its socket, so GPIO14 and GPIO15 are not reachable and the
USB/TTL console does not exist. Two ways out, and they are not equivalent:

| Approach | Console | SPI clock | Cost |
|---|---|---|---|
| Plug the panel on | SSH over Ethernet only | 32 MHz, as specified | No console before the network is up |
| Wire eleven jumpers | USB/TTL on GPIO14/15 works | Lower to 16 MHz | Jumper wires do not carry 32 MHz cleanly; a partially drawn or shifted picture is the symptom |

This bench takes the first. The Pi 3B+ has Ethernet, `bench-image` already
runs DHCP on `eth*` and carries an SSH server, and this project therefore
needs no wireless provisioning at all, which is a first here. The serial
console has been unproven on this bench since Project 1 for want of a
working USB/TTL cable, so choosing the path that does not need one is also
choosing the path whose prerequisite is known to exist.

**Do not stack.** GPIO17, GPIO24 and GPIO25 are used by Project 1 for the
status LEDs and by Project 6 for the Explorer 700. Those boards and this
panel cannot be on the header at the same time.

## Figure 3: Bench layout

```
        +--------------------------------------+
        |   480x320 ILI9486                    |
        |                                      |     Waveshare 3.5 inch
        |   bench login: _                     |     RPi LCD (A)
        |                                      |     socket on pins 1 to 26
        +--------------------------------------+
        | | | | | | | | | | | | |  26-pin socket
        +--------------------------------------+
                      |  plugs straight on
                      v
   +----------------------------------------------+
   |  o o o o o o o o o o o o o o o o o o o o     |  40-pin header
   |  o o o o o o o o o o o o o o o o o o o o     |
   |                                              |        +-----------+
   |  Raspberry Pi 3B+                    [ETH]---|--------| Host PC   |
   |                                              |Ethernet| ssh, scp  |
   |  [microSD]                           [USB]   |        +-----------+
   |                                              |
   +--[micro-USB 5V]------------------[HDMI]------+
                                         |
                                  first boots only,
                                  until fbcon is moved
                                  to the panel
```

HDMI earns its place for exactly one reason: until `fbcon` is mapped to the
panel, it is the only way to see a boot log if the network does not come up.
After that it is removable, and criterion 2 is about the panel rather than
about HDMI.

## Figure 4: From a page flip to SPI transfers

What happens between a user space program drawing something and pixels
changing on the glass. The tiny driver keeps a shadow buffer, copies only
the damaged rectangle, and sends it after addressing a window.

```
  drmfill        DRM core      ili9486 pipe   MIPI DBI      spi-bcm2835   panel
     |               |               |            |              |          |
     |--SetCrtc or-->|               |            |              |          |
     |  atomic commit|               |            |              |          |
     |               |--pipe update->|            |              |          |
     |               |  (old_state)  |            |              |          |
     |               |               |--fb_dirty->|              |          |
     |               |               |  (fb, rect)|              |          |
     |               |               |<--command--|              |          |
     |               |               |  CASET,    |              |          |
     |               |               |  RASET     |              |          |
     |               |               |------ spi_sync ---------->|          |
     |               |               |  DC low, then DC high     |          |
     |               |               |            |              |--CE0---->|
     |               |               |            |              | SCLK,    |
     |               |               |            |              | MOSI     |
     |               |               |            |--RAMWR + --->|          |
     |               |               |            |  pixel words |          |
     |               |               |            |  (DMA)       |--burst-->|
     |               |               |            |              | 32 MHz   |
     |<------------------------ picture updated ------------------------|   |
```

Two notes that the picture cannot carry:

- **Damage clips come from user space, or there are none.** A compositor
  calls `drmModeDirtyFB` after every frame and the driver sends only that
  rectangle. Without a clip list the legacy `SetCrtc` path still triggers a
  full update, so a program that never declares damage works and is slow.
  This is the difference that makes the panel usable at all, and it is why
  `drmfill` calls the dirty ioctl even though its picture would appear
  without it.
- **`ili9486` widens every command and parameter byte to a 16-bit word.**
  That is the bridge quirk from Figure 1, appearing here as the one thing
  the driver contributes that the shared helpers do not.

The input side has no equivalent diagram because it has no equivalent
complexity: `ads7846` takes the pen-down interrupt on GPIO17, samples X, Y
and pressure over CE1, and reports absolute events. Everything interesting
about touch is calibration, which is data and not code.

## Ownership

The table that prevents the commonest class of bug on this bench, two
managers on one resource.

| Resource | Owner | Never touched by |
|---|---|---|
| SPI0 CE0 | `ili9486`, bound by the overlay | `spidev`, which the overlay disables |
| SPI0 CE1 | `ads7846`, bound by the overlay | `spidev`, disabled the same way |
| GPIO17 | `ads7846`, as its pen-down interrupt | `bench-status` of Project 1, which must not be in this image |
| GPIO24, GPIO25 | `ili9486`, as `dc-gpios` and `reset-gpios` | Anything else on the header |
| `/dev/dri/cardN` for the panel | Whatever holds it: `fbcon`, or one DRM client at a time | Two at once. A DRM master is exclusive |
| The active virtual terminal | `fbcon` | DRM test programs, which is why they run with the console switched away |
| Calibration | A udev property read by libinput | A patched application, or a file only one toolkit reads |
| `overlays/bench-lcd35a.dtbo` on the FAT partition | `bench-lcd35a-overlay`, at build time | The board, which never runs `dtc` |

Two of these rows are the whole of the project's runtime discipline.
`fbcon` repaints the console whenever its virtual terminal is active, so a
DRM test program run on the same VT appears to do nothing; the answer is
`chvt` to another terminal, not a change to the program. And a DRM master is
exclusive, which is why criterion 4 asks for a clear error from the wrong
card rather than a picture on the wrong output.

## Kernel configuration

Four symbols, each checked against the mainline source before being written
rather than recalled from the name of a source file. This repository has
paid for the alternative once: three invented netfilter symbols survived
review, CI and a 178 minute build.

Verified in `v6.12`:

| Symbol | Where it is declared | Depends on |
|---|---|---|
| `TINYDRM_ILI9486` | `drivers/gpu/drm/tiny/Kconfig:150` | `DRM && SPI` |
| `TOUCHSCREEN_ADS7846` | `drivers/input/touchscreen/Kconfig:27` | `SPI_MASTER`, and `HWMON = n \|\| HWMON` |
| `DRM_FBDEV_EMULATION` | `drivers/gpu/drm/Kconfig:213` | `DRM` |
| `DRM_MIPI_DBI` | `drivers/gpu/drm/Kconfig:34` | selected, not chosen |

Three consequences, and the second is the one that would have cost a build:

**`DRM_MIPI_DBI` does not need naming.** `TINYDRM_ILI9486` selects it, along
with `DRM_KMS_HELPER`, `DRM_GEM_DMA_HELPER` and `BACKLIGHT_CLASS_DEVICE`. A
fragment that names selected symbols is noise that later has to be kept true.

**`TOUCHSCREEN_ADS7846` carries a tristate dependency that can silently
defeat a fragment line.** `depends on HWMON = n || HWMON` means the driver
may be built in only when `HWMON` is built in or absent entirely. If the
Raspberry Pi defconfig has `CONFIG_HWMON=m`, then `CONFIG_TOUCHSCREEN_ADS7846=y`
is not a valid configuration, Kconfig drops it without comment, and the
result is the exact failure mode this bench keeps meeting: the build
succeeds, the option is absent, and the board has no touch input with
nothing anywhere saying why. **This has not been checked against the
Raspberry Pi defconfig, because that needs a kernel tree and this laptop has
none.** It is the first thing to check on the build host, and the check is
`./go ksym -f lcd35a` followed by `./go kconfig -f lcd35a`.

**Everything is `=y`, and the bus controller is named first.** The same
argument as Project 6 and for a sharper reason. The Raspberry Pi 3 defconfig
builds `CONFIG_SPI_BCM2835=m`, and `core-image-minimal` installs no kernel
modules at all, so an image that named both drivers and forgot the
controller would have no SPI bus and therefore neither device, presenting as
a panel that is not there. `CONFIG_DRM` is `=m` in that defconfig too, and
Kconfig will not let a `=y` symbol depend on a `=m` one, so forcing `DRM=y`
is what makes the two `=y` driver lines legal rather than quietly dropped.

The fragment is opt in behind `BENCH_LCD35A_KERNEL`, following the switch
pattern the kernel bbappend already uses for netboot, TEE, IIO and RT. No
other image in this repository wants a DRM core and two SPI display drivers
built into its kernel for hardware it does not have.

## What this bench does differently

The specification is written for Raspberry Pi OS. Six of its steps do not
survive contact with a Yocto image, and saying so here is cheaper than
finding out during a build.

| The specification says | Here it is | Why |
|---|---|---|
| `sudo apt install libdrm-tests evtest libinput-tools libts-bin` | Packages named in an image recipe | There is no package manager on the target and no network install step. Every tool is decided at build time or is absent |
| Run `dtc` on the Pi, copy the `.dtbo` into `/boot/firmware/overlays` | A recipe compiles the overlay with `dtc-native` and deploys it, and `IMAGE_BOOT_FILES` puts it on the card | A board that compiles its own device tree has a boot that depends on a tool being installed. Same pattern as `bench-explorer700` |
| Append two lines to `/boot/firmware/config.txt` by hand | `ENABLE_SPI_BUS` and `RPI_EXTRA_CONFIG` in the kas file | A hand-edited boot partition is not reproducible and does not survive a reflash |
| Edit `cmdline.txt` to add `fbcon=map:1` | A `CMDLINE` addition in the same kas file | Same reason |
| `modinfo ili9486` to find out what the kernel ships | `./go ksym` and `./go kconfig` against the fragment | The question is not what a distribution shipped. It is whether the fragment reached the `.config`, which is checkable before the board exists |
| The overlay directory is `/boot/overlays` or `/boot/firmware/overlays` depending on the image | `overlays/` on the FAT partition, set by `do_deploy` and `IMAGE_BOOT_FILES` | The layout is ours, so the ambiguity does not arise |

One thing that does not change: the overlay source itself. Device tree is
device tree, and the specification's `.dts` is correct for this board,
including two details worth keeping the reasoning for.

- `/bits/ 16` on the `ti,*` properties, because the `ads7846` binding
  declares them as 16-bit cells and the driver reads them with
  `device_property_read_u16`. Without the prefix they are 32-bit cells and
  the driver reads the wrong half.
- `spidev0` and `spidev1` disabled. Leaving them enabled produces a bus
  conflict at probe: the panel node never binds and `dmesg` says only that
  chip select 0 is already in use, which does not sound like what it is.

## What this design does not claim

- **No board has been powered on.** Every row of the acceptance table says
  "not started" and will keep saying so until a card is flashed.
- **The `HWMON` interaction above is reasoning from the Kconfig stanza, not
  an observation.** It predicts a failure; it has not seen one.
- **The mode line is unconfirmed.** The panel is 480x320 and the overlay
  asks for `rotation = <90>`; whether the driver presents 480x320 or
  320x480 after that, and which way the touch axes then run, is a property
  of the driver and the panel together and is settled by looking, not by
  arguing. `ti,swap-xy` and the calibration matrix must be chosen for the
  same rotation value, and rotation in the panel driver does not rotate
  touch coordinates.
- **Which card is the panel is not fixed.** With `vc4-kms-v3d` active the
  HDMI output is `card0` and the panel is `card1`; with it disabled the
  panel is `card0`. The order can change between kernels, so anything that
  needs to know reads the `modalias` of each card rather than hard-coding a
  path. Criterion 4 exists partly to force this question into the open.
