# Bench bring-up

Everything in this file happens once, before the first image is written. It
is separate from the README because it is about the bench, not the layer.

## Parts

| Part | Role | Interface |
|---|---|---|
| Raspberry Pi 4 | Target board, machine `raspberrypi4-64` | microSD, HDMI optional |
| Renkforce USB/TTL cable | Serial console at 115200 baud, catches boot messages before the network is up | UART0 on GPIO14/15 |
| Green, yellow, red LED modules | Status indicators driven by `bench-status` | S1 to GPIO17, GPIO27, GPIO22 |
| Breadboard and jumpers | Distributes the 3V3 and ground rails to the three modules | 40-pin header |

The LED modules carry four pins, `S1`, `S2`, `U`, `G`, and their own series
resistor. The loose 330 Ohm resistors in the inventory are therefore not
needed here. Check the board anyway: if there is no small resistor next to
the LED, put 330 Ohm in series with `S1` before connecting anything.

## Wiring the LEDs (optional, currently deferred)

The bench LED modules are Joy-IT LinkerKit LK-LED10, which need a LinkerKit
baseboard and a 2.0 mm LK-Cable. Standard 2.54 mm jumper wires do not mate
with that socket, so this section describes what to do once one of the two
options in the project README is in hand. Nothing else in the project
depends on it.

With three bare LEDs and 330 Ohm resistors, the wiring is simply GPIO17,
GPIO27 and GPIO22 through a resistor to each anode, cathodes to a ground
rail, ground rail to pin 9. That is active high and needs no configuration
change.

The table below is for the four-pin modules.

## Wiring

| Signal | Pi header pin | BCM line | Module pin |
|---|---|---|---|
| Green module signal | 11 | GPIO17 | S1 |
| Yellow module signal | 13 | GPIO27 | S1 |
| Red module signal | 15 | GPIO22 | S1 |
| Module supply, all three | 1 (3V3) | | U |
| Module ground, all three | 9 (GND) | | G |
| Not connected | | | S2 |
| Console TXD, cable RX, white | 8 | GPIO14 | |
| Console RXD, cable TX, green | 10 | GPIO15 | |
| Console ground, cable black | 6 (GND) | | G of the cable |

Two rules that protect the board:

- **`U` goes to 3V3 on pin 1, never to 5 V.** If a module is wired with the
  LED between its supply and `S1`, then `S1` sits at the supply voltage
  whenever the GPIO is not driving. A 5 V supply would put 5 V on a 3.3 V
  input. With `U` on 3V3 the worst case is harmless.
- **Leave the red 5 V lead of the USB/TTL cable disconnected.** The Pi runs
  from its own USB-C supply. Two supplies fighting over the same rail is the
  usual way a board and a cable are lost at the same time.

`S2` is left open. On these modules it is a pass-through of `S1` for
daisy-chaining, and nothing here chains.

## Which way round are the LEDs?

The modules light either when the line is driven high or when it is pulled
low, and the silkscreen rarely says which. Settle it once on the running
board and record the answer in `/etc/bench/leds.conf`:

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

## Serial console

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
