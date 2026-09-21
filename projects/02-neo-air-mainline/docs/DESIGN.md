# Project 2: design

Written before any build script, which is the order Project 1 got wrong and
Project 15 got right. The four figures the specification asks for are
redrawn here as text, and the ownership table at the end is the part that
earns its keep: this project has three places where two things write the
same resource, and every one of them is a way to brick a boot.

## What makes this project different from the rest

Every other project in this repository starts after a bootloader has
already run. The Raspberry Pi's is closed firmware on the video core: it
reads `config.txt`, loads a kernel, and the first thing any of those
projects sees is Linux starting. Here there is no vendor firmware. The
Allwinner H3 boot ROM is the only code that is not ours, it is 32 KB in
the SoC and it cannot be changed, and everything after it is built from
source in this directory.

It is also the only project with no Yocto. U-Boot, the kernel and a Debian
root filesystem are built directly, which is why this lives under
`projects/` with its own build scripts rather than adding recipes to
`meta-bench/`. Project 4 already keeps scripts here, so the layout is not
new.

One later project depends on the result. Project 3 measures and shortens
the boot this one produces, so the boot has to be measurable, which means
`CONFIG_PRINTK_TIME=y` and a console that is attached from the SPL banner
onward.

**This paragraph used to say that Project 16 reuses the same small system
for the cellular tracker. It does not, and cannot.** The root README
assigns that project a Raspberry Pi 3, and the reason is physical rather
than a preference: its modem is a SIM7070G on a standard Raspberry Pi
40-pin GPIO extension header, and this board has a 24-pin header and a
separate 4-pin debug UART. The HAT does not stack on it. The sentence is
corrected here rather than deleted because it was the only place the two
projects were connected, and a reader who remembers it should find out why
it was wrong. See `projects/16-nbiot-tracker/docs/DESIGN.md`, which
resolves the conflict in full.

## Figure 1: the boot chain, and where each stage lives

The addresses matter more than the arrows. Every stage is found by the
previous one at a fixed place, and the two failures that cost the most are
both address collisions.

```
  ADDRESS / MEDIUM                 STAGE                    RUNS IN

  in the SoC, unchangeable         BROM                     SoC ROM
      |
      | probes for an eGON.BT0 header at byte 8192
      |
      +--> mmc0, SD card, byte 8192 ....... found? --> SPL
      |                                       |
      +--> mmc2, eMMC, byte 8192 .......... found? --> SPL
      |                                       |
      +--> neither: FEL mode, waits on the micro USB OTG port
                                              |
                                              v
  SRAM, about 32 KB budget          SPL       initialises the DDR3
                                              controller, then loads
                                              u-boot.img from the same
                                              medium it came from
                                              |
                                              v
  DRAM, 512 MiB                     U-Boot    distro boot: scans
                                              partitions for
                                              extlinux/extlinux.conf
                                              |
                                              v
  partition 1, ext4, label boot     kernel    zImage plus
                                              sun8i-h3-nanopi-neo-air.dtb
                                              console=ttyS0,115200
                                              root=PARTUUID=...
                                              |
                                              v
  partition 2, ext4, label root     systemd   Debian bookworm armhf
```

Two things in that picture are worth saying out loud.

**The SPL loads U-Boot from the medium it was itself loaded from.** So a
board with a bootloader on the SD card and a root filesystem on the eMMC is
a configuration to be chosen deliberately, not one to arrive at by
accident. The development medium is the SD card and the production medium
is the eMMC, and after provisioning the SD card is removed rather than left
in.

**Byte 8192 is 8 KiB, and the first partition starts at 1 MiB.** That gap
is the single most important number in the project. A partition table that
starts a partition at the usual sector 63, or any sector below 2048, puts a
filesystem on top of U-Boot. The symptom is not a clear error: the board
either stops after the SPL banner or mounts a filesystem that is corrupt in
a way `fsck` reports but cannot explain.

## Figure 2: console and power

```
   NanoPi NEO Air, underside                 Renkforce USB/TTL cable
   4-pin debug UART header

     pin 1  GND  -------------------------  black   GND
     pin 2  5 V  ---  NOT CONNECTED  ---     red    taped back
     pin 3  TX   -------------------------  white   RX of the cable
     pin 4  RX   -------------------------  green   TX of the cable

   micro USB port  <--- 5 V, 1 A or more, from a USB supply
                   and the same port is the FEL/OTG port to the PC
```

Crossed, because one side's transmit is the other's receive. 115200 8N1,
3.3 V logic on both sides.

**Pin 2 carries 5 V and the UART lines are 3.3 V with no protection.** A
connector seated one position out puts 5 V onto a 3.3 V pin of either the
board or the cable. The red lead is not merely unused, it is taped, so that
it cannot be the lead that finds a pin. The silkscreen is checked against
this table on every reconnection, not once.

**The board is never powered through the header while the micro USB supply
is connected.** Two supplies onto one rail is the other way this header
destroys a board.

## Figure 3: bench layout

```
    +-------------------+          +---------------------------+
    |  5 V USB supply   |          |  WSL2 host on the laptop  |
    |  1 A or more      |          |                           |
    +---------+---------+          |  picocom /dev/ttyUSB0     |
              |                    |  cross toolchain, trees   |
              | micro USB          |  sunxi-fel for recovery   |
              |                    +-------------+-------------+
              v                                  |
    +-------------------------+                  | USB
    |   NanoPi NEO Air        |                  |
    |                         |     4-pin debug  |
    |   [antenna attached]    |<-----------------+
    |                         |     UART header
    |   microSD in the slot   |
    |   eMMC on board         |
    +-------------------------+
```

The antenna is attached before the board is first powered, not before the
first Wi-Fi test. Running a transmitter without its antenna is avoidable by
never having the board powered without it.

The micro USB port has two jobs and they are mutually exclusive in
practice: it is the power input during normal work, and it is the FEL
recovery port when the PC is the host. Swapping between them means
unplugging, which is the point at which the console cable is the only thing
still attached and the only thing still talking.

## Figure 4: the state machine of tools/flash-emmc.sh

This runs **on the board**, booted from the SD card, and copies the running
system to the eMMC. Every state is idempotent and every failure leaves the
SD card untouched, so a failed run is recovered by rebooting.

```
   identify  ---- no eMMC found ------------------> refuse
      |       ---- target is mounted -------------> refuse
      |       ---- target is the running root ----> refuse
      v
   bootloader   dd u-boot-sunxi-with-spl.bin at seek=8, bs=1024
      |
      v
   partition    sfdisk: p1 at 2048 sectors, 256 MiB, bootable; p2 rest
      |
      v
   format       mkfs.ext4 on both, labels boot and root
      |
      v
   copy         rsync -aHAX --one-file-system / -> p2, /boot/ -> p1
      |
      v
   bootconfig   read PARTUUID of p2, patch extlinux.conf and fstab
      |
      v
   verify       umount both, fsck.ext4 -fn p2
      |
      v
   done         "remove the SD card and reboot"
```

Each state sets a variable naming itself and a trap reports it, so a
failure says which state failed rather than which line did.

**The refusals in `identify` are the whole safety argument.** Block device
names are assigned in probe order, so the eMMC is `mmcblk1` on some kernels
and `mmcblk2` on others, and a script with a device name in it eventually
writes to the card it booted from. The target is found by reading
`type` in sysfs and checking for `MMC`, and then checked against
`/proc/mounts` and against the device backing `/`.

The specification's version checks sysfs type and `/proc/mounts`. The third
refusal, that the target is not the device the running root is on, is added
here: on a board booted from eMMC by mistake, the first two checks pass and
the script overwrites the system it is running from.

## Ownership: which component owns which resource

The table that prevents the commonest class of bug. A resource with two
owners is where this project bricks a board.

| Resource | Owner | When | Never touched by |
|---|---|---|---|
| `mmc0`, the SD card | BROM at byte 8192, then U-Boot, then the kernel | development medium, whole project | `flash-emmc.sh`, which must leave it bootable |
| `mmc1`, SDIO | the kernel's `brcmfmac`, with the reset line owned by the `mmc-pwrseq-simple` node in the device tree | after the kernel starts | U-Boot, which has no reason to touch it |
| `mmc2`, the eMMC | `flash-emmc.sh` while provisioning, the BROM and U-Boot afterwards | production medium | anything, while it is mounted |
| byte 8192 of either medium | U-Boot's SPL image | written by `sdcard.sh` on the host, by `flash-emmc.sh` on the board | any partition, which is why partition 1 starts at 1 MiB |
| UART0, PA4 and PA5 | SPL, then U-Boot, then the kernel console, then a `getty` | in that order, one at a time | nothing else; there is no second console |
| the micro USB port | the 5 V supply during normal work, the PC during FEL recovery | never both | |
| `/boot/extlinux/extlinux.conf` | written by `mkrootfs.sh` from the overlay, **rewritten** by `flash-emmc.sh` | build time, then provision time | |
| `/etc/fstab` | same two writers, same two times | | |
| the root identity | `PARTUUID`, never a device name | everywhere it is referenced | |

The last three rows are the ones to argue with. Two writers on one file is
exactly what this table exists to catch, and here it is deliberate: the
overlay cannot know the `PARTUUID` of a partition that does not exist yet,
so the file is written twice on purpose.

The decision that follows is that the overlay's copy carries a **visible
placeholder** rather than a plausible value:

```
append console=ttyS0,115200 root=PARTUUID=FILLED-BY-FLASH-EMMC rootwait rw
```

A placeholder that cannot boot fails loudly at the first attempt. A
plausible-looking stale `PARTUUID` copied from a previous card boots the
wrong filesystem, or drops to an initramfs prompt with a message about a
device that does exist somewhere. The project's own habit applies: a value
that was never set is worse than a blank only when the blank is silent, and
this one is not.

## What is decided here and why

**Every input is pinned in `toolchain.env`** and the build scripts refuse
to run without it. U-Boot tag, kernel tag, Debian suite. An unpinned build
of a bootloader is not reproducible and this project's whole claim is that
the chain is known.

**Configuration is fragments merged with `merge_config.sh`,** never a
`.config` committed to the repository. That is the same rule as the Yocto
projects' kernel fragments and it exists for the same reason: a committed
`.config` is a snapshot of one moment of one defconfig and nothing says
when it stopped matching.

**`CONFIG_BRCMFMAC` is a module, and that is a trap rather than a
preference.** If the root filesystem is assembled before the modules are
installed, `/lib/modules/<version>/` is empty, and Wi-Fi does not fail: it
is absent, with no interface and no message that names the cause.
`mkrootfs.sh` therefore installs the modules and runs `depmod -a` as part
of building the rootfs, not as a later step.

**The Wi-Fi NVRAM file is the only vendor artefact in the project.** It is
documented with its origin and its checksum, because without it `brcmfmac`
loads its firmware and then times out bringing the SDIO clock up, which
reads as broken hardware.

**Boot logs are evidence, stored as text and diffed.** `docs/bootlog-sd.txt`
and `docs/bootlog-emmc.txt` are complete captures from power-on to login.
An unexpected new line in `dmesg` between runs is treated as a regression,
which is only possible because the captures are complete rather than
excerpted.

## What can be built before the board is touched

All of it except the boots. The cross builds run on the WSL2 host, and the
provisioning script's logic can be tested against loopback devices rather
than against an eMMC. That ordering is deliberate: the first time the board
is powered, the console cable is already attached and `picocom` is already
running, so the SPL banner is captured rather than missed.
