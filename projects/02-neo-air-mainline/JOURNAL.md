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
