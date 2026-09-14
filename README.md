# meta-bench

A Yocto layer that owns the whole stack for a Raspberry Pi 4 bench board:
the image, the kernel configuration, one application and a cross SDK. It is
Project 1 of the twenty embedded Linux projects, and the nineteen that
follow extend this layer rather than starting again.

The output that matters is not the image. It is the layer: every later
project adds a kernel fragment, a device-tree overlay or a recipe here, and
every later project cross-compiles against the SDK this one produces.

`daqring` builds its image with Buildroot. This one uses the Yocto Project
on purpose, so that the pair covers both major build systems.

## Quick start

```sh
./go setup      # host packages, kas, and the checks that save three hours
./go build      # first run: one to three hours and about 10 GB of downloads
./go flash /dev/sdX
./go sdk        # the cross SDK the other nineteen projects use
```

`./go` with no argument lists everything else.

## Layer tree

```
meta-bench/
  conf/layer.conf
  kas/bench-rpi4.yml                    layer pins, machine, distro, target
  kas/bench-rpi3.yml                    same layer, Raspberry Pi 3
  kas/bench-dev.yml                     the debugging image
  recipes-core/images/bench-image.bb
  recipes-core/images/bench-image-dev.bb
  recipes-bench/bench-status/bench-status_0.1.bb
  recipes-bench/bench-status/files/bench-status.c        the LED daemon
  recipes-bench/bench-status/files/bench-state           the state writer
  recipes-bench/bench-status/files/*.service *.timer     systemd units
  recipes-bench/bench-status/files/leds.conf watch.conf  configuration
  recipes-kernel/linux/linux-raspberrypi_%.bbappend
  recipes-kernel/linux/files/bench.cfg                   kernel fragment
  sdk/hello-gpiod/                      proves the SDK cross-compiles
  scripts/                              build, flash, SDK, checks
  tests/bench-state-test.sh             the state machine, no board needed
  docs/BRINGUP.md                       wiring, console, first checks
```

## Where versions live

In one file. `kas/bench-rpi4.yml` pins every external layer to a branch;
moving to the next LTS means editing three branch names and nothing else.
Before tagging a release, replace each branch with the commit that was
actually built, which `kas dump --lock` writes for you.

```yaml
header:
  version: 14

machine: raspberrypi4-64
distro: poky
target: bench-image

repos:
  meta-bench:                                   # the repo holding this file
  poky:
    url: https://git.yoctoproject.org/poky
    branch: scarthgap                           # 5.0 LTS
    layers: {meta: , meta-poky: }
  meta-openembedded:
    url: https://git.openembedded.org/meta-openembedded
    branch: scarthgap
    layers: {meta-oe: }
  meta-raspberrypi:
    url: https://git.yoctoproject.org/meta-raspberrypi
    branch: scarthgap
```

The `local_conf_header` in the same file sets systemd as the init manager,
enables UART0 early enough to catch the firmware messages, writes a `.wic`
with its block map so that flashing takes seconds, and keeps `DL_DIR` and
`SSTATE_DIR` outside the build tree so that deleting `build/` costs minutes
rather than hours.

## What is in the image, and why

| Package | Why it is there |
|---|---|
| `libgpiod`, `libgpiod-tools` | The character-device GPIO interface every later project uses, plus `gpiodetect` and `gpioset` for bring-up |
| `i2c-tools` | `i2cdetect` is the first command run against any new sensor board |
| `bench-status` | This project's own application: the status LEDs and the state machine behind them |
| `openssh-sshd` via `ssh-server-openssh` | How the later projects copy SDK-built binaries onto the board |
| `i2c-tools`, `openssh` dependencies | Pulled in by the two above, listed in the manifest |

Everything else comes from `core-image-minimal`. `./go packages` prints the
full manifest, so this table is checked against the build rather than
remembered.

`debug-tweaks` is on, which leaves the root account without a password. That
is right for a bench board on an isolated network and wrong for anything
else. Removing that one line in `bench-image.bb` and adding an
`EXTRA_USERS_PARAMS` entry is what this image needs before it leaves the
bench.

## The application

`bench-status` mirrors one word onto three LEDs:

| State file | LED | Meaning |
|---|---|---|
| `ok` | green | Every watched unit is active |
| `starting` | yellow | The system is still coming up |
| `failed` | red | A watched unit failed or was stopped |

The split is deliberate. `bench-status` is a C program that does nothing but
read `/run/bench/state` and drive three lines. The decision of which word
belongs in that file is made by `bench-state`, a shell script that asks
systemd. Unit ordering, restart policy and logging stay with systemd, where
they already work.

Two writers agree on one file:

- `bench-state.timer` runs `bench-state poll` every two seconds. It asks
  `systemctl is-system-running`, then checks each unit named in
  `/etc/bench/watch.conf`.
- A drop-in installed next to `sshd.socket` sets
  `OnFailure=bench-state-failed@%n.service`, which latches `failed`
  immediately rather than waiting for the next poll. The following poll
  reaches the same verdict on its own, because the unit that triggered the
  drop-in is no longer active.

Line offsets and polarity live in `/etc/bench/leds.conf`, so rewiring the
breadboard does not mean rebuilding the image. See
[docs/BRINGUP.md](docs/BRINGUP.md) for how to find out which polarity the
modules need.

The state machine is tested without hardware. `tests/bench-state-test.sh`
puts a fake `systemctl` on `PATH` and checks all seven cases, and CI runs it
on every push.

## Kernel changes

As a configuration fragment, never as a copied `.config`. A copied `.config`
pins the layer to one kernel version and hides which options the bench
actually needs; a fragment survives the next rebase and reads as a list of
reasons. Every line in `recipes-kernel/linux/files/bench.cfg` names the
projects that need it.

A fragment that is silently ignored is the classic trap: the build succeeds,
the option is absent, and a driver fails on the board a week later.
`./go kconfig` compares every line of the fragment against the `.config`
that was actually built, including the lines that ask for an option to stay
off.

## Verification

The acceptance criteria for this project, and the command that checks each.

| Criterion | Check |
|---|---|
| Boots to a login prompt in under 15 s | `docs/evidence/boot-console.log`, timestamps in the kernel messages |
| `systemctl --failed` is empty, green LED within 5 s | On the board, see [docs/BRINGUP.md](docs/BRINGUP.md) |
| Stopping sshd turns the red LED on | `systemctl stop sshd.socket`, then `bench-state show` |
| Every package in the image can be justified | `./go packages` against the table above |
| The kernel fragment reached the kernel | `./go kconfig` |
| A second clean build gives the same package list | `./go reproduce` |
| The SDK compiles and runs a libgpiod program | `./go sdk-check`, then run it on the board |

`./go reproduce` tests a narrow claim and states it precisely: a clean build
from the same commit produces the same package list. It does not claim
bit-identical images. Timestamps and build paths still differ, which is what
`buildhistory` is for.

## Build times

Filled in from your own host after the first two runs. Leave it empty rather
than quoting someone else's numbers.

| Host | Cores | RAM | First build | Rebuild, warm sstate | SDK |
|---|---|---|---|---|---|
| | | | | | |

## Where this differs from the book

The book's Project 1 is the specification. Four things are done differently
here, each for a reason worth keeping:

1. **The LEDs are four-pin modules, not bare LEDs.** `S1` is the signal,
   `S2` is unused, `U` is the 3V3 supply, `G` is ground, and the series
   resistor is on the module. The three loose 330 Ohm resistors are not
   needed. The signal pins are still GPIO17, GPIO27 and GPIO22.
2. **Polarity and line offsets are configuration, not constants.** A module
   with a supply pin may light on a low signal. `gpiod_line_settings_set_active_low()`
   exists for exactly this, so `/etc/bench/leds.conf` decides and the C never
   reasons about volts.
3. **The GPIO chip is found by label, not by index.** `/dev/gpiochip0` is the
   header on a Pi 4 but not on every board, and the numbering moves when an
   expander probes first.
4. **`bench-state` and its units are part of the recipe.** The book's
   acceptance criteria require a state file and an `OnFailure` drop-in, but
   its repository layout does not include them. They are here, with a test.

One smaller thing: `S = "${WORKDIR}"` is correct on scarthgap and becomes
`S = "${UNPACKDIR}"` on walnascar and later. It is the only line in the layer
that has to move with that release.

## Pitfalls

- A Windows-mounted drive under WSL2 defeats BitBake through
  case-insensitivity and slow I/O. `scripts/common.sh` probes for both and
  refuses to start, because discovering this three hours into a build is
  expensive.
- `rm_work` reclaims the disk but deletes the sources you want to read when
  something is wrong. `RM_WORK_EXCLUDE` keeps the kernel and `bench-status`
  unpacked, which is what makes `./go kconfig` possible.
- The `meta-raspberrypi` kernel recipe tracks the Raspberry Pi fork of Linux,
  not mainline. Worth remembering when a later project talks about a mainline
  driver.
- Do not power the Pi from the 5 V lead of the USB/TTL cable, and do not feed
  the LED modules from 5 V. See [docs/BRINGUP.md](docs/BRINGUP.md).

## Sources

- Yocto Project reference manual, https://docs.yoctoproject.org/
- meta-raspberrypi documentation, https://meta-raspberrypi.readthedocs.io/
- kas user guide, https://kas.readthedocs.io/
- libgpiod v2 API, https://libgpiod.readthedocs.io/
