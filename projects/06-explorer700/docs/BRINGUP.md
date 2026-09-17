# Bring-up: Project 06

Nothing in this project has been on hardware. This document is the order to
do it in, written before the session rather than after it, so that the
session is spent on the board instead of on deciding what to do next.

The ordering principle: **every step fills as many rows of
[pin-map.md](pin-map.md) as it can for the effort it costs.** One
`i2cdetect` settles four addresses. One minute with `evtest` and a thumb
settles five joystick rows, which are the least certain lines in the whole
project. A login prompt settles the console.

## Before power

Every time, and it is three questions rather than a ritual.

**What draws current and from where.** The HAT takes 5 V and ground from
the header and has no supply of its own. Its own USB socket is the CP2102's
data connection and is not a power input for the Pi. Powering the Pi
through the HAT's USB socket powers a bridge chip and nothing else.

**Which connector is data and which is power.** The Pi's own USB-C or
micro-USB is power. The HAT's socket is data. The vendor manual's photos
show both cables attached at once and that is correct.

**What is about to be driven that has not been checked against a
schematic.** On this board: GPIO16, GPIO19 and GPIO26 become outputs the
moment the overlay loads, and expander lines P4 and P7 become outputs as
soon as the expander binds. All five came from a manual's block diagram
rather than from a net list. Nothing else is on those pins because the HAT
covers the header, which is the one thing making this safe enough to do
without tracing first.

**And the DS18B20 orientation.** Manual chapter 13: it ships loose, plugs
into the three-pin header beside the display, flat side towards the
display, rounded side towards the USB and Ethernet ports. Backwards puts
3V3 across the wrong two pins.

## Step 0: which board, and the card

`raspberrypi3-64` covers the 3B and the 3B+ alike. Either works; the
specification says Pi 3 and the HAT is a 40-pin part.

**Stack the HAT on the board you intend to use and confirm it seats before
building.** `MACHINE` is compiled into the kernel, the device tree and the
rootfs, and `./go flash` does not compare the image against the card. A
`raspberrypi4-64` image on a Pi 3 does not warn, does not boot, and looks
like dead hardware. Project 8 set the machine first and paid for two kernel
rebuilds.

```bash
./go explorer
```

Then, **before the card leaves the reader**, write the WiFi credentials
onto the boot partition. The console on this board is the CP2102, which is
good, but a network route is what makes the rest of the session
copy-and-paste rather than typed a character at a time.

```bash
sudo mount /dev/sdX1 /mnt/card
printf 'SSID=%s\nPSK="%s"\n' 'NETWORK' 'PASSWORD' | sudo tee /mnt/card/wifi.conf >/dev/null
sudo sed 's/=.*/=<set>/' /mnt/card/wifi.conf
sync && sudo umount /mnt/card
```

The quotes around the passphrase are load bearing: `bench-wifi-setup`
writes `psk=` unquoted, so the value needs either 64 hex characters or its
own quotes in the file.

**A caution about the radio on this board, which is not this project's
defect and will bite here first.** `bench-image` installs
`linux-firmware-rpidistro-bcm43455`, which is the chip in a 3B+ and a 4.
`meta-raspberrypi` packages the 3B's firmware separately as
`linux-firmware-rpidistro-bcm43430`, with disjoint `FILES`, and that
package is in no image here. So on a plain 3B there is no WiFi.

Which chip the Pi 3 in the drawer has is not established. One line settles
it once the board is up:

```bash
dmesg | grep brcmfmac
```

Until then, use the 3B+ if the network matters, or work over the CP2102
console, which needs no radio at all and is step 1 anyway. This affects
Projects 6, 10 and 19 alike and is recorded in
[../JOURNAL.md](../JOURNAL.md) entry 7.

## Step 1: the console, before anything else

The CP2102 is a Silicon Labs USB-to-UART bridge soldered to the HAT. It
does exactly what the Renkforce USB/TTL cable does and is wired to the same
two pins, GPIO14 and GPIO15; the difference is that it is already attached
and the header is under the HAT.

Plug the HAT's USB socket into the PC. On Windows the device manager shows
"Silicon Labs CP210x USB to UART Bridge (COMn)". Open it at **115200**,
8N1.

```
bench-explorer login:
```

That prompt is acceptance criterion 8, and it also confirms the inference
in the pin map that the bridge is on GPIO14 and GPIO15, which is the one
row there that came from reasoning rather than from the manual's diagram.

**If there is no prompt**, in this order: is `dtoverlay=disable-bt` in
`config.txt` on the boot partition; is the baud rate 115200; is the cable a
data cable. On a Pi 3 without `disable-bt` the PL011 belongs to the
Bluetooth radio and the header gets the mini UART instead, which is the
failure the vendor manual warns about from the other side.

## Step 2: i2cdetect, which settles four rows at once

```bash
i2cdetect -y 1
```

Expected:

```
     0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
20: 20 -- -- ...                                     PCF8574
40: -- -- -- -- -- -- -- -- 48 ...                   PCF8591
60: -- -- -- -- -- -- -- -- 68 ...                   DS3231
70: -- -- -- -- -- -- 76 --                          BMP280
```

Three things to read off it.

**UU rather than a number** means a driver has claimed the address, which
is what you want and is the overlay working. A bare number means the
address answers and nothing bound.

**0x76 versus 0x77.** The manual says 0x76 and the project specification
says 0x77. Whichever appears, that is the answer; if it is 0x77, set
`bmp_addr=0x77` in the `dtoverlay=` line in `config.txt` and reboot. No
rebuild.

**0x3c must NOT appear.** The specification expects an I2C display there.
This board's panel is on SPI, and an answer at 0x3c would mean the board is
not the one this overlay was written for.

## Step 3: explorer-verify, which is the whole acceptance test

```bash
explorer-verify
```

Eleven rows. Read the status words rather than counting greens, because
three of them are not failures:

- `not-fitted` on DS18B20 means the bus is up and no probe is plugged in
- `unterminated` on PCF8591 is the correct permanent state of this board
- `unchecked` on Console means the test is at the other end of the cable

Anything `absent` is the overlay or the bus. Anything `no-driver` is
`explorer.cfg`. The distinction is the reason this script exists.

If several things are absent at once, read the firmware's own log before
anything else, because an overlay that failed to apply says so only there:

```bash
sudo vclog --msg
```

## Step 4: the joystick, which is the least certain thing in the project

```bash
evtest /dev/input/explorer-joystick
```

Push the stick in each of the four directions and press it, and write down
which `KEY_` code each one produced.

**The expected mapping, from the manual's block diagram:**

| Push | Expander line | Expect |
|---|---|---|
| Left | P0 | `KEY_LEFT` |
| Up | P1 | `KEY_UP` |
| Down | P2 | `KEY_DOWN` |
| Right | P3 | `KEY_RIGHT` |
| Press | GPIO20 | `KEY_ENTER` |

If the directions are permuted, edit the `gpios` lines of the four
`key-*` nodes in the overlay so that the mapping matches the board, rebuild
the overlay, and **update the Confirmed column in
[pin-map.md](pin-map.md) with what you saw**. A permuted joystick works
perfectly and is wrong, which is why this is a step and not an assumption.

Then the buzzer, which shares the expander:

```bash
explorer-beep 3
```

Silence with a green `explorer-verify` row means the line polarity is
inverted. `beeper_active=0` on the `dtoverlay=` line flips it.

## Step 5: the rest of the peripherals

```bash
# the clock. Needs a CR1220 in the holder to survive a power cut
hwclock -r
date

# the pressure sensor, and the second temperature source
cat /sys/bus/iio/devices/iio:device*/in_pressure_input
cat /sys/bus/iio/devices/iio:device*/in_temp_input

# the ADC. Four unterminated channels, and the point is that they read
# as noise. Wire something to the screw terminal to make them mean anything
sensors

# the 1-Wire probe, once it is plugged in
cat /sys/bus/w1/devices/w1_bus_master1/w1_master_slave_count
cat /sys/bus/w1/devices/28-*/temperature

# the LEDs
cat /sys/class/leds/explorer:led1/trigger
echo 1 > /sys/class/leds/explorer:led2/brightness

# the display
explorer-oled
```

For the DS18B20, acceptance criterion 5 is a change of more than two
degrees within a minute with the probe held between two fingers. Read it
twice rather than once: a single plausible number is not evidence that the
bus is working, and 85000 exactly is the sensor's power-on default, which
means it was read before a conversion finished.

## Step 6: the IR remote

```bash
ir-keytable -p nec,rc-5,rc-6 -t
```

Press keys. Scancodes appear. Then write them into
`/etc/rc_keymap.toml`, replacing the three examples, and load it:

```bash
ir-keytable -c -w /etc/rc_keymap.toml
evtest /dev/input/explorer-ir
```

`-c` clears the existing map first. Without it the new entries are added to
the old ones and a stale mapping survives, which looks like it worked.

**If `-t` shows pulse timings and never a scancode**, the receiver is fine
and no decoder is loaded. That is a kernel configuration answer, not a
hardware one.

## Optional: the two undocumented buttons

L3 and L4 are silkscreened on the back of the board and the manual wires
them to expander lines P5 and P6. Whether they are inputs is not settled;
the manual's arrows suggest outputs and the part is quasi-bidirectional, so
the drawing cannot decide it.

```bash
gpioinfo | grep -A9 pcf8574
gpioget $(gpiofind button-l3) $(gpiofind button-l4)
```

Read them with each button pressed and released. If they change, they are
inputs and can be added to the keys node. If they do not, leave them alone:
they may be driving something.

## Optional: interrupt-driven keys

The expander's INT output is on GPIO21, so the specification's stretch goal
is available. It is off by default because an open-drain output with no
confirmed pull-up, under an edge-triggered handler, is an interrupt storm
rather than a quiet failure.

**Prove the edges arrive first:**

```bash
gpiomon --num-events=4 --falling-edge gpiochip0 21
```

Push the joystick. Four events, and nothing at all when the board is still.
A stream of events with nothing touching the board is the storm, and it is
the reason for the order of these two steps.

**Only then, the change.** Four lines in the overlay, and it is a rebuild
rather than a parameter because it is a decision about the driver rather
than about the board:

```
	pcf8574: gpio@20 {
		compatible = "nxp,pcf8574";
		reg = <0x20>;
		gpio-controller;
		#gpio-cells = <2>;
+		interrupt-parent = <&gpio>;
+		interrupts = <21 2>;		/* GPIO21, falling edge */
+		interrupt-controller;
+		#interrupt-cells = <2>;
```

and in the keys node, `gpio-keys-polled` becomes `gpio-keys` and
`poll-interval` goes. Then measure the difference with `evtest`'s own
timestamps, which is what the stretch goal actually asks for.

`tests/explorer-overlay-test.sh` asserts that `interrupt-parent` is absent,
so making this change turns the suite red on purpose. Update the assertion
and the design document's ownership table in the same commit; a test that
is edited without the document is how the two stop describing each other.

## If it will not boot at all

The card carries the console, so there is a way in that does not need the
network. In order:

1. Is `config.txt` on the boot partition what the build put there.
   `dtparam=spi=on` in particular: without it the display fragment attaches
   to nothing and the OLED is missing while everything else works.
2. `sudo vclog --msg` for what the firmware thought of the overlay.
3. Move the card to a reader and read `/boot` from the PC. The device tree
   names say which board the image was built for: `bcm2710-*` is a Pi 3,
   `bcm2711-*` a Pi 4.
4. Rename the overlay out of the way in `config.txt` and boot without it.
   A board that boots plain and not with the overlay is an overlay problem;
   one that does neither is an image or a card problem, and those have
   different fixes.
