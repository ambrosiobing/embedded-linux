# Project 2: NanoPi NEO Air on mainline, from the boot ROM upwards

**Board:** NanoPi NEO Air (Allwinner H3, 512 MB, 8 GB eMMC, AP6212 Wi-Fi).
**Theme:** board bring-up, bootloader, sunxi mainline.

Every other project in this repository starts after a bootloader has
already run. The Raspberry Pi's is closed firmware on the video core: it
reads `config.txt`, loads a kernel, and the first thing those projects see
is Linux starting. Here there is no vendor firmware. The Allwinner boot ROM
is 32 KB inside the SoC and cannot be changed, and everything after it is
built from source in this directory.

It is also the only project in the set with no Yocto. U-Boot, the kernel
and a Debian root filesystem are built directly, which is why this lives
under `projects/` with its own build scripts rather than adding recipes to
`meta-bench/`.

The board has no Ethernet and no HDMI. For the first hour the only way in
is the debug UART, which is a realistic constraint rather than a hardship:
on most industrial boards the serial console is the first and sometimes the
only diagnostic interface.

## State

**Written, not yet built, and no board has been powered on.** Every script,
fragment and document exists and the two that can destroy something are
tested, but nothing here has cross-compiled a single object and the NEO Air
has not been out of its box.

That is a rung below Software complete on purpose, the same one Project 6
uses: `gcc-arm-linux-gnueabihf` is not installed on the authoring laptop,
so the build scripts have been exercised only as far as their refusals.

What is proven today, on a laptop:

| Proven | How |
|---|---|
| The eMMC provisioner refuses all four ways it can be misused | `tests/neo-air-flash-test.sh`, 32 assertions |
| It writes the bootloader at byte 8192 and starts partition 1 at sector 2048 | the same test, reading what `sfdisk` was fed on stdin |
| It patches the `PARTUUID` placeholder, and does so again on a second run | the same test |
| A failing state is reported by name rather than by line | the same test, by making `dd` fail |
| The card writer refuses the system disk, a non-removable device, a missing build and a mistyped confirmation | `tests/neo-air-sdcard-test.sh`, 29 assertions |
| It writes the partition table before the bootloader | the same test, proved by swapping the two and watching it fail |
| Both build scripts refuse an unpinned environment and a build inside the checkout | run by hand, both directions |

What that does not prove is that any of it compiles. See
[Acceptance criteria](#acceptance-criteria).

## What this project adds

| Path | What |
|---|---|
| `toolchain.env` | Every input pinned: U-Boot tag, kernel tag, Debian suite, defconfigs, and the marker the scripts refuse without |
| `uboot/build.sh` | Clone at a tag, merge the fragment, **verify the fragment reached `.config`**, build |
| `uboot/fragments/bench.config` | `CONFIG_MMC_SUNXI_SLOT_EXTRA=2`, which is what makes U-Boot see the eMMC at all |
| `kernel/build.sh` | The same, plus the device-tree path that moved in 6.5 and an assertion that `brcmfmac.ko` exists |
| `kernel/fragments/bench.cfg` | SDIO Wi-Fi, what systemd needs, and `PRINTK_TIME` for Project 3 |
| `rootfs/mkrootfs.sh` | debootstrap armhf, then the modules, then `depmod`, in that order and for a reason |
| `rootfs/overlay/` | `extlinux.conf` with a deliberately impossible `PARTUUID`, the network unit, a wpa_supplicant example |
| `tools/sdcard.sh` | Writes the development medium. Refuses four ways |
| `tools/flash-emmc.sh` | The state machine that provisions the production medium. Refuses four ways |
| `tools/fel-boot.sh` | Recovery over USB for a board with no working bootloader |
| `docs/DESIGN.md` | The four figures, and the ownership table that found the three two-owner hazards |

## The boot chain, and the two numbers in it

```
BROM (in the SoC)  probes byte 8192 of mmc0, then mmc2, then enters FEL
      |
      v
SPL (SRAM)         initialises DDR3, loads u-boot.img from the same medium
      |
      v
U-Boot (DRAM)      distro boot: scans partitions for extlinux/extlinux.conf
      |
      v
kernel             zImage + sun8i-h3-nanopi-neo-air.dtb, console=ttyS0,115200
      |
      v
systemd            Debian bookworm armhf
```

**Byte 8192 and sector 2048.** The bootloader starts at 8 KiB; the first
partition starts at 1 MiB. A partition table that starts a partition below
sector 2048 puts a filesystem on top of U-Boot, and U-Boot then overwrites
the filesystem. Neither failure announces itself: the board stops after the
SPL banner, or a filesystem will not mount and `fsck` cannot say why.

Both numbers are asserted in the tests rather than trusted in the code.

## Running it

Nothing here runs without the pins:

```
. projects/02-neo-air-mainline/toolchain.env
```

Then, on the WSL2 build host:

```
./go neo-air uboot
./go neo-air kernel
sudo ./go neo-air rootfs
sudo ./go neo-air card /dev/sdX
```

Sudo on the entry point, never on the script: `./go neo-air` sources
`toolchain.env` inside the sudo. Sourcing it in your own shell first does
not survive, and `-E` does not rescue it on a sudo that ignores `-E`. Both
scripts refuse rather than build something unpinned.

Sources and artefacts go to `$NEO_WORK`, which defaults to
`$BENCH_WORK/neo-air` and is outside the checkout. That is a departure from
the specification's layout and the reason is in `.gitignore`: a build tree
inside the checkout once made every archived image in this repository
report a dirty tree.

Then on the board, booted from the card:

```
sh /boot/flash-emmc.sh -n        the plan
sh /boot/flash-emmc.sh           the provisioning
```

## Acceptance criteria

| # | Criterion | How it is checked | State |
|---|---|---|---|
| 1 | The SPL banner appears within about a second of power, and `mmc list` shows both the SD card and the eMMC | serial console capture | not started |
| 2 | `cat /proc/device-tree/model` prints `FriendlyARM NanoPi NEO Air`, and `uname -r` is the tag from `toolchain.env` with no vendor suffix | on the board | not started |
| 3 | `dmesg \| grep brcmfmac` shows a firmware version line, `wlan0` exists, and ssh over Wi-Fi works | on the board | not started |
| 4 | With the SD card removed, the board boots from eMMC to a login, and `findmnt /` shows the eMMC partition | on the board | not started |
| 5 | `flash-emmc.sh` run twice in a row succeeds both times, and the second boot log differs only in timestamps | on the board, and the idempotence of the `PARTUUID` patching is already proven off-board | **the off-board half is met**, `tests/neo-air-flash-test.sh` |
| 6 | FEL recovery restores a board whose eMMC bootloader has been erased, without opening anything | on the board, deliberately erasing it first | not started |
| 7 | `docs/bootlog-sd.txt` and `docs/bootlog-emmc.txt` are complete captures from power-on to login | the console, captured from before power is applied | not started |
| 8 | Every kernel fragment option reaches the built `.config` | `kernel/build.sh` refuses if not | written, never run |
| 9 | The provisioner cannot be made to write to the medium it booted from | `tests/neo-air-flash-test.sh` | **met** |

Criterion 6 is the one worth doing rather than assuming. A recovery path
that has never been used is a recovery path whose state nobody knows, which
is why the project erases the bootloader on purpose once.

## What is tested without hardware

| Suite | Assertions | What it holds |
|---|---|---|
| `tests/neo-air-flash-test.sh` | 32 | the eMMC state machine: four refusals, both magic numbers, the `PARTUUID` patching, idempotence, and that a failure names its state |
| `tests/neo-air-sdcard-test.sh` | 29 | the card writer: four refusals, the confirmation, the write order, partition naming for both device shapes |

Neither needs root, a loop device, a card or a board. Everything
destructive is a stub that records what it was asked to do, and the two
scripts take `NEO_SYS`, `NEO_MOUNTS`, `NEO_ROOTDEV` and `NEO_MNT1/2` so
that the discovery and the filesystem work can be pointed at fixtures.

## Departures from the specification

| Departure | Why |
|---|---|
| Sources and artefacts live in `$NEO_WORK`, not in an in-tree `out/` | a build tree inside the checkout made every archived image here claim a dirty tree once. See `.gitignore` |
| `flash-emmc.sh` has four refusals, not two | the running root and the missing bootloader image were both reachable states that the specification's version writes through |
| `sdcard.sh` checks `removable` in sysfs | a name beginning with `sd` is not evidence, and the kernel already knows |
| The `PARTUUID` in the overlay is a visible placeholder | a plausible stale value boots the wrong filesystem; an impossible one fails at the first attempt with the reason on the console |
| Two test suites | the specification asks for neither. `flash-emmc.sh` runs on the board twice in the project's life, and would otherwise be trusted rather than tested |
| The configuration guard runs before the toolchain probe in both build scripts | checking the toolchain first put the in-repository guard behind a condition no authoring laptop can satisfy, making it a guard nobody could test |

## Pitfalls, and what guards each one

| Pitfall | Guard |
|---|---|
| A partition starting below sector 2048 overwrites U-Boot | the number is in one `printf` in each of two scripts, and both tests assert it by reading what `sfdisk` was given on stdin |
| Pin 2 of the debug header carries 5 V onto a 3.3 V line | the red lead is taped rather than merely unused, and `docs/DESIGN.md` gives the wiring per pin |
| Block device names are assigned in probe order | the eMMC is found by sysfs type, never by name, and `root=` is by `PARTUUID` |
| `brcmfmac` is a module, and a rootfs built before the modules exist has no Wi-Fi and no message | `mkrootfs.sh` refuses without `$NEO_OUT/kernel-version`, and asserts `brcmfmac` is in `modules.dep` after `depmod` |
| The NVRAM file `brcmfmac` needs is not a kernel option, and Debian ships it under a name the driver never asks for | `mkrootfs.sh` installs `brcmfmac43430-sdio.AP6212.txt` under the board-specific name and prints its `sha256sum`, so the project has no unpinned input |
| The device-tree path moved in 6.5 | `kernel/build.sh` looks in both and says which it found; a missing `.dtb` gives a board that stops after `Starting kernel ...` with nothing further |
| `sudo` drops the pinned environment, and some sudo implementations ignore `-E` while saying so only on stderr | the root-needing steps go through `./go neo-air`, which sources `toolchain.env` inside the sudo, and `$NEO_WORK` is derived from `SUDO_USER` rather than from `$HOME` |

## Where the rest is

[docs/DESIGN.md](docs/DESIGN.md) has the four figures and the ownership
table. [docs/BRINGUP.md](docs/BRINGUP.md) is the board work in order, from
the first cable to the eMMC boot. [JOURNAL.md](JOURNAL.md) is what actually
happened, including the things that were wrong first.
