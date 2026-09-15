# Project 17: a BLE gateway for the STWIN.box with BlueZ

**Board:** Raspberry Pi 3B+. **Theme:** Bluetooth LE central on Linux,
BlueZ D-Bus GATT, data pipelines.

Every other project on this bench moves data over a wire. This one moves it
over a radio, using the stock Linux Bluetooth stack rather than a vendor
library: the kernel owns the HCI transport, `bluetoothd` owns the ATT
client and the GATT database, and the gateway is an ordinary D-Bus client
that asks a daemon for notifications.

Understanding that split is the whole lesson. A program cannot open a BLE
peripheral; there is no device node for one. It calls methods on objects
that `bluetoothd` publishes on the system bus, and frames arrive as
`PropertiesChanged` signals. That is why this service needs no capabilities
and no root, and it is why the interesting failures are not in the radio
but in the layer boundaries.

The peripheral is an ST STWIN.box running ST's firmware, which exposes its
sensors through the documented BlueST GATT protocol. No firmware is written
here. The protocol is read, the frames are captured, and the decoding
happens on the Pi.

## State

**Everything is written and nothing has been run.** No image has been
built, no board has been booted, and the STWIN.box has never been near the
Pi. There are no measurements in this README, and the places that will hold
them say so.

One thing in particular is a claim rather than a measurement: **the field
table in [PROTOCOL.md](docs/PROTOCOL.md) has not been checked against a
captured frame.** The decoder tests use synthetic bytes, so they prove the
arithmetic of the decoder and not the layout of the protocol. Turning that
into a measurement is the first job after the first successful connection,
and the procedure is written down.

What is proven today, on a laptop:

| Proven | How |
|---|---|
| The decoder reads masks, scales and both frame shapes correctly | `tests/stwin-bluest-test.sh`, 29 assertions |
| An unknown mask bit stops decoding instead of shifting every field after it | the same suite, both directions |
| The ladder survives a failure at each of its four steps, and the delay doubles and resets on data | `tests/stwin-supervisor-test.sh`, 28 assertions |
| A connected but silent link is given up | the same suite |
| CSV columns are fixed by the mask, roll over daily, and mark an incomplete frame | `tests/stwin-sinks-test.sh`, 30 assertions |
| The MQTT topic and payload are what this README says | the same suite |
| Exactly one LED is lit in every state the supervisor can emit | the same suite, which is how a missing state was found |
| Every kernel symbol in `ble.cfg` exists | read out of `net/bluetooth/Kconfig`, `drivers/bluetooth/Kconfig` and `drivers/tty/serdev/Kconfig` at `rpi-6.6.y` |

## What this project adds to the repository

| Path | What |
|---|---|
| `meta-bench/recipes-kernel/linux/files/ble.cfg` | The opt-in kernel fragment: the stack and the UART transport, built in |
| `kas/bench-ble.yml` | The fragment switch, `meta-python` and `meta-networking`, on a Pi 3 |
| `meta-bench/recipes-core/images/bench-ble-image.bb` | `bench-image` plus BlueZ, the radio firmware, the Python stack and a broker |
| `meta-bench/recipes-bench/bench-stwin/` | The gateway, its service user, its unit and a udev rule |
| `meta-bench/recipes-connectivity/bluez5/` | A `main.conf`, which this image would otherwise not have at all |
| `tests/stwin-bluest-test.sh` and two more | What can be proven without a radio |

## Running it

```sh
./go check                   # about 2 minutes, no board and no radio
./go ble                     # bench-ble-image for the Raspberry Pi 3
./go flash /dev/sdX
```

On the board:

```sh
stwin-gw --scan-only                 # what is advertising, and how loud
vi /etc/bench/stwin.conf             # STWIN_MAC, STWIN_LEDS=1
systemctl restart stwin-gw
journalctl -u stwin-gw -f
mosquitto_sub -h localhost -t 'bench/stwin/#' -v
```

[docs/DESIGN.md](docs/DESIGN.md) is the methodology: where each layer
lives, the schematic, the bench layout, the connection as a sequence and
the supervisor as a state machine. Read it first.

[docs/PROTOCOL.md](docs/PROTOCOL.md) is the frame layout and the one sharp
consequence of a protocol with no length fields.

[docs/BRINGUP.md](docs/BRINGUP.md) is the board work in order, from
flashing the peripheral to a twenty-four hour run.

## Four things that are true of this image and not of a distribution

Instructions written for Raspberry Pi OS do not transfer, and each of these
would be found the hard way.

**There is no `main.conf`.** poky's `bluez5` recipe installs `network.conf`
and `input.conf` into `/etc/bluetooth` and nothing else, so `bluetoothd`
runs on the defaults compiled into it. The layer's bbappend adds one, and
it is short on purpose: every key is optional, so a file containing only
the decisions reads better than a distribution's file with three lines
uncommented.

**There is no `bluetooth` group.** Upstream BlueZ's own policy file,
`src/bluetooth.conf`, ends with a `<policy context="default">` that allows
any user to send to `org.bluez`. The group that every tutorial tells you to
join is Debian's patch to that file. `SupplementaryGroups=bluetooth` in the
unit would not tighten anything; it would stop the unit from starting,
because systemd cannot resolve a group that does not exist.

**There is no `gpio` group either, until this recipe makes one.** On a
Yocto image `/dev/gpiochip0` is root-owned and mode 0600, so a service
running as an ordinary user cannot drive an LED. The recipe creates the
group and ships the udev rule; the alternative is to run the gateway as
root, which would make every other hardening line in the unit decorative.

**The Bluetooth firmware is a separate package from the WiFi firmware.**
The CYW43455 has no flash of its own: the kernel uploads its patch RAM from
`/lib/firmware/brcm/BCM4345C0.hcd` on every boot. That file is not in
poky's `linux-firmware`, which carries only `BCM-0bb4-0306.hcd`. It comes
from meta-raspberrypi's `bluez-firmware-rpidistro` recipe, and without it
the adapter appears and `hciattach` times out.

## What is in the image beyond Project 1, and why

| Package | Why it is there | What breaks without it |
|---|---|---|
| `bluez5` | `bluetoothd`, `bluetoothctl`, `btmon` and `hciconfig` in one package | Everything. It also pulls `pi-bluetooth` on a Pi, which is what attaches the UART |
| `bluez-firmware-rpidistro-bcm4345c0-hcd` | The controller's patch RAM | `hci0` never reaches `UP RUNNING` |
| `python3-bleak` | The BLE client, and `dbus-fast` underneath it | No gateway |
| `python3-paho-mqtt` | The broker side | One of three sinks |
| `python3-gpiod` | libgpiod v2 bindings, version 2.1.3, the same library the C daemons here are compiled against | The LEDs |
| `mosquitto`, `mosquitto-clients` | A broker on the same board, so the pipeline can be proven end to end with nothing else on the bench | Nothing, but the proof needs a second machine |

Project 18 replaces that broker with one that has TLS and a private CA.
This one listens on localhost and is a test fixture rather than a product
decision.

## Acceptance criteria

| # | Criterion | Evidence | State |
|---|---|---|---|
| 1 | `btmon` shows LE Create Connection, the CCCD write of `0x0001` and Handle Value Notifications; the annotated trace is kept | `docs/first-connect.btsnoop` and a walk-through | **not started**, needs a board |
| 2 | The decoder passes against at least three frames taken from a real trace, one per characteristic | `tests/stwin-bluest-test.sh` with captured bytes | **partly met**: the suite exists and its frames are synthetic |
| 3 | The CSV grows at the rate the connection interval implies, and `mosquitto_sub` shows the same records | the rate calculation in BRINGUP.md, and both outputs side by side | **not started** |
| 4 | Removing the battery lights red within the supervision timeout plus 1 s; replacing it reaches green within 30 s with no service restart | the journal, and `NRestarts` still 0 | **logic proven against a fake link**, unproven on a radio |
| 5 | 24 hours with no restart and no growing RSS | `systemctl show -p MemoryCurrent` at both ends | **not started** |
| 6 | Runs unprivileged, and `systemd-analyze security` scores below 5 | the unit, which has a comment per directive | **written, not measured** |

Criterion 2 is the one to read carefully. A suite of 29 passing assertions
against bytes this repository invented is worth having, and it is not
evidence about the peripheral. The distinction is the difference between a
tested program and a correct one, and it is why the state section leads
with it.

## What is tested without hardware

| Check | Command | Covers |
|---|---|---|
| The protocol | `sh tests/stwin-bluest-test.sh` | Masks from UUIDs, both frame shapes, scalar against vector fields, an unknown bit above and below the known ones, a short frame, trailing bytes |
| The ladder | `sh tests/stwin-supervisor-test.sh` | State order, a failure at each step, the doubling and the cap, reset on data rather than on connection, a stalled link, that a session is always closed |
| The sinks | `sh tests/stwin-sinks-test.sh` | CSV columns per mask, daily rollover, append without a second header, an incomplete record, MQTT topic and payload, one LED per state |
| The fragment | `./go kconfig -f ble CONFIG` | Every symbol in `ble.cfg`, including the three that ask for an option to stay off |

Not covered, and only a board can cover it: that `hci0` comes up, that the
firmware loads, that `bleak` and `bluetoothd` behave like the fake link,
that the peripheral's frames match the field table, and every number in the
measurements section.

## Departures from the original scope

| # | As originally scoped | Here | Why |
|---|---|---|---|
| 1 | A standalone `stwin-gw` repository with a `pyproject.toml` | A recipe in the shared layer, installed as `bench_stwin` | The same rule the other projects follow: one tree, one layer, no twenty copies of the same pins |
| 2 | `sudo apt install bluez python3-pip`, and pip for the rest | Yocto packages, all of which exist in `meta-python` | There is no pip on the image, and a gateway whose dependencies are installed at run time is not reproducible |
| 3 | The decoder skips what it does not recognise | It stops, keeps what was above, and marks the record | A protocol with no length fields makes an unknown bit unlocatable. Skipping produces plausible numbers from wrong offsets |
| 4 | Back-off resets when a connection succeeds | It resets when data arrives | A peripheral that accepts a connection and drops it would otherwise be retried as fast as the radio allows |
| 5 | Reconnect on the disconnect signal | That, plus a stall timeout | A link that stays up and stops delivering produces no signal, and is the failure that looks like success |
| 6 | `SupplementaryGroups=bluetooth gpio` | `gpio` only, and the recipe creates it | No `bluetooth` group exists on this image, and naming it stops the unit from starting |
| 7 | One `stwin_gw` package with the BLE client inside it | The bleak import confined to one module | Three of the four modules can then be tested with no radio, which is where the assertions above come from |

## Pitfalls, and what guards each one

| Pitfall | Guard |
|---|---|
| A phone app still connected to the demo firmware | BRINGUP.md step 0, because a second central makes the connection succeed every other time |
| An active scan running during a connection attempt | `blelink.scan` stops discovery before returning, and the supervisor test asserts the order |
| `bluetoothd`'s stale GATT cache after a firmware change | BRINGUP.md names `bluetoothctl remove`, and the symptom it produces |
| A 2 s connect timeout copied from a TCP client | 15 s, because `Connect` returns only after `ServicesResolved` |
| Interval units in milliseconds rather than 1.25 ms | `main.conf` carries the units in a comment next to each value |
| The console and the radio fighting over the UART | DESIGN.md has the overlay table and says why neither is used |
| A peripheral sitting next to the receiver | The bench layout asks for one to three metres, and says the link is worse at ten centimetres |
| `RSSI` read during a connection | Logged only from advertisements, with the reason in the code and in this README |

---

[Journal](JOURNAL.md) | [Design](docs/DESIGN.md) |
[Protocol](docs/PROTOCOL.md) | [Bring-up](docs/BRINGUP.md)
