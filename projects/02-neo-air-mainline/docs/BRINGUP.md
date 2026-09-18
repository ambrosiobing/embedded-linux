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
    debootstrap qemu-user-binfmt sunxi-tools
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
. projects/02-neo-air-mainline/toolchain.env
sh projects/02-neo-air-mainline/uboot/build.sh
sh projects/02-neo-air-mainline/kernel/build.sh
sudo -E sh projects/02-neo-air-mainline/rootfs/mkrootfs.sh
```

`sudo -E`, because `sudo` keeps its own environment and the pins would be
lost. The script refuses rather than building something unpinned.

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
sudo -E sh projects/02-neo-air-mainline/tools/sdcard.sh -n /dev/sdX
sudo -E sh projects/02-neo-air-mainline/tools/sdcard.sh /dev/sdX
```

The dry run first, always. The real run asks you to type the device path
back before it writes anything, which exists because the first thing anyone
does after "it did not work" is press the up arrow.

The script refuses `/dev/sda` and friends by name, and refuses anything the
kernel reports as non-removable.

## 4. First power-on

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

If Debian's `firmware-brcm80211` does not carry one, the AP6212 `nvram.txt`
from the FriendlyElec vendor image or from `armbian/firmware` goes in under
the board-specific name.

**This is the only vendor artefact in the project.** Record where it came
from and its `sha256sum` in this file when it is installed, because it is
the one input that is not pinned by `toolchain.env`.

Then:

```
cp /etc/wpa_supplicant/wpa_supplicant-wlan0.conf.example \
   /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
```

Fill in the SSID and passphrase **on the card**, never in the repository.
`systemctl enable --now systemd-networkd wpa_supplicant@wlan0`, then
`ip -4 addr show wlan0`. That is criterion 3.

## 6. Provision the eMMC

Still booted from the card:

```
sh /boot/flash-emmc.sh -n
sh /boot/flash-emmc.sh
```

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

With the card removed, erase the eMMC bootloader:

```
dd if=/dev/zero of=/dev/mmcblkN bs=1024 seek=8 count=1024 conv=fsync
```

Power off. Connect the micro USB port to the PC rather than to its supply,
and power on. `lsusb` on the host should show:

```
1f3a:efe8 Allwinner Technology sunxi SoC OTG connector in FEL/flashing mode
```

Then:

```
sudo -E sh projects/02-neo-air-mainline/tools/fel-boot.sh
```

U-Boot appears on the console, running from SRAM and DRAM with nothing on
either card. From its prompt, write the bootloader back:

```
=> mmc dev 2
=> mmc write <addr> 0x10 0x800
```

`0x10` is sector 16, which is byte 8192 at 512 bytes per sector, which is
the same address the boot ROM probes and the same one every script in this
project writes to.

That is criterion 6, and it is the interview story: a board with no
bootloader on either medium, recovered over USB without opening anything.

## 8. Write it down

`docs/boot-chain.md`: every stage, its address and its medium, from the
BROM to systemd. The addresses are the part worth having, because they are
what transfers to the next non-Pi board.
