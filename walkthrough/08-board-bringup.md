# 08. Board bring-up

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

## Wiring

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

## The serial console

```sh
picocom -b 115200 --logfile boot-console.log /dev/ttyUSB0
```

115200 8N1, no flow control. This is why `ENABLE_UART = "1"` is in the kas
file: the console comes up in firmware, before the kernel, so you see early
messages and any panic.

**Over SSH you would see none of it**, because SSH needs a network that does
not exist yet at the moment things go wrong. Every board bring-up in this
book starts with the console for that reason, and projects 2, 3, 4 and 9
depend on it entirely.

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

There is a 50 percent chance the modules are active low.

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
script decides, the file changes, the C program reads it, the kernel drives
the line, the LED lights.

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
