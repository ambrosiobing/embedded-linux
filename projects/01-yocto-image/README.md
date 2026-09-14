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

| Criterion | Check |
|---|---|
| Boots to a login prompt in under 15 s | `docs/evidence/boot-console.log`, from the kernel timestamps |
| `systemctl --failed` empty, green LED within 5 s | On the board, see [docs/BRINGUP.md](docs/BRINGUP.md) |
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

Measured on this bench. The empty cells are not yet run.

| Host | Cores | RAM | First build | Rebuild, warm sstate | SDK |
|---|---|---|---|---|---|
| WSL2 Ubuntu 26.04 | 8 | 15 GiB | 194 min | | |

`BB_NUMBER_THREADS` and `PARALLEL_MAKE` are both 8 in the kas file, which
matches this host exactly. On a machine with a different core count, both
are worth changing together.

## What the first build produced

| | |
|---|---|
| Tasks | 5095, all succeeded, none reused from a previous run |
| Wall clock | 194 min |
| Image | 49 MB compressed (`.wic.bz2`) |
| Kernel | 6.6.63, Raspberry Pi fork, via meta-raspberrypi |
| Packages in the image | 99 |
| Warnings | 36, all of one class: a primary download URL was unreachable and the mirror served it instead |

`./go kconfig` confirms all thirteen fragment options reached the built
`.config`, including `CONFIG_GPIO_CDEV_V1` being absent rather than merely
unrequested.

## Open: four packages not yet justified

The manifest contains `libx11-6`, `libxau6`, `libxcb1` and `libxdmcp6` in an
image with no display and no X server. The acceptance criterion above says
every package must be justifiable, so these are an open item rather than a
passing result. `buildhistory` recorded the runtime dependency graph, so the
cause is recoverable rather than a guess:

```sh
grep -i libx11 ~/bench/build/buildhistory/images/raspberrypi4-64/glibc/bench-image/depends.dot
```

Two lesser candidates: the `kbd` and `keymaps` group, which a board reached
over serial and SSH does not need, and `update-rc.d` with
`update-alternatives-opkg`, which are package-management machinery on an
image that has no package manager.

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
