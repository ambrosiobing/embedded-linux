# Bench bring-up

Everything in this file happens once, before the first image is written. It
is separate from the README because it is about the bench, not the layer.

The schematic, the bench layout and the component diagrams are in
[DESIGN.md](DESIGN.md). This file is the procedure: what to connect, in
what order, and what to check once it is powered.

## Parts

| Part | Role | Interface |
|---|---|---|
| Raspberry Pi 4 | Target board, machine `raspberrypi4-64` | microSD, HDMI optional |
| Renkforce USB/TTL cable | Serial console at 115200 baud, catches boot messages before the network is up | UART0 on GPIO14/15 |
| Green, yellow, red LED modules | Status indicators driven by `bench-status` | S1 to GPIO17, GPIO27, GPIO22 |
| Breadboard and jumpers | Carries the common ground rail for the three modules | 40-pin header |

The LED modules carry four pins, `S1`, `S2`, `U`, `G`, and their own series
resistor, marked `R1` on the board. No loose resistor is needed here, which is
just as well because the bench has none. Check the board anyway: if there is no
small resistor next to the LED, do not connect it to a pin until one is in
series with `S1`.

## Wiring the LEDs

The bench LED modules are Joy-IT LinkerKit LK-LED10. They carry a 2.0 mm
LinkerKit socket, and beside it a 2.54 mm header with `S1`, `S2`, `U` and `G`
printed next to it, which ordinary jumper wires mate with. An earlier version
of this section said they could not be connected without a LinkerKit baseboard
and cable. That was wrong, it was taken from the manufacturer's page rather
than from the board, and it deferred this project's LED output for nothing.

Three wires per module and nothing else:

| Module pin | Goes to | Note |
|---|---|---|
| `S1` | header pin 11, 13 or 15 (GPIO17, GPIO27, GPIO22) | the signal, and the anode side |
| `G` | the breadboard ground rail | one jumper from that rail to pin 9 |
| `U` | nothing | the module lights without it |
| `S2` | nothing | unused |

Measured on a Raspberry Pi 3 Model B on Friday 2 October 2026: driving a pin
high lights its module, driving it low puts it out, and releasing the line to
an input also puts it out and reads low. That is **active high**, so
`/etc/bench/leds.conf` needs no polarity change for these modules.

Settle it on one module before wiring three. Which way round the LED sits is
not printed on the board, and a module wired the other way sinks instead, in
which case every statement above inverts and the configuration file is where
that is recorded.

The table below is for the four-pin modules.

## Wiring

| Signal | Pi header pin | BCM line | Module pin |
|---|---|---|---|
| Green module signal | 11 | GPIO17 | S1 |
| Yellow module signal | 13 | GPIO27 | S1 |
| Red module signal | 15 | GPIO22 | S1 |
| Module supply, all three | not connected | | U, see below |
| Module ground, all three | 9 (GND) | | G |
| Not connected | | | S2 |
| Console TXD, cable RX, white | 8 | GPIO14 | |
| Console RXD, cable TX, green | 10 | GPIO15 | |
| Console ground, cable black | 6 (GND) | | G of the cable |

Two rules that protect the board:

- **`U` is not needed, and if it is ever used it goes to 3V3 on pin 1, never
  to 5 V.** These modules light from `S1` and `G` alone, which was tested by
  pulling the supply jumper off a module that had one and watching nothing
  change. The rule still matters for a module wired the other way: if the LED
  sits between its supply and `S1`, then `S1` sits at the supply voltage
  whenever the GPIO is not driving, and a 5 V supply would put 5 V on a 3.3 V
  input. With `U` on 3V3, or absent, the worst case is harmless.
- **Leave the red 5 V lead of the USB/TTL cable disconnected.** The Pi runs
  from its own USB-C supply. Two supplies fighting over the same rail is the
  usual way a board and a cable are lost at the same time.

`S2` is left open. On these modules it is a pass-through of `S1` for
daisy-chaining, and nothing here chains.

## Which way round are the LEDs?

The modules light either when the line is driven high or when it is pulled
low, and the silkscreen rarely says which. **For the LK-LED10 modules on this
bench the answer is active high**, measured on Friday 2 October 2026, so
`/etc/bench/leds.conf` keeps its default. Settle it anyway on whatever module
is actually in front of you, because this is a property of the part and not of
the Raspberry Pi, and record the answer in that file:

```sh
gpioset -c gpiochip0 17=1     # green lights? active high
# Ctrl-C, then:
gpioset -c gpiochip0 17=0     # green lights? active low
```

If it is active low, set `active_low=1` in `/etc/bench/leds.conf` and
restart the daemon. Nothing is rebuilt: the kernel does the inversion, so
`bench-status` keeps asking for "active" and never reasons about volts.

```sh
systemctl restart bench-status
journalctl -u bench-status -n 3
```

The daemon prints its configuration on the first line, so the journal is the
fastest way to confirm which lines and which polarity it actually used.

## Serial console (not used in this project)

The console here is the 7 inch DSI panel, with SSH for everything else, so
nothing in this section is needed for Project 1. It is kept because the
capability is in the image, and because Project 2 cannot proceed without it:
a NanoPi NEO Air has no HDMI and no DSI, so serial is its only console, and
interrupting U-Boot requires it.

One hardware note before then. The Renkforce cable on this bench uses a
PL2303HXA, which the current Prolific Windows driver refuses to drive and
which dropped its USB connection twice during bring-up. Linux handles it
through `usbipd` and the `pl2303` driver, but a CP2102 or a genuine FTDI
FT232 costs a few euros and behaves. Worth having before Project 2.


```sh
picocom -b 115200 /dev/ttyUSB0        # or: screen /dev/ttyUSB0 115200
```

115200 8N1, no flow control. `ENABLE_UART = "1"` in the kas file is what
makes the firmware bring UART0 up early enough to catch the first messages;
without it the console starts only once the kernel is running and the
interesting failures have already gone past.

To capture the boot log as text rather than a screenshot, which is what the
portfolio evidence asks for:

```sh
picocom -b 115200 --logfile projects/01-yocto-image/docs/evidence/boot-console.log /dev/ttyUSB0
```

## WiFi

This bench has no wired network in reach, so the image joins a wireless one.
The image carries the capability; the card carries the credentials, and the
repository never sees a password.

On the laptop, turn the passphrase into the hash the supplicant actually
wants:

```sh
wpa_passphrase "YourNetwork" "yourpassword"
```

Copy the `psk=` value from its output. Then, after flashing, open the card's
FAT boot partition from any machine and create **`wifi.conf`** with two
lines:

```
SSID=YourNetwork
PSK=a1b2c3d4e5f6...
```

Notepad is fine. The setup script strips the CRLF line endings that Windows
leaves behind, which is covered by a test.

At boot, `bench-wifi-setup.service` reads that file, writes
`/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` with mode 600, and starts
the supplicant. A card without `wifi.conf` boots normally with no failed
units, so an image with no credentials is not a broken image.

To check it on the board:

```sh
networkctl
ip a
```

`wlan0` should reach `routable` with an address. Then SSH in from the laptop
as `root` with no password, and the console keyboard stops mattering.

## First checks on the board

```sh
systemctl --failed                 # expected: 0 loaded units listed
systemctl status bench-status      # expected: active (running)
bench-state show                   # expected: ok
gpiodetect                         # which chip is the header
gpioinfo | grep bench-status       # the three lines, held by the daemon
```

Then the demonstration the acceptance criteria ask for:

```sh
systemctl stop sshd.socket         # red within one poll interval
bench-state show                   # failed
systemctl start sshd.socket        # green again
```

`sshd.socket` rather than `sshd.service`: openssh in poky is socket
activated, so the socket is the unit that is supposed to stay up, and
`sshd.service` only runs while someone is logged in. The watch list in
`/etc/bench/watch.conf` names the socket for that reason.
