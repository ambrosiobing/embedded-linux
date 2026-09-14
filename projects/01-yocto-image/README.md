# Project 01: a Yocto image that owns the whole stack

**Board:** Raspberry Pi 4. **Theme:** build systems, layers, recipes, SDK.

Every later project needs a kernel that can be configured, a rootfs that can
be shrunk and a toolchain that matches the target. Building that once with
the Yocto Project turns the Pi from a hobby board into an engineering
platform: you know which package is in the image, why it is there, and how
to reproduce the build a year from now.

The hardware is deliberately small, three LEDs on a breadboard, so that
every difficulty is a build-system difficulty and nothing else.

The output that matters is not the image. It is
[`meta-bench/`](../../meta-bench), the layer the other nineteen projects
extend, and the SDK that cross-compiles their code.

`daqring` builds its image with Buildroot. This one uses the Yocto Project
on purpose, so that the pair covers both major build systems.

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/conf/layer.conf` | The layer itself |
| `meta-bench/recipes-core/images/bench-image.bb` | The image, from `core-image-minimal` |
| `meta-bench/recipes-core/images/bench-image-dev.bb` | The debugging variant |
| `meta-bench/recipes-bench/bench-status/` | The status LED daemon and its systemd plumbing |
| `meta-bench/recipes-kernel/linux/` | The kernel configuration fragment |
| `kas/bench-rpi4.yml` and siblings | Layer pins, machine, distro |
| `sdk/hello-gpiod/` | Proves the cross SDK links against the target sysroot |

## Running it

```sh
./go setup      # host packages, kas, the checks that save three hours
./go check      # about 2 minutes, no board needed
./go build      # 1 to 3 hours the first time, about 10 GB of downloads
./go flash /dev/sdX
./go sdk        # the SDK the other nineteen projects use
```

Wiring, serial console and the first commands on the board are in
[docs/BRINGUP.md](docs/BRINGUP.md).

[JOURNAL.md](JOURNAL.md) records what actually happened while building
this, in order, including the things that were wrong first and why each
decision was taken over its alternative.

## What is in the image, and why

| Package | Why it is there |
|---|---|
| `libgpiod`, `libgpiod-tools` | The character-device GPIO interface every later project uses, plus `gpiodetect` and `gpioset` for bring-up |
| `i2c-tools` | `i2cdetect` is the first command run against any new sensor board |
| `bench-status` | This project's own application: the status LEDs and the state machine behind them |
| `openssh-sshd`, via `ssh-server-openssh` | How later projects copy SDK-built binaries onto the board |

Everything else comes from `core-image-minimal`. `./go packages` prints the
manifest, so this table is checked against the build rather than remembered.

`debug-tweaks` is on, which leaves root without a password. That is right for
a bench board on an isolated network and wrong for anything else. Removing
that line in `bench-image.bb` and adding an `EXTRA_USERS_PARAMS` entry is
what this image needs before it leaves the bench.

## The application

`bench-status` mirrors one word onto three LEDs:

| State file | LED | Meaning |
|---|---|---|
| `ok` | green | Every watched unit is active |
| `starting` | yellow | The system is still coming up |
| `failed` | red | A watched unit failed or was stopped |

The split is deliberate. `bench-status` is a C program that does nothing but
read `/run/bench/state` and drive three lines. Which word belongs in that
file is decided by `bench-state`, a shell script that asks systemd. Unit
ordering, restart policy and logging stay with systemd, where they already
work.

Two writers agree on one file:

- `bench-state.timer` runs `bench-state poll` every two seconds. It asks
  `systemctl is-system-running`, then checks each unit in
  `/etc/bench/watch.conf`.
- A drop-in beside `sshd.socket` sets `OnFailure=bench-state-failed@%n.service`,
  which latches `failed` at once rather than waiting for the next poll. The
  following poll reaches the same verdict on its own, because the unit that
  triggered the drop-in is no longer active.

Line offsets and polarity live in `/etc/bench/leds.conf`, so rewiring the
breadboard does not mean rebuilding the image.

The state machine is tested without hardware: `tests/bench-state-test.sh`
puts a fake `systemctl` on `PATH` and covers all seven cases.

## Kernel changes

As a configuration fragment, never as a copied `.config`. A copy pins the
layer to one kernel version and hides which options the bench needs; a
fragment survives the next rebase and reads as a list of reasons. Every line
in `meta-bench/recipes-kernel/linux/files/bench.cfg` names the projects that
need it.

A fragment that is silently ignored is the classic trap: the build succeeds,
the option is absent, and a driver fails on the board a week later.
`./go kconfig` compares every line of the fragment against the `.config`
that was actually built, including lines that ask for an option to stay off.

## Verification

| Criterion | Check | Status |
|---|---|---|
| The image builds from source | `./go build` | met, 194 min, 5095 tasks |
| The board boots to a login prompt | On the console | met |
| `systemctl --failed` is empty | On the board | met, 0 units |
| The daemon runs and owns its GPIO lines | `systemctl status bench-status`, `gpioinfo` | met, lines 17/22/27 held |
| The state machine reports correctly | `bench-state show` | met, `ok` |
| A stopped unit is reported as failed | `systemctl stop sshd.socket`, then `bench-state show` | to do |
| Every package in the image can be justified | `./go packages` against the table above | met, all 95 |
| The kernel fragment reached the kernel | `./go kconfig` | met, all 13 options |
| A second clean build gives the same package list | `./go reproduce` | running |
| The SDK compiles and runs a libgpiod program | `./go sdk-check`, then run it on the board | to do |
| Boots to a login prompt in under 15 s | Console log timestamps | not measured |

`./go reproduce` tests a narrow claim and states it precisely: a clean build
from the same commit produces the same package list. It does not claim
bit-identical images. Timestamps and build paths still differ, which is what
`buildhistory` is for.

## Deferred: the LED indication

The book's Project 1 drives three LEDs from the status daemon. That is
deferred, and the reason is worth recording rather than hiding.

The bench LEDs are Joy-IT LinkerKit LK-LED10 modules. They have a 2.0 mm
socket and, in the manufacturer's own words, require "a Linker Kit baseboard
as well as an Linker Kit connecting cable". Standard 2.54 mm jumper wires
cannot mate with that socket, so the modules were never electrically
connected and no polarity or wiring test could have succeeded.

**Nothing in the software was changed or removed.** `bench-status` runs,
requests lines 17, 22 and 27 through libgpiod v2, holds them for as long as
it is running, and sets their values once a second from the state file. That
much is verified on the board by `gpioinfo`:

```
line  17: "GPIO17"  output consumer="bench-status"
line  22: "GPIO22"  output consumer="bench-status"
line  27: "GPIO27"  output consumer="bench-status"
```

What is **not** verified is that those output values reach the pins as
voltages. That needs either an LED or a meter, and it is the single
unverified link in the chain.

To close it, either fit three bare LEDs with 330 Ohm series resistors from
GPIO17, GPIO27 and GPIO22 to ground, which is what the book originally
specified and which is unambiguously active high, or buy an LK-Cable and use
the modules as the manufacturer intends. Grove 4-pin cables are the same
2.0 mm pitch and fit.

The polarity and line-offset configuration in `/etc/bench/leds.conf` stays.
It costs one small file and one libgpiod call, it is the correct design for
a module whose wiring is not known in advance, and it means neither option
above needs a rebuild.

## Build times

Measured on this bench. The empty cells are not yet run.

| Host | Cores | RAM | First build | Rebuild, warm sstate | SDK |
|---|---|---|---|---|---|
| WSL2 Ubuntu 26.04 | 8 | 15 GiB | 194 min | 21 s | |

`BB_NUMBER_THREADS` and `PARALLEL_MAKE` are both 8 in the kas file, which
matches this host exactly. On a machine with a different core count, both
are worth changing together.

## What the first build produced

| | |
|---|---|
| Tasks | 5095, all succeeded, none reused from a previous run |
| Wall clock | 194 min |
| Image | 49 MB compressed, 48 MB after the dbus fix |
| Kernel | 6.6.63, Raspberry Pi fork, via meta-raspberrypi |
| Packages in the image | 99, then 95 after the dbus fix |
| Warnings | 36, all of one class: a primary download URL was unreachable and the mirror served it instead |
| Warm rebuild, no change | 21 s, 5091 of 5095 tasks reused, sstate 100% match |
| Rebuild after one recipe changed | 2 min 31 s, sstate 84% match, 25 tasks missed |

### The commits this was built from

kas prints them at the start of every build, which is what makes a build
reportable rather than merely repeatable.

| Layer | Commit |
|---|---|
| poky (scarthgap) | `77d1feb37e280733684ae8a9449fb031d5d7ff40` |
| meta-openembedded (scarthgap) | `b5874ea07d69919d9b40d59f2c2f0bbd24bc3259` |
| meta-raspberrypi (scarthgap) | `6ca1f75017cc5d5acdb8bb05634c4bc01fa049fd` |
| meta-bench (main) | `2432871cf5eabd268530461fd5763b47e4ba0bca` |

BitBake 2.8.1, poky 5.0.20, tune `aarch64 crc cortexa72`.

Before tagging a release these replace the branch names in the kas file,
which is what `kas dump --lock` writes.

`./go kconfig` confirms all thirteen fragment options reached the built
`.config`, including `CONFIG_GPIO_CDEV_V1` being absent rather than merely
unrequested.

## The four X11 packages, and what pulled them in

The first manifest contained `libx11-6`, `libxau6`, `libxcb1` and
`libxdmcp6` in an image with no display. The acceptance criterion is that
every package can be justified, and these could not be, so they were traced
rather than tolerated.

The package metadata answers it directly:

```sh
grep -H '^RDEPENDS' ~/bench/build/tmp/pkgdata/raspberrypi4-64/runtime/* | grep libx11
```
```
runtime/dbus:RDEPENDS:dbus: dbus-common dbus-tools dbus-lib expat glibc
                            libsystemd libx11
```

dbus, not openssh as first guessed. The poky distro carries `x11` in
`DISTRO_FEATURES`, so dbus is built with X11 autolaunch: the feature that
starts a session bus by talking to an X display. A headless board can never
use it, and it costs four packages.

`meta-bench/recipes-core/dbus/dbus_%.bbappend` removes it:

```
PACKAGECONFIG:remove = "x11"
```

Removing `x11` from `DISTRO_FEATURES` instead would also work and is
arguably more correct for a headless image. It was not chosen because it
invalidates shared-state signatures across the whole build for a
four-package saving, where the bbappend rebuilds one recipe. Project 13
wants graphics, but it wants Wayland, so the distro feature is not being
kept for its benefit either.

**Verified.** The rebuild took 2 min 31 s, dropped 38 build tasks that no
longer needed to exist, removed 23 now-unreachable sstate objects, and
produced a 48 MB image with **95 packages** and no `libx` entries. The
criterion that every package can be justified is met for all 95.

### Still open

`kbd`, `kbd-consolefonts`, `kbd-keymaps`, `kbd-keymaps-pine` and `keymaps`
are console keymaps, which a board reached over serial and SSH does not
need. `update-rc.d` and `update-alternatives-opkg` are package-management
machinery on an image with no package manager. Both come from
`packagegroup-core-boot`, so trimming them means overriding that rather than
a `PACKAGECONFIG`, which is a larger change than it looks.

## Where this differs from the book

The book's Project 1 is the specification. Four things are done differently,
each for a reason worth keeping:

1. **The LEDs are four-pin modules, not bare LEDs.** `S1` is the signal, `S2`
   is unused, `U` is the 3V3 supply, `G` is ground, and the series resistor
   is on the module, so the three loose 330 Ohm resistors are not needed.
   The signal pins are still GPIO17, GPIO27 and GPIO22.
2. **Polarity and line offsets are configuration, not constants.** A module
   with a supply pin may light on a low signal.
   `gpiod_line_settings_set_active_low()` exists for this, so
   `/etc/bench/leds.conf` decides and the C never reasons about volts.
3. **The GPIO chip is found by label, not by index.** `/dev/gpiochip0` is the
   header on a Pi 4 but not on every board, and the numbering moves when an
   expander probes first.
4. **`bench-state` and its units are part of the recipe.** The book's
   acceptance criteria require a state file and an `OnFailure` drop-in, but
   its repository layout does not include them. They are here, with a test.

5. **The LED indication is deferred.** The bench LED modules cannot be
   connected with the cables available, so the daemon drives its lines and
   nothing is attached to them. See the section above.

One smaller thing: `S = "${WORKDIR}"` is correct on scarthgap and becomes
`S = "${UNPACKDIR}"` on walnascar and later. It is the only line in the layer
that has to move with that release.

## Pitfalls

- A Windows-mounted drive under WSL2 defeats BitBake through
  case-insensitivity and slow I/O. `scripts/common.sh` probes for both and
  refuses to start.
- `rm_work` reclaims disk but deletes the sources you want when something is
  wrong. `RM_WORK_EXCLUDE` keeps the kernel and `bench-status` unpacked,
  which is what makes `./go kconfig` possible.
- The `meta-raspberrypi` kernel recipe tracks the Raspberry Pi fork of Linux,
  not mainline. Worth remembering when a later project talks about a
  mainline driver.
- Do not power the Pi from the 5 V lead of the USB/TTL cable, and do not feed
  the LED modules from 5 V. See [docs/BRINGUP.md](docs/BRINGUP.md).

## Sources

- Yocto Project reference manual, https://docs.yoctoproject.org/
- meta-raspberrypi documentation, https://meta-raspberrypi.readthedocs.io/
- kas user guide, https://kas.readthedocs.io/
- libgpiod v2 API, https://libgpiod.readthedocs.io/
