# Project 2: board work, in order

From the first cable to a board booting mainline off its eMMC. Read
[DESIGN.md](DESIGN.md) first, particularly the ownership table.

**The console cable is attached and `picocom` is already running before the
board is first powered.** The SPL banner appears about a second after power
and once. It is the first line of evidence in the project, and a boot log
that starts halfway through is not a boot log.

## 0. The host, once

```
sudo apt install gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf \
    build-essential bison flex libssl-dev swig python3-dev python3-setuptools \
    device-tree-compiler u-boot-tools bc libncurses-dev rsync picocom \
    debootstrap qemu-user-binfmt sunxi-tools libgnutls28-dev pkg-config
```

The build scripts name whichever of these is missing rather than failing
partway through a make.

The USB/TTL adapter has to reach WSL2. From an administrator PowerShell on
the Windows side:

```
usbipd list
usbipd bind --busid 2-3
usbipd attach --wsl --busid 2-3
```

`bind` is once per adapter; `attach` is after every replug and after every
`wsl --shutdown`. In WSL it appears as `/dev/ttyUSB0`.

## 1. Wire the console, with the board unpowered

Three wires, and the fourth is taped.

| Board debug header | Cable lead | Note |
|---|---|---|
| pin 1, GND | black | common reference |
| pin 2, 5 V | red, **taped back** | not merely unused |
| pin 3, board TX | white, cable RX | crossed |
| pin 4, board RX | green, cable TX | crossed |

**Check the silkscreen against this table every time, not once.** Pin 2
carries 5 V and the UART lines are 3.3 V with no protection. A connector
seated one position out puts 5 V onto a 3.3 V pin of either the board or
the cable, and the red lead is taped so that it cannot be the lead that
finds one.

Power comes from the micro USB port, never from the header, and never from
both.

```
picocom -b 115200 /dev/ttyUSB0
```

Start it now and leave it running.

## 2. Build, in this order

```
./go neo-air uboot
./go neo-air kernel
sudo ./go neo-air rootfs
```

**Sudo goes on the entry point, never on the script.** `./go neo-air`
sources `toolchain.env` itself, so with sudo in front of it the pins are
established inside the sudo. Sourcing the file in your own shell and then
running the script under sudo does not work: sudo resets the environment,
and `-E` does not rescue it on a sudo that ignores `-E`, which this bench's
build host has. The script refuses rather than building something
unpinned, which is how that was found.

The kernel before the root filesystem, and that order is not cosmetic.
`brcmfmac` is a module; a root filesystem assembled before the modules
exist has an empty `/lib/modules/<version>/`, and the board then boots
perfectly with no wireless interface and nothing in `dmesg` naming a cause.
`mkrootfs.sh` refuses without `$NEO_OUT/kernel-version` for that reason,
and asserts `brcmfmac` is in `modules.dep` after `depmod`.

Two things to read in the build output rather than scroll past:

- `every fragment option is present in .config`, from both build scripts.
  A silently dropped fragment is this repository's oldest recurring
  failure, and for the U-Boot one the symptom is a shorter `mmc list`
  rather than an error.
- the device-tree path the kernel build reports. Kernels before 6.5 keep
  the sunxi trees in `arch/arm/boot/dts/` and later ones in
  `arch/arm/boot/dts/allwinner/`. A missing `.dtb` gives a board that stops
  after `Starting kernel ...` with nothing further on the console.

## 3. Write the card

```
lsblk
sudo ./go neo-air card -n /dev/sdX
sudo ./go neo-air card /dev/sdX
```

The dry run first, always. The real run asks you to type the device path
back before it writes anything, which exists because the first thing anyone
does after "it did not work" is press the up arrow.

The script refuses `/dev/sda` and friends by name, and refuses anything the
kernel reports as non-removable.

## 4. First power-on

**The eMMC is not blank, and nothing in this project put anything there.**
The board arrived with a FriendlyElec vendor image already on mmc2. That
was discovered on the first bring-up night, by taking the card out and
watching the status LED settle into a heartbeat blink: a rhythmic blink is
the kernel's heartbeat trigger, and neither the boot ROM nor U-Boot
blinks anything.

Two consequences, and the second is the one that can mislead you for an
hour:

- A board with no card still boots. The boot ROM finds nothing at byte
  8192 of mmc0, moves to mmc2 as designed, and starts the vendor system.
- **A booting board is therefore not evidence that this project's image
  booted.** Whenever you want to know whose system is running, ask it
  rather than infer it from the fact that something came up:

```
uname -r
cat /etc/os-release
findmnt /
```

`6.12.0` and Debian bookworm are ours. Anything else is the vendor image,
and the answer to "why does my change have no effect" is that you are
looking at a different operating system.

Card in, antenna on, `picocom` already running, then power.

What to expect, in order:

- `U-Boot SPL 2025.10` within about a second, matching `UBOOT_TAG`
- `DRAM: 512 MiB`
- a two second countdown, then `=>`

At the prompt, before going further:

```
=> mmc list
```

Both media must appear. If only the SD card does,
`CONFIG_MMC_SUNXI_SLOT_EXTRA=2` did not reach the build, and the eMMC half
of this project is not possible until it does. That is criterion 1.

Then let it boot. `neo-air login:` is the second milestone.

The first boot generates this board's ssh host keys, which takes a few
seconds and happens once. The image deliberately ships without them: they
would otherwise be the build machine's keys, identical on every board
written from the same tar.

**Capture the whole thing to `docs/bootlog-sd.txt`.** `picocom -g` logs to
a file; so does `script`. Complete, from the SPL banner, not excerpted:
Project 3 measures and shortens this boot and cannot do either from a log
with the beginning missing, and `CONFIG_PRINTK_TIME=y` is set so that the
capture is already usable as a baseline.

## 5. Wi-Fi

```
dmesg | grep -i brcmfmac
ls /lib/firmware/brcm/ | grep 43430
```

A firmware version line means the chip is alive. What is usually missing is
not the firmware but the NVRAM text file beside it. Without it `brcmfmac`
loads the firmware and then reports a timeout bringing the SDIO clock up,
which reads exactly like broken hardware.

`brcmfmac` looks for a name derived from the device-tree compatible string
first and a generic one second:

```
brcmfmac43430-sdio.bin
brcmfmac43430-sdio.friendlyarm,nanopi-neo-air.txt      preferred
brcmfmac43430-sdio.txt                                 fallback
```

**`mkrootfs.sh` already installed it, and this is worth knowing about.**

`firmware-brcm80211` carries neither of those two names. It carries
`brcmfmac43430-sdio.AP6212.txt`, and the AP6212 is the module on this
board: a BCM43430 with Bluetooth on one SDIO bus. NVRAM describes the
module, its crystal and its antenna path, not the carrier it is soldered
to, which is why the vendor name is the useful one.

So the file is copied to the board-specific name during the root filesystem
build, and the script prints its `sha256sum` when it does. There is no
vendor image to download and nothing unpinned left in this project.

What went onto the card, recorded here because this is the one file whose
provenance is worth writing down rather than inferring:

| | |
|---|---|
| package | `firmware-brcm80211` 20230210-5, bookworm `non-free-firmware` |
| shipped as | `brcmfmac43430-sdio.AP6212.txt` |
| installed as | `brcmfmac43430-sdio.friendlyarm,nanopi-neo-air.txt` |
| sha256 | `fdef0603345dd023ad28c0eff2d5167915c617bee2d6944da9a6da1c4ac87ca5` |

A different sha256 on a later build means Debian updated the package, not
that something is wrong. The value is here so the difference is visible
rather than silent.

If `dmesg` still shows the SDIO timeout, check the name the driver asked
for rather than assuming the file is wrong:

```
dmesg | grep -i 'brcmfmac.*\(nvram\|txt\|failed\)'
```

A name other than `brcmfmac43430-sdio.friendlyarm,nanopi-neo-air.txt` means
the device tree's root compatible is not what `BOARD_COMPATIBLE` in
`toolchain.env` says, and that is the thing to fix.

Then:

```
cp /etc/wpa_supplicant/wpa_supplicant-wlan0.conf.example \
   /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
```

Fill in the SSID and passphrase **on the card**, never in the repository.
`systemctl enable --now systemd-networkd wpa_supplicant@wlan0`, then
`ip -4 addr show wlan0`. That is criterion 3.

## 6. Provision the eMMC

Still booted from the card. First confirm the boot partition is mounted,
because the whole step depends on it:

```
findmnt /boot
```

It must show the card's first partition on `/boot`. If it does not, the
fstab `/boot` line did not take and `flash-emmc.sh` will refuse for want of
a bootloader image; reflash the card with a build that carries the two-line
fstab. Then:

```
sh /boot/flash-emmc.sh -n
sh /boot/flash-emmc.sh
```

`flash-emmc.sh` travels on the card, written to the boot partition by
`sdcard.sh`, so `/boot/flash-emmc.sh` is present on the running board.

The dry run names the device it discovered. It finds the eMMC by reading
`type` in sysfs, never by name, because names are assigned in probe order
and the eMMC is `mmcblk1` on some kernels and `mmcblk2` on others.

It refuses four ways: no eMMC, a mounted target, a target carrying the
running root, and a missing bootloader image. Every state is idempotent and
a failure names the state rather than the line, so a failed run is
recovered by rebooting from the card and running it again.

Then power off, **remove the card**, power on. The boot ROM finds nothing
at byte 8192 of `mmc0` and moves to `mmc2`. Capture this one to
`docs/bootlog-emmc.txt`, and check `findmnt /`. That is criterion 4.

Run it a second time to prove idempotence. Criterion 5.

## 7. Break it on purpose, then recover

The last criterion is the one worth doing rather than assuming. A recovery
path that has never been used is a recovery path whose state nobody knows.

Erase the eMMC bootloader while booted **from the card**, so the running
system is not the one being broken. `mmcblkN` is whichever device sysfs
reports as type MMC; `flash-emmc.sh -n` names it for you.

```
dd if=/dev/zero of=/dev/mmcblkN bs=1024 seek=8 count=1016 conv=fsync
```

**The count is 1016, not 1024, and the difference is the whole point of
this project.** The bootloader starts at byte 8192 and partition 1 starts
at sector 2048, which is byte 1048576. The gap between them is 1040384
bytes, which is 1016 KiB. A count of 1024 writes 1 MiB, overruns the
boundary by 8 KiB, and zeroes the ext4 superblock that sits 1 KiB into the
partition.

That is not hypothetical. It is what happened the first time this was run,
and the consequence was that `ext4load` from the eMMC boot partition failed
with `Can't set block device` at exactly the moment the recovery needed it.
The image had to be fetched from the SD card instead.

With 1016, **the partitions and their contents survive**: the eMMC's boot
partition still holds `u-boot-sunxi-with-spl.bin`, and that is the copy
written back at the end, with no card involved.

Power off. **Remove the card.** Connect the micro USB port to the PC rather
than to its supply, and power on. With no bootloader on either medium the
boot ROM enters FEL, and the host should show:

```
1f3a:efe8 Allwinner Technology sunxi SoC OTG connector in FEL/flashing mode
```

Then:

```
sudo ./go neo-air fel
```

U-Boot appears on the console, running from SRAM and DRAM with nothing
booted from either medium. From its prompt, write the bootloader back.

**Watch the device numbers: U-Boot does not number the controllers the way
the boot ROM does.** The boot ROM calls the eMMC mmc2, which is what the
SPL banner says. U-Boot calls it **mmc 1**, and calls the SDIO Wi-Fi mmc 2.
The board tells you itself, at the top of every boot:

```
MMC:   mmc@1c0f000: 0, mmc@1c10000: 2, mmc@1c11000: 1
```

`1c0f000` is the card slot, `1c10000` is the SDIO radio, `1c11000` is the
eMMC. So the eMMC is **dev 1** at the U-Boot prompt, and `mmc dev 2` would
select the Wi-Fi controller. Read that line on your board rather than
trusting this paragraph:

```
=> mmc list
=> mmc dev 1
=> ext4load mmc 1:1 0x42000000 u-boot-sunxi-with-spl.bin
=> mmc write 0x42000000 0x10 0x3EC
```

`ext4load` reads the image from the eMMC's own boot partition, which the
`dd` above deliberately did not touch. `0x10` is sector 16, which is byte
8192 at 512 bytes per sector, which is the same address the boot ROM probes
and the same one every script in this project writes to.

**`0x3EC` is 1004 sectors, which is exactly the image**, 513912 bytes
rounded up to a whole sector. The obvious-looking `0x800` is 2048 sectors:
it would run from sector 16 to sector 2064 and overwrite the first 8 KiB of
partition 1, which is the same boundary mistake as the erase above, made
twice in the same procedure. Write the size of the thing you are writing,
not a round number that looks like a megabyte.

If the eMMC's boot partition is unreadable because a previous run used the
wrong count, put the SD card back in and take the image from there instead:

```
=> mmc dev 0
=> mmc rescan
=> ext4load mmc 0:1 0x42000000 u-boot-sunxi-with-spl.bin
=> mmc dev 1
=> mmc write 0x42000000 0x10 0x3EC
```

That is criterion 6, and it is the interview story: a board with no
bootloader on either medium, recovered over USB without opening anything.

## 8. Write it down

`docs/boot-chain.md`: every stage, its address and its medium, from the
BROM to systemd. The addresses are the part worth having, because they are
what transfers to the next non-Pi board.
