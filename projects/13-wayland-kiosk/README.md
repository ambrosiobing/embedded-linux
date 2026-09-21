# Project 13: a Wayland kiosk HMI on the 7 inch touchscreen

**Board:** Raspberry Pi 4. **Theme:** the graphics stack from GPU to
widget: DRM/KMS with vc4 and v3d, a compositor that owns the display and
the input devices, and LVGL drawing into a Wayland surface.

**Read this paragraph first.** Project 7 drove a small SPI panel through
a tiny DRM driver and let the console render. This project climbs the
rest of the stack, and the dashboard is the excuse. **The deliverable is
[docs/DEBUGGING.md](docs/DEBUGGING.md):** nine layers, the one tool that
answers for each, and what a healthy answer looks like. Every integration
problem here (black screen, no touch, wrong rotation, twenty second boot)
is a question of which layer is misconfigured, and that question
transfers to every embedded product with a screen.

## State

**Everything is written and nothing has been run.** No image has been
built, no board has been booted, no pixel has been drawn. There are no
measurements in this README and the rows that will hold them say so.

What is proven today, on a laptop:

| Proven | How |
|---|---|
| Rotation is set exactly once, and neither weston.ini nor udev rotates again | `tests/kiosk-config-test.sh`, 20 assertions |
| The touch rule ships disabled and is installed outside udev's path | the same suite |
| The kas file adds the distro feature weston refuses to build without | the same suite |
| LVGL is not pinned at the version with no Wayland driver | the same suite |
| The recipe verifies its own generated `lv_conf.h` | the same suite |
| `bench-gfx` reports questions it could not ask, and is BusyBox-safe | the same suite |
| The memory bar uses MemAvailable, not MemFree, and a failed read shows n/a rather than 0 | `tests/hmi-metrics-test.sh`, 21 assertions, **in CI only**: this laptop has no compiler and the suite says so instead of passing |
| Every LVGL function and every `lv_conf.h` option the code uses exists at the pinned tag | read out of the 9.3.0 headers and template |
| The image installs the kernel modules without which there is no `/dev/dri` at all | the same suite |
| Four of those guards fire when broken and go quiet when restored | each defect reintroduced and the suite rerun |
| `cage` and `wlroots` are in no layer this bench uses | directory listings of oe-core, meta-oe, meta-raspberrypi |
| weston 13.0.1 has `shell-kiosk` in its default `PACKAGECONFIG` | `meta/recipes-graphics/wayland/weston_13.0.1.bb` |
| Poky supplies `wayland` and `opengl` but not `pam` | `poky.conf` and `default-distrovars.inc` at scarthgap |
| LVGL 9.1.0 has no Wayland driver; 9.2.0 is the first that does | the `src/drivers` listing at each tag |

## The four findings worth carrying elsewhere

### 1. The alternative became the primary, on provenance rather than availability

The specification's compositor is `cage`. It is in **no layer this bench
uses** (oe-core, meta-oe, meta-raspberrypi), and neither is `wlroots`.
Weston 13.0.1 is, with `shell-kiosk` already in its default
`PACKAGECONFIG`, and the specification names it as the sanctioned
alternative.

**A correction worth reading, because the first version of this section
was wrong.** It said packaging cage would be "roughly a week of work".
That reasoned from three layers to all layers.
[meta-wayland](https://codeberg.org/flk/meta-wayland) has a **scarthgap**
branch with `cage-0.1.5.bb` and `wlroots-0.17.bb` in `recipes-wlroots/`.
Using cage means adding one layer to the kas file, the way
`kas/bench-tee.yml` already adds meta-arm. An afternoon, not a week.

The decision stands, on a different reason than the one first given:
every other layer this repository depends on comes from the Yocto Project
or OpenEmbedded, and meta-wayland is a personal layer on codeberg.
Adding one to a portfolio repository is a supply chain choice worth
making deliberately, not to save a nine line `weston.ini`. The full
comparison is in
[docs/DESIGN.md](docs/DESIGN.md#1-the-compositor-is-weston-not-cage).

### 2. A sed that matches nothing is the new promptless Kconfig symbol

meta-oe pins LVGL 9.1.0, which **has no Wayland driver at all**, and
configures LVGL by running `sed` over `lv_conf.h`. A `sed` whose pattern
matches nothing changes nothing and reports success. Adding
`LV_USE_WAYLAND` there would produce **no error, no warning and no
effect**: a build that succeeds and a binary with no Wayland support.

This is the same shape as Project 9's four promptless Kconfig symbols, in
a different tool. So `bench-hmi` vendors its own LVGL at 9.3.0 and
**verifies its generated configuration by reading it back**, failing the
build with the symbol name and the line that is actually there.

### 3. The image already owned the panel

`kas/bench-rpi4.yml` has set `dtoverlay=vc4-kms-dsi-7inch` and appended
`console=tty1` since Project 1. **Every bench image already drives this
screen and already runs a getty on it.** Project 13 is not adding a
display to a headless board; it is taking one from a getty.

The specification's answer is `Conflicts=getty@tty1.service`. oe-core's
`weston-init` unit uses **tty7**, which removes the conflict instead of
declaring it: the dashboard and the login prompt coexist, and
Ctrl-Alt-F1 still reaches a shell on a board showing a kiosk. On a bench
that is strictly better, so this project reuses that unit and changes
only `weston.ini`.

### 4. Everything graphics is a module, and the image installed none of them

**The one that would have cost a build and a reflash.** Every driver this
project needs is `=m` in `arch/arm64/configs/bcm2711_defconfig`:

```
  CONFIG_DRM=m   CONFIG_DRM_VC4=m   CONFIG_DRM_V3D=m
  CONFIG_DRM_PANEL_RASPBERRYPI_TOUCHSCREEN=m
  CONFIG_TOUCHSCREEN_EDT_FT5X06=m
```

and `bench-image` is built on `core-image-minimal`, which installs **no
kernel modules**. The image as first written would have had no
`/dev/dri`, no panel and no touch device: a black screen, which is also
what a bad ribbon, a missing overlay and a brown-out look like.

Project 6 hit this and answered with a fragment full of `=y`. **That
answer is unreachable here**, and the reason is invisible until a build:

```
  config DRM_VC4
      tristate "Broadcom VC4 Graphics"
      depends on SND && SND_SOC
```

with `CONFIG_SND=m` and `CONFIG_SND_SOC=m` in the same defconfig. A
tristate that depends on a module can be at most a module, so
`CONFIG_DRM_VC4=y` is not merely unset by a fragment, it **cannot be
satisfied**, and the line would be dropped in silence.

So the modules stay modules and the image installs `kernel-modules`. The
test asserts it, and the assertion fires when the line is removed.

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-bench/bench-hmi/` | The LVGL dashboard, with LVGL 9.3.0 vendored and its configuration verified |
| `meta-bench/recipes-bench/bench-kiosk/` | `bench-gfx`, the runnable version of the layer table, and the touch rule shipped disabled |
| `meta-bench/recipes-graphics/wayland/weston-init.bbappend` | Nine lines of `weston.ini` that turn oe-core's weston into a kiosk |
| `meta-bench/recipes-core/images/bench-kiosk-image.bb` | The image, and a note naming the two tools it could not package |
| `kas/bench-kiosk.yml` | `pam`, the panel orientation, and the firmware boot trims |
| `tests/kiosk-config-test.sh` | 20 assertions on configuration coherence, no board and no GPU |
| `tests/hmi-metrics-test.sh` and its harness | 21 assertions on the only C that can run off the board |
| `projects/13-wayland-kiosk/docs/figures/` | Seven TikZ drawings, each compiling on its own |

## Running it

On the **authoring laptop (Windows)**:

```bash
sh tests/kiosk-config-test.sh
```

On the **build laptop (WSL)**, after checking the disk (about 25 GB; the
first build rebuilds the kernel because the command line changes):

```bash
./go kiosk
```

```bash
./go flash /dev/sdX
```

On the **board over ssh**, once it is up:

```bash
bench-gfx
```

The full sequence with what each step should print is in
[docs/BRINGUP.md](docs/BRINGUP.md).

## Documents

| File | What |
|---|---|
| [docs/DEBUGGING.md](docs/DEBUGGING.md) | **The deliverable.** Nine layers, nine tools, and the faults to inject |
| [docs/DESIGN.md](docs/DESIGN.md) | The drawings, the ownership table, and the three deviations |
| [docs/BRINGUP.md](docs/BRINGUP.md) | First boot in order, with the check that catches each silent failure |
| [docs/BOOT-TIME.md](docs/BOOT-TIME.md) | The ten second budget, both instruments, and what a Yocto image does not need to trim |
| [JOURNAL.md](JOURNAL.md) | What was decided and why |

## Acceptance criteria

Measured rows are blank until a board has produced them.

| # | Criterion | Kind | Status |
|---|---|---|---|
| 1 | Power-on to first dashboard frame under 10 s, measured three times | measured | |
| 2 | `drm_info` shows `DSI-1` connected at 800x480 with the compositor as DRM master | measured | see the gap below |
| 3 | Atomic state shows one active plane with the client's buffer | measured | |
| 4 | A touch at each corner lands within 2 percent after rotation | measured | |
| 5 | Writing `failed` to `/run/bench/state` turns the LED red within 1 s | measured | |
| 6 | Compositor and application together under 5 percent CPU at idle | measured | |
| 7 | `systemctl restart weston` brings the dashboard back within 3 s | measured | |
| 8 | Tab and Enter operate the buttons with the touch driver unloaded | measured | |
| 9 | Rotation is set at exactly one layer | configured | verified by test, and proven by breaking it |
| 10 | The compositor runs unprivileged, through a seat broker | configured | `weston-init`'s unit, user `weston`, PAM session |
| 11 | Touch calibration lives in udev, not in the application | configured | rule shipped disabled, outside udev's path |
| 12 | Every other bench image is unaffected | configured | one `DISTRO_FEATURES` append, in the kiosk kas file only |

### Two criteria this bench cannot fully meet, with the reason

**Criterion 2 names `drm_info`, which has no recipe** in oe-core, meta-oe
or meta-raspberrypi. `bench-gfx drm` answers the part that matters, which
card carries a connected connector and what the atomic state holds, by
reading sysfs and debugfs. **What it cannot show is the DRM master
holder**, which is the half of criterion 2 that `drm_info` uniquely
provides. Packaging `drm_info` is a small recipe and the honest fix.

**`evtest` is likewise absent**, and BusyBox has no equivalent, so layer
4 (raw evdev, below libinput) is reachable only indirectly. Neither gap
is an oversight and neither is fatal: both layers can be inferred from
the layers around them, and saying which question could not be asked is
better than an empty row.

## Going further

- **Package `drm_info` and `evtest`**, closing the two gaps above. The
  smallest useful follow-up.
- **Add meta-wayland and build the cage variant**, then compare against
  weston on boot time, RSS and configuration surface. This is the
  specification's original design, and it is **cheaper than it first
  looked**: `https://codeberg.org/flk/meta-wayland` has a scarthgap
  branch with `recipes-wlroots/cage/cage-0.1.5.bb` and
  `recipes-wlroots/wlroots/wlroots-0.17.bb`, so it is a `repos:` entry in
  a kas file rather than recipes to write. `seatd` is already in oe-core.
  The open question is maintenance, not effort.
- **Qt 6 with `eglfs_kms` and no compositor at all**, for the boot time
  and memory comparison the specification asks for. That is the classic
  embedded Qt deployment and the honest competitor to this stack.
- **The sensor hub's D-Bus interface** from Project 12, plotted live with
  an `lv_chart`.
