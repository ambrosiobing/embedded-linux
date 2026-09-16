# 08. Board bring-up

## Which board, and why it is not a free choice

An image is built for one `MACHINE`. The kernel, the device tree, the tune
flags and `config.txt` are all baked in, and `./go flash` does not compare
the image against the card it is writing to. A `raspberrypi4-64` image on a
card for a Pi 3 does not warn, it simply does not boot, and the symptom is
a board that looks dead.

So the board is decided before the build, and on this bench it is often
decided by the hardware rather than by preference. A HAT either seats on a
board or it does not: the 40-pin header is standard but the surrounding
ports are not, and a HAT with screw terminals can foul a connector that
moved between models. Project 8 changed machine after the DAQ HAT had been
stacked, which cost a rebuild of a kernel and an image.

**The order that avoids it:** stack the HAT on the board you intend to use,
confirm it seats, then set `machine:` and build. Not the other way round.

**And read the board's own label before writing anything about it.**
Project 8 spent two days reasoning about which Raspberry Pi the HAT was on,
invented a mechanism for why it did not fit another one, and wrote
"Cortex-A53 at 1.4 GHz" into a comparison table. The board turned out to be
a 3B v1.2 from 2015: same core at 1.2 GHz, 1 GB of memory, 100 Mbit
Ethernet behind the USB hub. It had been on the desk the whole time with
its model and revision printed on it.

**The board then moved a third time, and the reason is worth keeping.** An
adapter arrived, the HAT fitted the Pi 4 after all, and the machine went
back. Not because the Pi 4 is better, but because the acceptance thresholds
had been written for it: measured on the board they were written for they
are criteria, and measured on another they are criteria with an asterisk in
every row. The alternative, relaxing the thresholds to suit the board in
hand, turns a criterion into a description of what happened.

The churn is paid once. A footnote in a results table is paid by every
reader, forever. That is the whole trade, and it is why the numbers did not
move when the board did.

The first board is not wasted: it becomes the second board. Same kernel,
same userspace, slower core, busier interrupt controller. A relative claim
that holds on both is stronger than an absolute one that holds on one.

One thing did survive that, by luck rather than by care.
meta-raspberrypi's `raspberrypi3-64` covers the whole BCM2837 family, so a
3B and a 3B+ take the same image and the machine setting happened to be
right. Machine names are coarser than board names, which is convenient
here and misleading in general: `raspberrypi4-64` and `raspberrypi3-64` are
not interchangeable, and neither tells you which revision is under the HAT.

**And when the board changes, the thresholds do not.** Acceptance criteria
written as absolute numbers were written for a particular piece of silicon.
Moving them to suit a slower board turns a criterion into a prediction.
Keep them, mark which board they were written for, and record which board
produced each row. Where a criterion can be expressed relatively, one
configuration against another on the same hardware, prefer that: it
survives a change of board and it is usually the claim you actually wanted
to make.

## Flashing

```sh
./go flash /dev/sdX
```

The script refuses a device that is not a block device, refuses `/dev/sda`,
`/dev/nvme0n1` and `/dev/vda` outright as likely system disks, shows
`lsblk` for the target, and requires you to type the device path back before
it writes anything.

It uses `bmaptool` rather than `dd`. The `.bmap` file lists which blocks are
actually non-empty, so a 1 GB image holding 200 MB writes 200 MB. Minutes
become seconds, and checksums are verified as it goes.

**The `dd` habit is worth breaking** for a second reason: a mistyped `dd`
target is one of the few commands that can destroy a laptop's filesystem
without warning. Confirmation and a refusal list cost nothing.

## Wiring (deferred)

The bench LED modules are Joy-IT LinkerKit LK-LED10 parts with a 2.0 mm
socket, and the available jumper wires are 2.54 mm Dupont. They do not mate,
so this wiring has never been connected and the LED output is deferred. The
manufacturer says it in one line: a baseboard and a connecting cable are
required.

Three bare LEDs with 330 Ohm series resistors from GPIO17, GPIO27 and GPIO22
to a ground rail work immediately and are unambiguously active high, which
is the daemon's default. The table below is for the four-pin modules,
for whenever an LK-Cable arrives.

```
                    Raspberry Pi 4, 40-pin header
        3V3  1  o o  2   5V
       GPIO2  3  o o  4   5V
       GPIO3  5  o o  6   GND ------------------- console GND (black)
       GPIO4  7  o o  8   GPIO14 TXD ------------ console RX  (white)
         GND  9  o o 10   GPIO15 RXD ------------ console TX  (green)
      GPIO17 11  o o 12   GPIO18
      GPIO27 13  o o 14   GND
      GPIO22 15  o o 16   GPIO23
         ...

    pin 11 GPIO17 --> S1 [ green  module ]  U --> pin 1  3V3
    pin 13 GPIO27 --> S1 [ yellow module ]  G --> pin 9  GND
    pin 15 GPIO22 --> S1 [ red    module ]  S2 --> not connected
```

| Signal | Pi pin | BCM line | Module pin |
|---|---|---|---|
| Green signal | 11 | GPIO17 | S1 |
| Yellow signal | 13 | GPIO27 | S1 |
| Red signal | 15 | GPIO22 | S1 |
| Supply, all three | 1 | 3V3 | U |
| Ground, all three | 9 | GND | G |
| Not connected | | | S2 |
| Console TXD | 8 | GPIO14 | cable RX, white |
| Console RXD | 10 | GPIO15 | cable TX, green |
| Console ground | 6 | GND | cable black |

The modules carry their own series resistors, so loose resistors are not
needed. Check the board: if there is no small resistor beside the LED, put
330 Ohm in series with `S1`.

### Two rules that protect the board

**`U` goes to 3V3, never to 5 V.** If the LED sits between the supply and
`S1`, then `S1` floats at the supply voltage whenever the GPIO is not
driving. 5 V on a 3.3 V input damages the pin. With `U` on 3V3 the worst
case is harmless.

**Leave the red 5 V lead of the USB/TTL cable disconnected.** The Pi has its
own supply. Two supplies on one rail is how a board and a cable are lost at
the same time.

Both are instances of the same habit: before connecting anything, ask what
voltage appears on each pin in every state, including the states where
nothing is driving.

## Networking, and how credentials reach the board

This bench has no wired network in reach, so the image joins a wireless one.
Three layers had to be present, and each absence looked identical from
`networkctl`, which showed no `wlan0` at all:

| Layer | Package | Symptom when missing |
|---|---|---|
| Firmware | `linux-firmware-rpidistro-bcm43455` | Radio never initialises |
| Driver | `kernel-module-brcmfmac` | `core-image-minimal` ships no modules, so the device never probes |
| Vendor module | `kernel-module-brcmfmac-wcc` | Chip detected, firmware found, `brcmf_attach` fails at the last step |

`wcc` is the Cypress and Infineon variant. Modern `brcmfmac` asks for it by
name at probe time, and says so in `dmesg` when it is absent, which is
faster than reasoning about what an image ought to contain.

The credentials never enter the repository. A first-boot service reads
`SSID` and `PSK` from `wifi.conf` on the FAT boot partition, which you write
from any machine after flashing. The image carries capability; the card
carries identity.

That file is usually written in Notepad, which breaks text three different
ways, all of which the parser now handles and tests: CRLF line endings, a
UTF-8 byte order mark, and no final newline. The last of those is the
interesting one, because `while read` returns false on an unterminated final
line and silently drops the last key in the file.

## The serial console (deferred to Project 2)

```sh
picocom -b 115200 --logfile boot-console.log /dev/ttyUSB0
```

Not used in Project 1. The console here is the 7 inch DSI panel, and the
bench cable is a PL2303HXA that Prolific's current Windows driver refuses
and that dropped its USB connection twice during bring-up. `ENABLE_UART`
stays set and the kernel still prints to `serial0`, so the capability is in
the image.

Project 2 makes it mandatory: a NanoPi NEO Air has no HDMI and no DSI, so
serial is its only console and interrupting U-Boot requires it. A CP2102 or
genuine FTDI adapter is the thing to own before then.

115200 8N1, no flow control. `ENABLE_UART = "1"` brings the console up in
firmware, before the kernel, so you see early messages and any panic.

One correction worth keeping: the firmware itself is **silent** on the UART
by default. `enable_uart=1` only guarantees the port is available at a fixed
clock for the kernel. `uart_2ndstage=1` in `config.txt` makes the firmware
narrate its own boot, which is the setting that distinguishes "the board is
not booting" from "the console is not connected".

**Over SSH you would see none of it**, because SSH needs a network that does
not exist yet at the moment things go wrong. Every board bring-up in this
this repository starts with the console for that reason, and projects 2, 3,
4 and 9 depend on it entirely.

Log to a file rather than photographing the screen: boot timings live in the
kernel timestamps, and a text log is quotable, searchable and diffable
against the next boot.

## First boot

```sh
systemctl --failed                 # expect 0 loaded units listed
systemctl status bench-status      # expect active (running)
journalctl -u bench-status -n 3    # the daemon prints its lines and polarity
bench-state show                   # expect ok
gpiodetect                         # which chip is the header
gpioinfo | grep bench-status       # the three lines, held by the daemon
```

`gpiodetect` and `gpioinfo` are the general bring-up tools, not specific to
this project. `gpioinfo` shows every line, its direction, and which process
holds it, which answers "why can I not drive this pin" immediately.

The I2C equivalent is `i2cdetect -y 1`, and it is the first command to run
against any new sensor board in projects 6, 10, 11 and 12. A device that
does not appear there has a wiring or address problem, and no amount of
driver work will help.

## Expect the colours to be wrong first

Whenever LEDs are connected, there is a 50 percent chance they are active
low, and nothing on the silkscreen says which.

```sh
gpioset -c gpiochip0 17=1     # green lights? active high
# Ctrl-C, then
gpioset -c gpiochip0 17=0     # green lights? active low
```

Then set `active_low` in `/etc/bench/leds.conf` and
`systemctl restart bench-status`. Nothing is rebuilt: the kernel does the
inversion.

## The demonstration

```sh
systemctl stop sshd.socket     # red within one poll interval
bench-state show               # failed
systemctl start sshd.socket    # green again
```

Twenty seconds, and it exercises the whole chain: systemd notices, the shell
script decides, the file changes, the C program reads it and the kernel
drives the line. Verified on the board as `ok`, then `failed`. The last step,
a diode lighting, is the deferred part.

## The SDK, which is the real deliverable

```sh
./go sdk           # populate_sdk, 30 to 60 minutes
./go sdk install   # installs into /opt/poky
./go sdk-check     # cross-compiles sdk/hello-gpiod, asserts it is aarch64
```

The SDK is a cross toolchain plus a sysroot that matches the image exactly:
the same libgpiod, the same glibc, the same headers.

```
  without the SDK                      with the SDK
  edit -> bitbake -> flash -> boot     edit -> make -> scp -> run
  minutes to hours                     seconds
```

`hello-gpiod` exists to prove the chain end to end, because it links a real
target library and only runs on the Pi. `make check` asserts the output is
an aarch64 binary, so a forgotten environment script fails loudly instead of
producing a host binary that mysteriously will not run.

Projects 5, 10, 11 and 12 compile against this. That edit cycle difference
is why Project 1 comes first.

---

Previous: [07. Verification](07-verification.md) | Next: [09. Lifecycle](09-lifecycle.md)
