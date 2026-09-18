# Journal: Project 2

What actually happened, in order, including the things that were wrong
first. [DECISIONS.md](../../walkthrough/DECISIONS.md) is the distilled list
of choices; this is the path that produced them.

All entries are 18 September 2026 unless noted.

## 1. The specification first, and the ownership table earned its place

The method this repository settled on after Project 1 got it backwards:
read the specification, write the design document with every specified
figure redrawn as text, and only then write code.

Four figures were asked for and all four are in
[docs/DESIGN.md](docs/DESIGN.md). Redrawing the boot chain as addresses
rather than arrows is what made the two numbers visible: the bootloader at
byte 8192, the first partition at sector 2048. Everything dangerous in this
project is about the gap between them.

The ownership table found three places where two things write one resource,
which is exactly what it exists for:

- the micro USB port is the 5 V supply during normal work and the FEL
  recovery port when the PC is host, and the two are mutually exclusive
- `extlinux.conf` is written by the rootfs build and rewritten by the
  provisioning script
- `/etc/fstab` likewise

The last two are deliberate: the overlay cannot know the `PARTUUID` of a
partition that does not exist when the overlay is written. So the decision
recorded is what the overlay ships instead.

**A placeholder that cannot boot, rather than a value that might.**
`root=PARTUUID=FILLED-BY-FLASH-EMMC` fails at the first attempt with the
reason on the console. A stale `PARTUUID` copied from a previous card boots
the wrong filesystem, or drops to a prompt naming a device that really does
exist somewhere else, and both of those are hours.

## 2. A refusal the specification does not have

`flash-emmc.sh` in the specification checks two things before it writes:
that a device reporting type MMC exists, and that it is not mounted.

Both of those pass on a board that is already booted from the eMMC. The
script then writes a bootloader over the one it is running from, partitions
the disk under itself, and the board is gone. The window is small and the
situation is not exotic: it is what happens the second time somebody runs
the provisioner, having forgotten to put the SD card back.

So there is a third refusal, comparing the target against the device
carrying `/`. And while testing it, a fourth: `dd` with a missing input
file writes nothing and reports success, so a missing bootloader image is
refused by name rather than discovered at the next power-on.

## 3. The guard that no laptop could reach

Both build scripts refuse to build inside the checkout. `.gitignore`
records why at length: a build tree in the repository once made every
archived image claim a dirty tree, so the provenance was wrong about the
one thing it exists to get right.

The guard was written after the toolchain check. `gcc-arm-linux-gnueabihf`
is not installed on the authoring laptop, so every attempt to reach the
guard stopped one line earlier, and it could not be tested on the machine
it was written on.

Configuration errors are now refused before the environment is probed. A
misconfigured `NEO_SRC` is wrong on every machine; a missing cross compiler
is wrong only on this one. Proved in both directions afterwards: it fires
when `NEO_SRC` is inside the checkout, and stays quiet when it is not.

## 4. Two tests the specification does not ask for, and what they caught

`flash-emmc.sh` runs on the board twice in this project's entire life. Both
times it is being trusted rather than tested, and it is the one program
here that can destroy the system it is running on.

So both destructive scripts are tested with fixtures and recording stubs:
a fake `/sys/block` so the target is discovered the way the real one is, a
fake `/proc/mounts`, overridable mount points, and stubs for `dd`,
`sfdisk`, `mkfs.ext4` and the rest that record their arguments and succeed.
No root, no loop devices, no board.

Writing them required one change to the code: the mount points were
hardcoded as `/mnt/e1` and `/mnt/e2`, which made the copy, bootconfig and
verify states untestable without writing to the real `/mnt`. They are now
`NEO_MNT1` and `NEO_MNT2`, which is the difference between a state machine
that is tested and one that is read.

**The tests caught two things, and both were in the tests.**

The assertion for sector 2048 failed against a script doing exactly the
right thing. The partition table is piped to `sfdisk` on **stdin**, not
passed as an argument, so a stub that records only `argv` cannot see the
single most important number in the project. `sfdisk` now has its own stub
that records both.

That is worth stating as a rule rather than a fix: a stub that captures
less than the program consumes will report a correct program as broken, and
the tempting response on the next reading is to weaken the assertion rather
than the stub.

The second was the same shape. The write-order assertion in the card test
matched `sfdisk /dev/sdz` while the stub records `sfdisk -q /dev/sdz`, so
the pattern found nothing, the comparison ran against one line number, and
a correct script failed. Anchored on the command name now.

## 5. Proving the order assertion, and three path failures on the way

The write order in `sdcard.sh` is a real decision. `sfdisk` writes sector
0, so a bootloader written first loses its first 512 bytes to it. The
`eGON.BT0` header at byte 8192 survives either order and the SPL that
follows does not, which means the wrong order produces a board that reads
its header, starts, and dies with nothing on the console.

An assertion that cannot fail is not an assertion, so it was proved by
swapping the two writes in a copy and watching exactly that one fail. It
took four attempts, all of them environment rather than logic:

- `/tmp` in Git Bash is a Windows path that native Python cannot open
- a Windows-style `TMPDIR` makes `mktemp -d` return `C:/Users/...`, and a
  Windows path in `PATH` is never searched, so the stubs were ignored and
  the **real** `dd` ran against `/dev/mmcblk1`
- exact-block text matching across a heredoc was fragile; line numbers were
  not
- `sdcard.sh` finds the overlay relative to its own directory, so copying
  the script alone into a scratch folder broke it. The whole project tree
  has to be mirrored

The second of those is the one that matters. A test harness whose stubs are
silently not on `PATH` does not fail: it runs the real tools. The only
reason it was noticed is that the real `dd` said `Permission denied` on a
device that does not exist on this laptop.

## 6. What is deliberately not done yet

No cross toolchain is installed here, so the build scripts have been
exercised only as far as their refusals. Nothing has compiled. The board is
in its box and the console cable is not attached.

The order that follows is deliberate and is in
[docs/BRINGUP.md](docs/BRINGUP.md): the console cable is attached and
`picocom` is already running before the board is first powered, so the SPL
banner is captured rather than missed. It is the first line of evidence in
the project and it appears about a second after power, once.

## 7. The first build, and two guards that were wrong before the compiler was

The cross toolchain went onto JPTOUPM678 and `./go neo-air uboot` ran for
the first time. Three things went wrong before a single object compiled,
and two of them were mine.

**`qemu-user-static` does not exist on Ubuntu 26.04.** It is a virtual
package now, provided by `qemu-user-binfmt`, and `apt` refuses to pick a
provider for you. The whole install failed on that one name, so nothing was
installed at all.

The consequence in `mkrootfs.sh` was worse than the apt message, because it
was silent. The script copied `$(command -v qemu-arm-static)` into the
chroot with a `|| true` after it, and on this release there is no such
binary: only a dynamically linked `/usr/bin/qemu-arm`. So it would have
copied nothing and said nothing, and whether the second stage worked would
have come down to a binfmt flag the script never looked at.

It now reads the flag. A registration carrying `F` keeps the interpreter
open across a chroot and nothing needs copying; without it, a binary is
copied, preferring the static one and falling back to the dynamic. The
board's registration exists and the flag is the next thing to check when
the rootfs step runs.

**My own U-Boot guard refused a build that had just done the right thing.**
`merge_config.sh` printed

    Value of CONFIG_MMC_SUNXI_SLOT_EXTRA is redefined by fragment ...
    Previous value: CONFIG_MMC_SUNXI_SLOT_EXTRA=-1
    New value: CONFIG_MMC_SUNXI_SLOT_EXTRA=2

and the script treated the word "redefined" as failure. That line is the
fragment overriding the defconfig, which is the entire purpose of the
fragment, and that particular symbol is the one that makes U-Boot see the
eMMC at all. So the guard fired on success, on the single most important
line in the file.

It was also redundant. The check immediately after it compares every
fragment line against the produced `.config`, which is the question that
matters: not what the merge said about its work, but whether the option is
there. That check passed on the next run and printed `every fragment option
is present in .config`.

This repository has now documented four guards that refuse on evidence they
should not, three of them in other people's scripts and this one in mine,
written the day after writing the decision that names the pattern.

**Then the compiler, and this one is not a bug anywhere.** The build
stopped in `scripts/dtc/pylibfdt`:

    libfdt_wrap.c: error: too few arguments to function
    'SWIG_Python_AppendOutput'; expected 3, have 2

SWIG 4.3 added a third argument to that function. U-Boot `v2024.10` carries
a copy of dtc whose typemaps still call the two-argument form, and Ubuntu
26.04 ships SWIG 4.4. `pylibfdt` is not skippable here, because
`u-boot-sunxi-with-spl.bin` is a binman image and binman needs it.

Three options, and only one of them leaves the project honest:

- patch the vendored dtc inside a pinned tree, which makes the pin a lie
- hold the host's SWIG back, which makes the build depend on an apt pin
  that nothing in this repository can state
- move the tag, and record why

`UBOOT_TAG` is now `v2025.10`, which is also the vintage of the host's own
`u-boot-tools`. The reason is written where the pin is, not only here,
because the next person to read `toolchain.env` will be looking at the
number rather than at this file.

The expected SPL banner in `docs/BRINGUP.md` moved with it. A milestone
that names a version is a claim, and it was one line away from being a
stale one.
